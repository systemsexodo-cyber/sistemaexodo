import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/produto.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import '../models/perfil_tributario.dart';
import 'supabase_service.dart';
import 'database_service.dart';
import 'local_bridge_detector.dart';
import 'nfce_contingencia_service.dart';
import 'nfce_duplicidade_helper.dart';
import 'data_service.dart';

/// Interface base para serviços de NFC-e
abstract class NFCeServiceBase {
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    double?
    valorDesconto, // Desconto total da venda (tabela de preços, promoções, manual)
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
    int? modelo, // 55 = NFe, 65 = NFCe
    int? numero, // Numero forçado a partir da UI
    int numeroInicial = 1,
    Set<int> numerosOcupados = const {},
    int?
    tpEmis, // Tipo de Emissão: 1=Normal, 2=FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
    int?
    crt, // Código de Regime Tributário: 1=Simples Nacional, 2=SN excesso, 3=Regime Normal
    // Endereço do destinatário (obrigatório para NF-e modelo 55)
    String? destLogradouro,
    String? destNumero,
    String? destComplemento,
    String? destBairro,
    String? destMunicipio,
    String? destUf,
    String? destCep,
    String? destCodMunicipio,
    String? destTelefone,
    String? destEmail,
    String? destIe,

    // Finalidade e Devolução
    int? finalidade,
    String? naturezaOperacao,
    String? chaveReferenciada,

    // Despesas acessórias
    double? valorFrete,
    double? valorSeguro,
    double? outrasDespesas,

    // Transportadora
    int? modFrete,
    String? transpNome,
    String? transpCnpjCpf,
    String? transpInscEst,
    String? transpEndereco,
    String? transpMunicipio,
    String? transpUf,
    String? transpPlaca,
    String? transpPlacaUf,
    double? transpQtdVolumes,
    String? transpEspecie,
    double? transpPesoBruto,
    double? transpPesoLiquido,

    // Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002)
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  });

  Future<Map<String, dynamic>> cancelarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
  });

  /// Inutiliza a numeração de uma nota que não será transmitida
  /// (serviço NFeInutilizacao4 da SEFAZ). Serve para "queimar" o número de uma
  /// NFC-e pendente/rejeitada, evitando que a numeração fique em sequência.
  Future<Map<String, dynamic>> inutilizarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
    int? numeroFinal,
    int? ano,
  });
}

/// Serviço de emissão local: chama o Bridge em localhost:8000
/// e salva o resultado no Supabase + PostgreSQL
class NFCeBackendService extends NFCeServiceBase {
  static const String _localBridgeUrl = 'http://localhost:8000';

  final String? _customBaseUrl;

  static final NFCeBackendService instance = NFCeBackendService._();
  NFCeBackendService._() : _customBaseUrl = null;
  NFCeBackendService({String? baseUrl}) : _customBaseUrl = baseUrl;

  String get baseUrl => _customBaseUrl ?? _localBridgeUrl;

  Future<Map<String, dynamic>> _enviarPayloadUmaVez(
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/nfce/emitir'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'status': 'erro',
          'mensagem':
              decoded['detail'] ??
              decoded['mensagem'] ??
              decoded['error'] ??
              response.body,
          '_http_status': response.statusCode,
        };
      }
      return {...decoded, '_http_status': response.statusCode};
    }
    return {
      'status': 'erro',
      'mensagem': response.body,
      '_http_status': response.statusCode,
    };
  }

  bool _respostaAutorizada(Map<String, dynamic> retorno) {
    final httpStatus = retorno['_http_status'] as int? ?? 200;
    final status = retorno['status']?.toString().toLowerCase() ?? '';
    return httpStatus >= 200 &&
        httpStatus < 300 &&
        status != 'erro' &&
        status != 'error' &&
        retorno['success'] != false;
  }

  /// Procura um número livre da série para a FRENTE depois de uma duplicidade.
  ///
  /// SALTO DIRETO: quando a SEFAZ identifica números ocupados (chave da rejeição
  /// 539, campo `numeros_duplicados` do Bridge, lista "Números ocupados SEFAZ"),
  /// o próximo candidato já nasce DEPOIS do maior deles — em vez de testar
  /// candidato a candidato até chegar lá (cada teste é uma ida completa à SEFAZ).
  ///
  /// Começa no MENOR número livre da série que não esteja identificado como
  /// ocupado (o buraco da sequência) e só avança. Antes a busca descia a partir
  /// do número rejeitado — com um rejeitado fora de ordem (ex.: 791252835) ela
  /// testava 791252834, 791252833... e autorizava a nota lá em cima,
  /// contaminando a sequência para as próximas vendas.
  ///
  /// Respostas HTTP 500 também são analisadas: o Bridge entrega rejeições
  /// SEFAZ no campo `detail`.
  Future<Map<String, dynamic>?> _encontrarNumeroLivre({
    required Map<String, dynamic> payload,
    required int aPartirDe,
    required int numeroInicial,
    required Set<int> numerosOcupados,
    Set<int> numerosIdentificados = const {},
  }) async {
    final piso = numeroInicial < 1 ? 1 : numeroInicial;
    var candidato = aPartirDe < piso ? piso : aPartirDe;
    var tentativas = 0;
    final numerosJaTestados = <int>{...numerosOcupados};

    // Salto inicial: pula de uma vez todos os números que a SEFAZ já disse
    // estar ocupados, começando após o MAIOR deles.
    for (final identificado in numerosIdentificados) {
      if (identificado > 0) numerosJaTestados.add(identificado);
    }
    final maiorIdentificado = numerosIdentificados.fold<int>(
      0,
      (atual, numero) => numero > atual ? numero : atual,
    );
    if (maiorIdentificado >= candidato) {
      candidato = maiorIdentificado + 1;
    }

    while (tentativas < 30) {
      while (numerosJaTestados.contains(candidato)) {
        candidato++;
      }
      tentativas++;
      final payloadTentativa = Map<String, dynamic>.from(payload)
        ..['numero'] = candidato
        ..['venda_numero'] = candidato.toString();
      Map<String, dynamic> retorno;
      try {
        retorno = await _enviarPayloadUmaVez(payloadTentativa);
      } catch (e) {
        retorno = {'status': 'erro', 'mensagem': e.toString()};
      }
      if (_respostaAutorizada(retorno)) {
        return {'numero': candidato, 'retorno': retorno, 'duplicidade': false};
      }
      final mensagem =
          (retorno['mensagem'] ?? retorno['detail'] ?? retorno['error'] ?? '')
              .toString();
      if (!NfceDuplicidadeHelper.ehDuplicidade(mensagem)) {
        return {'numero': candidato, 'retorno': retorno, 'duplicidade': false};
      }
      final numeroDuplicado =
          NfceDuplicidadeHelper.numeroDaChaveDuplicada(mensagem) ?? candidato;
      if (numeroDuplicado > 0) numerosJaTestados.add(numeroDuplicado);
      numerosJaTestados.add(candidato);
      // A SEFAZ confirmou este como ocupado: se ela citou um número MAIOR,
      // salta direto para depois dele; senão, segue para o próximo.
      final salto = numeroDuplicado > candidato ? numeroDuplicado : candidato;
      candidato = salto + 1;
    }
    return null;
  }

  /// Menor número livre da série — a mesma régua do aplicativo ( DataService
  /// .menorNumeroLivreNfce ): começa no [numeroInicial] e só sobe para o menor
  /// registrado se ele estiver dentro da janela da sequência.
  static int menorNumeroLivre({
    required Iterable<int> numerosOcupados,
    required int numeroInicial,
  }) => DataService.menorNumeroLivreNfce(
    numerosUsados: numerosOcupados,
    numeroInicial: numeroInicial,
  );

  Future<void> _marcarDuplicidadesComoOcupadas(
    Map<String, dynamic> payload,
    int numeroAtual,
    int? numeroChaveDuplicada,
    Map<String, dynamic>? resultadoBusca,
  ) async {
    final numeros = <int>{
      ...((payload['numeros_ocupados'] as List?) ?? const [])
          .map((valor) => int.tryParse(valor.toString()))
          .whereType<int>(),
      ...((resultadoBusca?['numeros_duplicados'] as List?) ?? const [])
          .map((valor) => int.tryParse(valor.toString()))
          .whereType<int>(),
      if (numeroAtual > 0) numeroAtual,
      if (numeroChaveDuplicada != null && numeroChaveDuplicada > 0)
        numeroChaveDuplicada,
    };
    if (resultadoBusca != null) {
      final retorno = resultadoBusca['retorno'];
      if (retorno is Map<String, dynamic>) {
        numeros.addAll(
          NfceDuplicidadeHelper.numerosDuplicados(
            (retorno['mensagem'] ?? retorno['detail'] ?? retorno['error'])
                ?.toString(),
          ),
        );
        for (final valor
            in retorno['numeros_duplicados'] as List? ?? const []) {
          final numero = int.tryParse(valor.toString());
          if (numero != null && numero > 0) numeros.add(numero);
        }
      }
    }
    final serie = (payload['serie'] ?? '1').toString();
    for (final numero in numeros) {
      await NfceContingenciaService.marcarNumeroNfceComoOcupado(
        numero: numero,
        serie: serie,
      );
    }
  }

  /// Inicializa o serviço detectando automaticamente o bridge local
  static Future<NFCeBackendService> createWithAutoDetection({
    String? customUrl,
  }) async {
    final bridgeUrl = await LocalBridgeDetector.getBridgeUrl(
      customUrl: customUrl,
    );
    return NFCeBackendService(baseUrl: bridgeUrl);
  }

  // ------------------------------------------------------------
  // PREPARAÇÃO DOS DADOS
  // ------------------------------------------------------------

  /// Valida e corrige combinações CFOP × CSOSN incompatíveis.
  ///
  /// Regras SEFAZ (Rejeição 386):
  /// - CSOSN 101/102/103/201/202/203 → CFOP deve ser 5102, 1102, 6102, 7102
  /// - CSOSN 500 → CFOP deve ser 5405, 1551, 5551, etc.
  /// - CSOSN 900 → aceita qualquer CFOP
  /// - CFOP 5949 → só aceita CSOSN 900
  static Map<String, String> _corrigirCfopCsosn(String cfop, String csosn) {
    String cfopCorrigido = cfop;
    String csosnCorrigido = csosn;

    // CFOPs aceitos para CSOSNs de tributação / imune / não-tributada
    final cfopsTributados = {
      '5102',
      '1102',
      '6102',
      '7102',
      '5101',
      '1101',
      '6101',
      '7101',
    };
    // CFOPs aceitos para CSOSN 500 (substituição tributária)
    final cfopsSt = {
      '5405',
      '1551',
      '5551',
      '6551',
      '7551',
      '5403',
      '1403',
      '6403',
    };
    // CSOSNs que usam CFOPs de tributação (inclui imune 300 e não-tributada 400)
    final csosnsTributados = {
      '101',
      '102',
      '103',
      '201',
      '202',
      '203',
      '300',
      '400',
      '600',
    };

    if (csosnsTributados.contains(csosn)) {
      // CSOSN tributado/imune/não-tributado → CFOP precisa ser da lista de tributados
      if (!cfopsTributados.contains(cfop)) {
        cfopCorrigido = '5102'; // Padrão para venda interna
      }
    } else if (csosn == '500') {
      // CSOSN ST → CFOP precisa ser da lista de ST
      if (!cfopsSt.contains(cfop) && !cfopsTributados.contains(cfop)) {
        cfopCorrigido = '5405'; // Padrão para ST interna
      }
    } else if (csosn == '900') {
      // CSOSN Outros → aceita qualquer CFOP
      // Manter CFOP original
    } else if (csosn.isEmpty) {
      // Sem CSOSN definido → padrão 102 com CFOP 5102
      if (!cfopsTributados.contains(cfop)) {
        cfopCorrigido = '5102';
      }
    }

    // Regra reversa: se CFOP é 5949, CSOSN deve ser 900
    if (cfop == '5949' && csosn != '900') {
      csosnCorrigido = '900';
    }

    return {'cfop': cfopCorrigido, 'csosn': csosnCorrigido};
  }

  Map<String, dynamic> _prepararPayload({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    double? valorDesconto,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    bool ambienteHomologacao = true,
    int? serie,
    int? modelo,
    int? numero,
    int numeroInicial = 1,
    Set<int> numerosOcupados = const {},
    int? tpEmis,
    int? crt,
    String? vendaId,
    String? vendaNumero,
    // Endereço do destinatário (obrigatório para NF-e modelo 55)
    String? destLogradouro,
    String? destNumero,
    String? destComplemento,
    String? destBairro,
    String? destMunicipio,
    String? destUf,
    String? destCep,
    String? destCodMunicipio,
    String? destTelefone,
    String? destEmail,
    String? destIe,

    // Finalidade e Devolução
    int? finalidade,
    String? naturezaOperacao,
    String? chaveReferenciada,

    // Despesas acessórias
    double? valorFrete,
    double? valorSeguro,
    double? outrasDespesas,

    // Transportadora
    int? modFrete,
    String? transpNome,
    String? transpCnpjCpf,
    String? transpInscEst,
    String? transpEndereco,
    String? transpMunicipio,
    String? transpUf,
    String? transpPlaca,
    String? transpPlacaUf,
    double? transpQtdVolumes,
    String? transpEspecie,
    double? transpPesoBruto,
    double? transpPesoLiquido,
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) {
    final serieNum = serie ?? int.tryParse(empresa.serieNFCe ?? '1') ?? 1;
    // Regime Tributário efetivo: prioriza o parâmetro, depois configuracoes['crt'],
    // depois o campo crt da empresa. (Antes a emissão lia apenas configuracoes['crt'],
    // que não era gravado no cadastro, então a nota continuava saindo como Simples Nacional.)
    final crtEfetivo =
        crt ??
        int.tryParse(empresa.configuracoes?['crt']?.toString() ?? '') ??
        empresa.crt ??
        1;
    final regimeNormal =
        crtEfetivo == 3; // 3 = Regime Normal (usa CST em vez de CSOSN)
    return {
      'empresa': {
        'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'razao_social': empresa.razaoSocial,
        'nome_fantasia': empresa.nomeFantasia ?? empresa.razaoSocial,
        'inscricao_estadual':
            empresa.inscricaoEstadual?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'logradouro': empresa.endereco ?? '',
        'numero': empresa.numero ?? 'S/N',
        'bairro': empresa.bairro ?? '',
        'municipio': empresa.cidade ?? '',
        'codigo_municipio':
            empresa.codigoIBGE ??
            empresa.configuracoes?['codigo_municipio'] ??
            '',
        'uf': empresa.estado ?? 'SP',
        'cep': empresa.cep?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'crt': crtEfetivo,
        'ambiente': ambienteHomologacao ? 2 : 1,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ??
            '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ??
            '',
        'csc': empresa.csc ?? '',
        'csc_id': empresa.cscIdToken ?? '',
      },
      'itens': produtos.map((p) {
        final qty = quantidades[p.id] ?? 1.0;

        // Buscar perfis tributários cadastrados na empresa
        final rawList =
            empresa.configuracoes?['perfis_tributarios'] as List? ?? [];
        final perfis = rawList
            .map(
              (item) =>
                  PerfilTributario.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList();

        PerfilTributario? perfil;

        // 1. Tentar pelo ID do perfil atrelado ao produto
        if (p.perfilTributarioId != null && p.perfilTributarioId!.isNotEmpty) {
          try {
            perfil = perfis.firstWhere((per) => per.id == p.perfilTributarioId);
          } catch (_) {}
        }

        // 2. Se não encontrou, tentar pelo perfil padrão (isDefault) do regime atual.
        //    Há um padrão por regime (tributado Simples = CSOSN 102 / tributado Normal = CST 00),
        //    então filtra também pelo código do regime para pegar o perfil correto.
        if (perfil == null) {
          try {
            perfil = perfis.firstWhere((per) {
              if (!per.isDefault) return false;
              final temCst = per.icmsCst?.trim().isNotEmpty == true;
              final temCsosn = per.csosn?.trim().isNotEmpty == true;
              return regimeNormal ? temCst : temCsosn;
            });
          } catch (_) {}
        }

        // Definir regras tributárias com base no perfil ou nos campos individuais do produto
        var cfop = perfil?.cfop ?? p.cfop ?? '5102';
        final ncm = perfil?.ncm ?? p.ncm ?? '00000000';
        var csosn = perfil?.csosn ?? p.csosn;

        // ═══ VALIDAÇÃO AUTOMÁTICA CFOP × CSOSN ═══
        // Corrigir incompatibilidades que causam Rejeição 386 da SEFAZ
        if (!regimeNormal && csosn != null && csosn.isNotEmpty) {
          final correcao = _corrigirCfopCsosn(cfop, csosn.trim());
          if (correcao['cfop'] != cfop) {
            print(
              '[NFCe Backend] ⚠️ CFOP corrigido: $cfop → ${correcao['cfop']} (CSOSN: $csosn)',
            );
            cfop = correcao['cfop']!;
          }
          if (correcao['csosn'] != csosn) {
            print(
              '[NFCe Backend] ⚠️ CSOSN corrigido: $csosn → ${correcao['csosn']} (CFOP: $cfop)',
            );
            csosn = correcao['csosn'];
          }
        }
        final icmsCst = perfil?.icmsCst ?? p.icmsCst;
        final pisCst = perfil?.pisCst ?? p.pisCst;
        final cofinsCst = perfil?.cofinsCst ?? p.cofinsCst;
        final icmsAliquota = perfil?.aliquotaIcms ?? p.icmsAliquota;

        final ipiCst = perfil?.ipiCst ?? p.ipiCst;
        final aliquotaIpi = perfil?.aliquotaIpi ?? p.ipiAliquota;
        final mva = perfil?.mva;
        final reducaoBaseIcms = perfil?.reducaoBaseIcms;
        final aliquotaFcp = perfil?.aliquotaFcp;
        final aliquotaIcmsInterestadual = perfil?.aliquotaIcmsInterestadual;
        final cstIbs = perfil?.cstIbs;
        final aliquotaIbs = perfil?.aliquotaIbs;
        final cstCbs = perfil?.cstCbs;
        final aliquotaCbs = perfil?.aliquotaCbs;
        final classTrib = perfil?.classTrib;

        // Impostos por regime: Regime Normal usa CST (padrão 00, ex: CFOP 5102/00);
        // Simples Nacional usa CSOSN (padrão 102, ex: CFOP 5102/102). Nunca envia os dois juntos.
        final String? csosnEnviado = regimeNormal
            ? null
            : (csosn?.trim().isNotEmpty == true ? csosn!.trim() : '102');
        final String? icmsCstEnviado = regimeNormal
            ? (icmsCst?.trim().isNotEmpty == true ? icmsCst!.trim() : '00')
            : null;

        return {
          'codigo': p.codigo ?? p.id,
          'descricao': p.nome,
          'ncm': ncm,
          'cfop': cfop,
          'quantidade': qty,
          'valor_unitario': p.preco,
          'valor_total': p.preco * qty,
          if (csosnEnviado != null && csosnEnviado.isNotEmpty)
            'icms_csosn': csosnEnviado,
          if (icmsCstEnviado != null && icmsCstEnviado.isNotEmpty)
            'icms_cst': icmsCstEnviado,
          if (pisCst != null && pisCst.isNotEmpty) 'pis_cst': pisCst,
          if (cofinsCst != null && cofinsCst.isNotEmpty)
            'cofins_cst': cofinsCst,

          // Suporte a Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002)
          'icms_reducao_bc': icmsReducaoBc ?? (reducaoBaseIcms ?? 0.0),
          'icms_base_calculo': icmsBaseCalculo ?? (p.preco * qty),
          'icms_aliquota': icmsAliquota ?? 0.0,
          'icms_valor': icmsValor ?? 0.0,
          'credito_aliquota': creditoAliquota ?? 0.0,
          'credito_valor': creditoValor ?? 0.0,

          if (ipiCst != null && ipiCst.isNotEmpty) 'ipi_cst': ipiCst,
          if (aliquotaIpi != null) 'ipi_aliquota': aliquotaIpi,
          if (mva != null) 'mva': mva,
          if (reducaoBaseIcms != null) 'reducao_base_icms': reducaoBaseIcms,
          if (aliquotaFcp != null) 'fcp_aliquota': aliquotaFcp,
          if (aliquotaIcmsInterestadual != null)
            'icms_aliquota_interestadual': aliquotaIcmsInterestadual,
          if (cstIbs != null && cstIbs.isNotEmpty) 'ibs_cst': cstIbs,
          if (aliquotaIbs != null) 'ibs_aliquota': aliquotaIbs,
          if (cstCbs != null && cstCbs.isNotEmpty) 'cbs_cst': cstCbs,
          if (aliquotaCbs != null) 'cbs_aliquota': aliquotaCbs,
          // cClassTrib (6 dígitos) — o bridge precisa dele para montar o grupo
          // <IBSCBS> com a classificação correta do produto.
          if (classTrib != null && classTrib.trim().isNotEmpty)
            'ibs_class_trib': classTrib.trim(),
        };
      }).toList(),
      'pagamentos': pagamentos
          .map(
            (p) => {
              'tipo': p.tipo,
              'valor': p.valor,
              'troco': p.troco,
              if (p.cnpjAdminCartao != null && p.cnpjAdminCartao!.isNotEmpty)
                'cnpj_admin_cartao': p.cnpjAdminCartao,
              if (p.bandeira != null) 'bandeira': p.bandeira,
              if (p.operadora != null && p.operadora!.isNotEmpty)
                'operadora': p.operadora,
              if (p.aut != null && p.aut!.isNotEmpty) 'aut': p.aut,
              if (p.tpIntegra != null && p.tpIntegra!.isNotEmpty)
                'tp_integra': p.tpIntegra,
            },
          )
          .toList(),
      'valor_total': valorTotal,
      'valor_desconto': valorDesconto ?? 0.0,
      'venda_numero': vendaNumero,
      'cpf_cliente': cpfCnpjConsumidor,
      'nome_cliente': nomeConsumidor,
      'serie': serieNum,
      'modelo': modelo ?? 65, // Envia 55 para NFe, 65 para NFCe
      'tp_emis': tpEmis ?? 1, // Tipo de Emissão (tpEmis)
      if (numeroInicial > 0) 'numero_inicial_nfce': numeroInicial,
      if (numerosOcupados.isNotEmpty)
        'numeros_ocupados': numerosOcupados.toList(),
      if (numero != null) 'numero': numero,
      'crt':
          crtEfetivo, // Regime tributário (1=Simples Nacional, 2=SN excesso, 3=Regime Normal)
      // Endereço do destinatário
      if (destLogradouro != null && destLogradouro.isNotEmpty)
        'dest_logradouro': destLogradouro,
      if (destNumero != null && destNumero.isNotEmpty)
        'dest_numero': destNumero,
      if (destComplemento != null && destComplemento.isNotEmpty)
        'dest_complemento': destComplemento,
      if (destBairro != null && destBairro.isNotEmpty)
        'dest_bairro': destBairro,
      if (destMunicipio != null && destMunicipio.isNotEmpty)
        'dest_municipio': destMunicipio,
      if (destUf != null && destUf.isNotEmpty) 'dest_uf': destUf,
      if (destCep != null && destCep.isNotEmpty) 'dest_cep': destCep,
      if (destCodMunicipio != null && destCodMunicipio.isNotEmpty)
        'dest_cod_municipio': destCodMunicipio,
      if (destTelefone != null && destTelefone.isNotEmpty)
        'dest_telefone': destTelefone,
      if (destEmail != null && destEmail.isNotEmpty) 'dest_email': destEmail,
      if (destIe != null && destIe.isNotEmpty) 'dest_ie': destIe,

      // Finalidade e Devolução
      if (finalidade != null) 'finalidade': finalidade,
      if (naturezaOperacao != null && naturezaOperacao.isNotEmpty)
        'natureza_operacao': naturezaOperacao,
      if (chaveReferenciada != null && chaveReferenciada.isNotEmpty)
        'chave_referenciada': chaveReferenciada,

      // Despesas acessórias
      if (valorFrete != null) 'valor_frete': valorFrete,
      if (valorSeguro != null) 'valor_seguro': valorSeguro,
      if (outrasDespesas != null) 'outras_despesas': outrasDespesas,

      // Transportadora
      if (modFrete != null) 'mod_frete': modFrete,
      if (transpNome != null && transpNome.isNotEmpty)
        'transp_nome': transpNome,
      if (transpCnpjCpf != null && transpCnpjCpf.isNotEmpty)
        'transp_cnpj_cpf': transpCnpjCpf,
      if (transpInscEst != null && transpInscEst.isNotEmpty)
        'transp_insc_est': transpInscEst,
      if (transpEndereco != null && transpEndereco.isNotEmpty)
        'transp_endereco': transpEndereco,
      if (transpMunicipio != null && transpMunicipio.isNotEmpty)
        'transp_municipio': transpMunicipio,
      if (transpUf != null && transpUf.isNotEmpty) 'transp_uf': transpUf,
      if (transpPlaca != null && transpPlaca.isNotEmpty)
        'transp_placa': transpPlaca,
      if (transpPlacaUf != null && transpPlacaUf.isNotEmpty)
        'transp_placa_uf': transpPlacaUf,
      if (transpQtdVolumes != null) 'transp_qtd_volumes': transpQtdVolumes,
      if (transpEspecie != null && transpEspecie.isNotEmpty)
        'transp_especie': transpEspecie,
      if (transpPesoBruto != null) 'transp_peso_bruto': transpPesoBruto,
      if (transpPesoLiquido != null) 'transp_peso_liquido': transpPesoLiquido,
    };
  }

  // ------------------------------------------------------------
  // NOTA PENDENTE (rejeição SEFAZ / falha do emissor)
  // ------------------------------------------------------------

  /// Guarda a NFC-e rejeitada na fila de pendentes e devolve o registro local
  /// com status 'pendente' (em vez de descartar a venda).
  ///
  /// Diferente da contingência (bridge offline), aqui a SEFAZ respondeu
  /// rejeitando a nota: ela fica salva em "pendentes", é retransmitida
  /// automaticamente a cada 30s (até 100 tentativas) e pode ser reenviada na
  /// mão pelo histórico de NFC-e.
  Future<NFCe> _guardarComoPendente({
    required Map<String, dynamic> payload,
    required Empresa empresa,
    required List<NFCeItem> nfceItens,
    required double valorTotal,
    required List<NFCePagamento> pagamentos,
    required String? vendaNumero,
    required String? vendaId,
    required int? serie,
    required String? cpfCnpjConsumidor,
    required String? nomeConsumidor,
    required String motivo,
    int? modelo,
  }) async {
    final now = DateTime.now();
    final numStr = vendaNumero ?? '0';
    debugPrint('>>> [NFCeLocal] Nota $numStr ficou PENDENTE ($motivo).');

    await NfceContingenciaService.instance.adicionarNaFila(
      payload: payload,
      empresaId: empresa.id,
      empresaCnpj: empresa.cnpj ?? '',
      numero: numStr,
      valorTotal: valorTotal,
      tentativaEm: now,
    );

    // A nota pendente continua DONA do número (ela será reenviada com ele), então
    // o número não pode ser reservado para reuso: a próxima venda pega o
    // seguinte (getProximoNumeroNfce considera notas pendentes como usadas).
    await NfceContingenciaService.limparNumeroReservado(empresa.id);

    final nfcePendente = NFCe(
      id: now.millisecondsSinceEpoch.toString(),
      numero: numStr,
      serie: serie?.toString() ?? empresa.serieNFCe ?? '1',
      chaveAcesso: null,
      protocolo: null,
      dataEmissao: now,
      empresaId: empresa.id,
      itens: nfceItens,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      pagamentos: pagamentos,
      xmlEnviado: null,
      // Guarda o motivo da rejeição para o histórico poder exibir o porquê
      // da nota estar pendente (a nota ainda NÃO existe na SEFAZ).
      xmlRetorno: motivo,
      qrCode: null,
      modelo: modelo ?? 65,
      status: 'pendente',
      vendaId: vendaId,
      vendaNumero: vendaNumero,
      createdAt: now,
      updatedAt: now,
    );

    // O chamador salva o retorno no DataService (adicionarNFCe), como já faz
    // com a nota em contingência.
    return nfcePendente;
  }

  /// Rejeição (inclusive 539) NÃO varre 30 números na SEFAZ na mesma emissão:
  /// isso deixava a NFC-e lenta e pulava numeração antes do reenvio. A nota
  /// fica pendente com o MESMO número; o pulo só acontece no reenvio, depois
  /// de a SEFAZ confirmar duplicidade.
  Future<NFCe> _guardarRejeicaoComoPendente({
    required Map<String, dynamic> payload,
    required Empresa empresa,
    required List<NFCeItem> nfceItens,
    required double valorTotal,
    required List<NFCePagamento> pagamentos,
    required String? vendaNumero,
    required String? vendaId,
    required int? serie,
    required String? cpfCnpjConsumidor,
    required String? nomeConsumidor,
    required String motivo,
    int? modelo,
    int? numeroAtual,
  }) async {
    if (NfceDuplicidadeHelper.ehDuplicidade(motivo)) {
      await _marcarDuplicidadesComoOcupadas(
        {...payload, 'empresa_id': empresa.id},
        numeroAtual ?? 0,
        NfceDuplicidadeHelper.numeroDaChaveDuplicada(motivo),
        {
          'numeros_duplicados': NfceDuplicidadeHelper.numerosDuplicados(motivo),
        },
      );
    }
    return _guardarComoPendente(
      payload: payload,
      empresa: empresa,
      nfceItens: nfceItens,
      valorTotal: valorTotal,
      pagamentos: pagamentos,
      vendaNumero: vendaNumero,
      vendaId: vendaId,
      serie: serie,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      motivo: motivo,
      modelo: modelo,
    );
  }

  // ------------------------------------------------------------
  // EMIT
  // ------------------------------------------------------------

  @override
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    double? valorDesconto,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
    int? modelo,
    int? numero,
    int numeroInicial = 1,
    Set<int> numerosOcupados = const {},
    int? tpEmis,
    int? crt,
    // Endereço do destinatário (obrigatório para NF-e modelo 55)
    String? destLogradouro,
    String? destNumero,
    String? destComplemento,
    String? destBairro,
    String? destMunicipio,
    String? destUf,
    String? destCep,
    String? destCodMunicipio,
    String? destTelefone,
    String? destEmail,
    String? destIe,

    // Finalidade e Devolução
    int? finalidade,
    String? naturezaOperacao,
    String? chaveReferenciada,

    // Despesas acessórias
    double? valorFrete,
    double? valorSeguro,
    double? outrasDespesas,

    // Transportadora
    int? modFrete,
    String? transpNome,
    String? transpCnpjCpf,
    String? transpInscEst,
    String? transpEndereco,
    String? transpMunicipio,
    String? transpUf,
    String? transpPlaca,
    String? transpPlacaUf,
    double? transpQtdVolumes,
    String? transpEspecie,
    double? transpPesoBruto,
    double? transpPesoLiquido,
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) async {
    debugPrint('>>> [NFCeLocal] Preparando payload...');

    final numeroDaEmissao = numero ?? int.tryParse(vendaNumero ?? '');
    final payload = _prepararPayload(
      empresa: empresa,
      produtos: produtos,
      quantidades: quantidades,
      pagamentos: pagamentos,
      valorTotal: valorTotal,
      valorDesconto: valorDesconto,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      observacoes: observacoes,
      ambienteHomologacao: ambienteHomologacao,
      serie: serie,
      modelo: modelo,
      numero: numero,
      tpEmis: tpEmis,
      crt: crt,
      vendaId: vendaId,
      vendaNumero: vendaNumero,
      destLogradouro: destLogradouro,
      destNumero: destNumero,
      destComplemento: destComplemento,
      destBairro: destBairro,
      destMunicipio: destMunicipio,
      destUf: destUf,
      destCep: destCep,
      destCodMunicipio: destCodMunicipio,
      destTelefone: destTelefone,
      destEmail: destEmail,
      destIe: destIe,

      finalidade: finalidade,
      naturezaOperacao: naturezaOperacao,
      chaveReferenciada: chaveReferenciada,

      valorFrete: valorFrete,
      valorSeguro: valorSeguro,
      outrasDespesas: outrasDespesas,

      modFrete: modFrete,
      transpNome: transpNome,
      transpCnpjCpf: transpCnpjCpf,
      transpInscEst: transpInscEst,
      transpEndereco: transpEndereco,
      transpMunicipio: transpMunicipio,
      transpUf: transpUf,
      transpPlaca: transpPlaca,
      transpPlacaUf: transpPlacaUf,
      transpQtdVolumes: transpQtdVolumes,
      transpEspecie: transpEspecie,
      transpPesoBruto: transpPesoBruto,
      transpPesoLiquido: transpPesoLiquido,
      icmsReducaoBc: icmsReducaoBc,
      icmsBaseCalculo: icmsBaseCalculo,
      icmsAliquota: icmsAliquota,
      icmsValor: icmsValor,
      creditoAliquota: creditoAliquota,
      creditoValor: creditoValor,
    );
    if (numeroDaEmissao != null) {
      payload['numero'] = numeroDaEmissao;
      payload['venda_numero'] = numeroDaEmissao.toString();
    }

    // Reconstruir lista de itens do modelo NFCeItem para salvar localmente
    final List<NFCeItem> nfceItens = produtos.map((p) {
      final qty = quantidades[p.id] ?? 1.0;
      return NFCeItem(
        produtoId: p.id,
        codigo: p.codigo ?? p.id,
        descricao: p.nome,
        ncm: p.ncm ?? '00000000',
        cfop: '5102',
        unidade: p.unidade ?? 'UN',
        quantidade: qty,
        valorUnitario: p.aplicarPromocoes(p.preco, quantidade: qty),
        valorTotal: p.aplicarPromocoes(p.preco, quantidade: qty) * qty,
      );
    }).toList();

    debugPrint('>>> [NFCeLocal] Enviando para $baseUrl/api/nfce/emitir...');

    late http.Response response;
    bool erroConexao = false;
    // [NFCe-TEMPO] Tempo da ida ao bridge: é aqui que o XML é assinado e a
    // nota é transmitida à SEFAZ. Separar este número do tempo total mostra se
    // a lentidão é fiscal ou do próprio aplicativo.
    final cronBridge = Stopwatch()..start();
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/emitir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      debugPrint(
        '>>> [NFCe-TEMPO] bridge: HTTP ${response.statusCode} em '
        '${cronBridge.elapsedMilliseconds} ms (numero=$numeroDaEmissao)',
      );
    } catch (e) {
      erroConexao = true;
      debugPrint(
        '>>> [NFCe-TEMPO] bridge: falhou em '
        '${cronBridge.elapsedMilliseconds} ms (numero=$numeroDaEmissao): $e',
      );
      // ─── MODO CONTINGÊNCIA ───────────────────────────────────────
      // Bridge offline: salvar na fila e retornar NFCe em contingência
      final now = DateTime.now();
      final numStr = vendaNumero ?? '0';
      debugPrint(
        '>>> [Contingência] Bridge offline. Enfileirando nota $numStr...',
      );

      await NfceContingenciaService.instance.adicionarNaFila(
        payload: payload,
        empresaId: empresa.id,
        empresaCnpj: empresa.cnpj ?? '',
        numero: numStr,
        valorTotal: valorTotal,
        tentativaEm: now,
      );

      // Reservar o número para não ser pulado na próxima tentativa
      final numInt = int.tryParse(numStr.replaceAll(RegExp(r'[^0-9]'), ''));
      if (numInt != null && numInt > 0) {
        await NfceContingenciaService.reservarNumero(empresa.id, numInt);
      }

      return NFCe(
        id: now.millisecondsSinceEpoch.toString(),
        numero: numStr,
        serie: serie?.toString() ?? empresa.serieNFCe ?? '1',
        chaveAcesso: null,
        protocolo: null,
        dataEmissao: now,
        empresaId: empresa.id,
        itens: nfceItens,
        valorTotal: valorTotal,
        cpfCnpjConsumidor: cpfCnpjConsumidor,
        nomeConsumidor: nomeConsumidor,
        pagamentos: pagamentos,
        xmlEnviado: null,
        qrCode: null,
        status: 'contingencia',
        vendaId: vendaId,
        vendaNumero: vendaNumero,
        createdAt: now,
        updatedAt: now,
      );
    }

    if (!erroConexao && response.statusCode != 200) {
      String detail = '';
      try {
        final errBody = jsonDecode(response.body);
        detail = errBody['detail'] ?? errBody['error'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }

      final detailLower = detail.toLowerCase();
      final isNetworkError =
          detailLower.contains('httpsconnectionpool') ||
          detailLower.contains('nameresolutionerror') ||
          detailLower.contains('failed to resolve') ||
          detailLower.contains('getaddrinfo') ||
          detailLower.contains('timeout') ||
          detailLower.contains('connection refused') ||
          detailLower.contains('connection aborted');

      if (isNetworkError) {
        final now = DateTime.now();
        final numStr = vendaNumero ?? '0';
        debugPrint(
          '>>> [Contingência] Erro de rede ou SEFAZ offline ($detail). Enfileirando nota $numStr...',
        );

        await NfceContingenciaService.instance.adicionarNaFila(
          payload: payload,
          empresaId: empresa.id,
          empresaCnpj: empresa.cnpj ?? '',
          numero: numStr,
          valorTotal: valorTotal,
          tentativaEm: now,
        );

        // Reservar o número para não ser pulado na próxima tentativa
        final numInt = int.tryParse(numStr.replaceAll(RegExp(r'[^0-9]'), ''));
        if (numInt != null && numInt > 0) {
          await NfceContingenciaService.reservarNumero(empresa.id, numInt);
        }

        return NFCe(
          id: now.millisecondsSinceEpoch.toString(),
          numero: numStr,
          serie: serie?.toString() ?? empresa.serieNFCe ?? '1',
          chaveAcesso: null,
          protocolo: null,
          dataEmissao: now,
          empresaId: empresa.id,
          itens: nfceItens,
          valorTotal: valorTotal,
          cpfCnpjConsumidor: cpfCnpjConsumidor,
          nomeConsumidor: nomeConsumidor,
          pagamentos: pagamentos,
          xmlEnviado: null,
          qrCode: null,
          status: 'contingencia',
          vendaId: vendaId,
          vendaNumero: vendaNumero,
          createdAt: now,
          updatedAt: now,
        );
      }

      // NFC-e: rejeição não descarta a venda — a nota fica PENDENTE e é
      // reenviada automaticamente. NF-e (modelo 55) segue propagando o erro.
      if ((modelo ?? 65) != 55) {
        return _guardarRejeicaoComoPendente(
          payload: payload,
          empresa: empresa,
          nfceItens: nfceItens,
          valorTotal: valorTotal,
          pagamentos: pagamentos,
          vendaNumero: vendaNumero,
          vendaId: vendaId,
          serie: serie,
          cpfCnpjConsumidor: cpfCnpjConsumidor,
          nomeConsumidor: nomeConsumidor,
          motivo: 'Erro do Emissor (${response.statusCode}): $detail',
          modelo: modelo ?? 65,
          numeroAtual: numeroDaEmissao,
        );
      }

      throw Exception('Erro do Emissor (${response.statusCode}): $detail');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('>>> [NFCeLocal] Resposta: ${data.keys.toList()}');

    // Verificar se a emissão foi bem sucedida. O bridge devolve rejeições
    // SEFAZ no HTTP 200 com status "erro".
    final statusResp = data['status']?.toString().toLowerCase() ?? '';
    if (statusResp == 'erro' || statusResp == 'error') {
      final motivo =
          (data['error'] ??
                  data['mensagem'] ??
                  data['message'] ??
                  'Erro desconhecido')
              .toString();
      if ((modelo ?? 65) != 55) {
        return _guardarRejeicaoComoPendente(
          payload: payload,
          empresa: empresa,
          nfceItens: nfceItens,
          valorTotal: valorTotal,
          pagamentos: pagamentos,
          vendaNumero: vendaNumero,
          vendaId: vendaId,
          serie: serie,
          cpfCnpjConsumidor: cpfCnpjConsumidor,
          nomeConsumidor: nomeConsumidor,
          motivo: motivo,
          modelo: modelo ?? 65,
          numeroAtual: numeroDaEmissao,
        );
      }

      throw Exception(motivo);
    }

    // Sucesso: limpar número reservado
    await NfceContingenciaService.limparNumeroReservado(empresa.id);

    // Construir objeto NFCe
    final now = DateTime.now();
    final nfce = NFCe(
      id: data['id']?.toString() ?? now.millisecondsSinceEpoch.toString(),
      numero: data['numero']?.toString() ?? numeroDaEmissao?.toString() ?? '0',
      serie:
          data['serie']?.toString() ??
          (serie?.toString() ?? empresa.serieNFCe ?? '1'),
      chaveAcesso:
          data['chave']?.toString() ??
          data['chave_acesso']?.toString() ??
          data['chNFe']?.toString(),
      protocolo: data['protocolo']?.toString() ?? data['nProt']?.toString(),
      dataEmissao: now,
      empresaId: empresa.id,
      itens: nfceItens,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      pagamentos: pagamentos,
      xmlEnviado: data['xml_autorizado']?.toString() ?? data['xml']?.toString(),
      qrCode: data['qr_code']?.toString() ?? data['qrCode']?.toString(),
      status: 'autorizada',
      vendaId: vendaId,
      vendaNumero: numeroDaEmissao?.toString() ?? vendaNumero,
      createdAt: now,
      updatedAt: now,
    );

    debugPrint('>>> [NFCeLocal] NFC-e emitida: ${nfce.chaveAcesso}');

    // Salvar no Supabase e PostgreSQL em paralelo (fire-and-forget com log de erros)
    _salvarNosbancos(nfce, empresa);

    return nfce;
  }

  // ------------------------------------------------------------
  // CANCELAR
  // ------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> cancelarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
  }) async {
    final payload = {
      'chave_acesso': nfce.chaveAcesso,
      'protocolo': nfce.protocolo,
      'justificativa': justificativa ?? 'Cancelamento via sistema',
      'empresa': {
        'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'razao_social': empresa.razaoSocial,
        'uf': empresa.estado ?? 'SP',
        'ambiente_homologacao':
            empresa.configuracoes?['ambienteHomologacao'] ?? true,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ??
            '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ??
            '',
      },
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/cancelar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true) {
        // Atualizar status no Supabase (somente com nuvem ativa)
        if (empresa.nuvemAtiva) {
          _atualizarStatusSupabase(nfce.id, 'cancelada').catchError(
            (e) =>
                debugPrint('>>> [NFCeLocal] Erro ao cancelar no Supabase: $e'),
          );
        }
        // Atualizar status no PostgreSQL
        _atualizarStatusPostgres(nfce.id, 'cancelada').catchError(
          (e) =>
              debugPrint('>>> [NFCeLocal] Erro ao cancelar no PostgreSQL: $e'),
        );
      }

      return {
        'success': data['success'] ?? false,
        'message':
            data['message'] ?? data['error'] ?? 'Cancelamento processado',
        'data': data,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ------------------------------------------------------------
  // INUTILIZAR NUMERAÇÃO
  // ------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> inutilizarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
    int? numeroFinal,
    int? ano,
  }) async {
    final numero = int.tryParse(nfce.numero.trim()) ?? 0;
    if (numero <= 0) {
      return {
        'success': false,
        'message':
            'Número da nota inválido para inutilização ("${nfce.numero}").',
      };
    }

    final payload = {
      'numero': numero,
      'numero_final': numeroFinal ?? numero,
      'serie': int.tryParse((nfce.serie).trim()) ?? 1,
      'modelo': nfce.modelo ?? 65,
      'ano': ano ?? DateTime.now().year % 100,
      'justificativa': (justificativa == null || justificativa.trim().isEmpty)
          ? 'Quebra de sequencia de numeracao por falha na emissao'
          : justificativa.trim(),
      'empresa': {
        'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'razao_social': empresa.razaoSocial,
        'uf': empresa.estado ?? 'SP',
        'ambiente_homologacao':
            empresa.configuracoes?['ambienteHomologacao'] ?? true,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ??
            '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ??
            '',
      },
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/inutilizar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final sucesso = data['success'] == true;

      if (sucesso) {
        if (empresa.nuvemAtiva) {
          _atualizarStatusSupabase(nfce.id, 'inutilizada').catchError(
            (e) => debugPrint(
              '>>> [NFCeLocal] Erro ao inutilizar no Supabase: $e',
            ),
          );
        }
        _atualizarStatusPostgres(nfce.id, 'inutilizada').catchError(
          (e) => debugPrint(
            '>>> [NFCeLocal] Erro ao inutilizar no PostgreSQL: $e',
          ),
        );
      }

      return {
        'success': sucesso,
        'ja_inutilizada': data['ja_inutilizada'] == true,
        'protocolo': data['protocolo'],
        'cStat': data['cStat'],
        'message':
            data['mensagem'] ??
            data['xMotivo'] ??
            data['error'] ??
            (sucesso
                ? 'Numeração inutilizada'
                : 'Falha ao inutilizar numeração'),
        'data': data,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ------------------------------------------------------------
  // PERSISTÊNCIA
  // ------------------------------------------------------------

  /// Salva a NFC-e emitida no Supabase e no PostgreSQL local.
  /// Roda em background - não bloqueia a UI.
  void _salvarNosbancos(NFCe nfce, Empresa empresa) {
    // 1. Supabase (somente se nuvem ativa para esta empresa)
    if (empresa.nuvemAtiva) {
      _salvarNoSupabase(nfce).catchError(
        (e) => debugPrint('>>> [NFCeLocal] Falha ao salvar no Supabase: $e'),
      );
    } else {
      debugPrint(
        '>>> [NFCeLocal] ☁️⛔ Nuvem desativada — NFC-e não enviada ao Supabase.',
      );
    }

    // 2. PostgreSQL
    _salvarNoPostgres(nfce).catchError(
      (e) => debugPrint('>>> [NFCeLocal] Falha ao salvar no PostgreSQL: $e'),
    );

    // 3. Google Drive (XML)
    if (nfce.xmlEnviado != null && nfce.xmlEnviado!.isNotEmpty) {
      // TODO: Implementar salvamento no Google Drive
      debugPrint('>>> [NFCeLocal] XML disponível para salvar no Google Drive');
    }
  }

  Future<void> _salvarNoSupabase(NFCe nfce) async {
    if (!SupabaseService.isAvailable) {
      debugPrint(
        '>>> [NFCeLocal] Supabase offline - NFC-e ficará só no PostgreSQL.',
      );
      return;
    }

    final data = {
      'id': nfce.id,
      'empresa_id': nfce.empresaId,
      'numero': nfce.numero,
      'serie': nfce.serie,
      'chave_acesso': nfce.chaveAcesso,
      'protocolo': nfce.protocolo,
      'status': nfce.status ?? 'autorizada',
      'valor_total': nfce.valorTotal,
      'cpf_cnpj_consumidor': nfce.cpfCnpjConsumidor,
      'nome_consumidor': nfce.nomeConsumidor,
      'xml_autorizado': nfce.xmlEnviado,
      'qr_code': nfce.qrCode,
      'venda_id': nfce.vendaId,
      'venda_numero': nfce.vendaNumero,
      'pagamentos': jsonEncode(nfce.pagamentos.map((p) => p.toMap()).toList()),
      'data_emissao': nfce.dataEmissao.toUtc().toIso8601String(),
      'created_at': nfce.createdAt.toUtc().toIso8601String(),
      'updated_at': nfce.updatedAt.toUtc().toIso8601String(),
    };

    try {
      await SupabaseService.instance.client.from('nfces').upsert(data);
      debugPrint('>>> [NFCeLocal] NFC-e salva no Supabase.');
    } catch (e) {
      debugPrint('>>> [NFCeLocal] Erro ao salvar NFC-e no Supabase: $e');
      rethrow;
    }
  }

  Future<void> _salvarNoPostgres(NFCe nfce) async {
    if (kIsWeb) return;

    try {
      await DatabaseService().salvarLista('nfces', [nfce.toMap()]);
      debugPrint('>>> [NFCeLocal] NFC-e salva no PostgreSQL.');
    } catch (e) {
      debugPrint('>>> [NFCeLocal] Erro ao salvar NFC-e no PostgreSQL: $e');
      rethrow;
    }
  }

  Future<void> _atualizarStatusSupabase(String nfceId, String status) async {
    if (!SupabaseService.isAvailable) return;
    await SupabaseService.instance.client
        .from('nfces')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', nfceId);
  }

  Future<void> _atualizarStatusPostgres(String nfceId, String status) async {
    if (kIsWeb) return;
    await DatabaseService().atualizarStatusNFCe(nfceId, status);
  }

  /// Verifica se o bridge está online
  Future<bool> verificarConexao() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      // Tentar endpoint raiz como fallback
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/'))
            .timeout(const Duration(seconds: 4));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Consulta NFC-e emitida
  Future<Map<String, dynamic>> consultar({
    required String chaveAcesso,
    required Empresa empresa,
  }) async {
    final payload = {
      'chave_acesso': chaveAcesso,
      'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/consultar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? data['error'] ?? 'Consulta processada',
        'data': data,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}

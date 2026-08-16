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
import 'google_drive_service.dart';
import 'local_bridge_detector.dart';
import 'nfce_contingencia_service.dart';

/// Interface base para serviços de NFC-e
abstract class NFCeServiceBase {
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    double? valorDesconto, // Desconto total da venda (tabela de preços, promoções, manual)
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
    int? modelo, // 55 = NFe, 65 = NFCe
    int? numero, // Numero forçado a partir da UI
    int? tpEmis, // Tipo de Emissão: 1=Normal, 2=FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
    int? crt, // Código de Regime Tributário: 1=Simples Nacional, 2=SN excesso, 3=Regime Normal
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

  /// Inicializa o serviço detectando automaticamente o bridge local
  static Future<NFCeBackendService> createWithAutoDetection({String? customUrl}) async {
    final bridgeUrl = await LocalBridgeDetector.getBridgeUrl(customUrl: customUrl);
    return NFCeBackendService(baseUrl: bridgeUrl);
  }

  // ------------------------------------------------------------
  // PREPARAÇÃO DOS DADOS
  // ------------------------------------------------------------

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
    final crtEfetivo = crt ??
        int.tryParse(empresa.configuracoes?['crt']?.toString() ?? '') ??
        empresa.crt ??
        1;
    final regimeNormal = crtEfetivo == 3; // 3 = Regime Normal (usa CST em vez de CSOSN)
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
        'codigo_municipio': empresa.codigoIBGE ?? empresa.configuracoes?['codigo_municipio'] ?? '',
        'uf': empresa.estado ?? 'SP',
        'cep': empresa.cep?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'crt': crtEfetivo,
        'ambiente': ambienteHomologacao ? 2 : 1,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ?? '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ?? '',
        'csc': empresa.csc ?? '',
        'csc_id': empresa.cscIdToken ?? '',
      },
      'itens': produtos.map((p) {
        final qty = quantidades[p.id] ?? 1.0;
        
        // Buscar perfis tributários cadastrados na empresa
        final rawList = empresa.configuracoes?['perfis_tributarios'] as List? ?? [];
        final perfis = rawList.map((item) => PerfilTributario.fromMap(Map<String, dynamic>.from(item))).toList();
        
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
        final cfop = perfil?.cfop ?? p.cfop ?? '5102';
        final ncm = perfil?.ncm ?? p.ncm ?? '00000000';
        final csosn = perfil?.csosn ?? p.csosn;
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
          if (csosnEnviado != null && csosnEnviado.isNotEmpty) 'csosn': csosnEnviado,
          if (icmsCstEnviado != null && icmsCstEnviado.isNotEmpty) 'icms_cst': icmsCstEnviado,
          if (pisCst != null && pisCst.isNotEmpty) 'pis_cst': pisCst,
          if (cofinsCst != null && cofinsCst.isNotEmpty) 'cofins_cst': cofinsCst,
          
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
          if (aliquotaIcmsInterestadual != null) 'icms_aliquota_interestadual': aliquotaIcmsInterestadual,
          if (cstIbs != null && cstIbs.isNotEmpty) 'ibs_cst': cstIbs,
          if (aliquotaIbs != null) 'ibs_aliquota': aliquotaIbs,
          if (cstCbs != null && cstCbs.isNotEmpty) 'cbs_cst': cstCbs,
          if (aliquotaCbs != null) 'cbs_aliquota': aliquotaCbs,
        };
      }).toList(),
      'pagamentos': pagamentos
          .map((p) => {'tipo': p.tipo, 'valor': p.valor})
          .toList(),
      'valor_total': valorTotal,
      'valor_desconto': valorDesconto ?? 0.0,
      'venda_numero': vendaNumero,
      'cpf_cliente': cpfCnpjConsumidor,
      'nome_cliente': nomeConsumidor,
      'serie': serieNum,
      'modelo': modelo ?? 65, // Envia 55 para NFe, 65 para NFCe
      'tp_emis': tpEmis ?? 1, // Tipo de Emissão (tpEmis)
      if (numero != null) 'numero': numero,
      'crt': crtEfetivo, // Regime tributário (1=Simples Nacional, 2=SN excesso, 3=Regime Normal)
      
      // Endereço do destinatário
      if (destLogradouro != null && destLogradouro.isNotEmpty) 'dest_logradouro': destLogradouro,
      if (destNumero != null && destNumero.isNotEmpty) 'dest_numero': destNumero,
      if (destComplemento != null && destComplemento.isNotEmpty) 'dest_complemento': destComplemento,
      if (destBairro != null && destBairro.isNotEmpty) 'dest_bairro': destBairro,
      if (destMunicipio != null && destMunicipio.isNotEmpty) 'dest_municipio': destMunicipio,
      if (destUf != null && destUf.isNotEmpty) 'dest_uf': destUf,
      if (destCep != null && destCep.isNotEmpty) 'dest_cep': destCep,
      if (destCodMunicipio != null && destCodMunicipio.isNotEmpty) 'dest_cod_municipio': destCodMunicipio,
      if (destTelefone != null && destTelefone.isNotEmpty) 'dest_telefone': destTelefone,
      if (destEmail != null && destEmail.isNotEmpty) 'dest_email': destEmail,
      if (destIe != null && destIe.isNotEmpty) 'dest_ie': destIe,

      // Finalidade e Devolução
      if (finalidade != null) 'finalidade': finalidade,
      if (naturezaOperacao != null && naturezaOperacao.isNotEmpty) 'natureza_operacao': naturezaOperacao,
      if (chaveReferenciada != null && chaveReferenciada.isNotEmpty) 'chave_referenciada': chaveReferenciada,

      // Despesas acessórias
      if (valorFrete != null) 'valor_frete': valorFrete,
      if (valorSeguro != null) 'valor_seguro': valorSeguro,
      if (outrasDespesas != null) 'outras_despesas': outrasDespesas,

      // Transportadora
      if (modFrete != null) 'mod_frete': modFrete,
      if (transpNome != null && transpNome.isNotEmpty) 'transp_nome': transpNome,
      if (transpCnpjCpf != null && transpCnpjCpf.isNotEmpty) 'transp_cnpj_cpf': transpCnpjCpf,
      if (transpInscEst != null && transpInscEst.isNotEmpty) 'transp_insc_est': transpInscEst,
      if (transpEndereco != null && transpEndereco.isNotEmpty) 'transp_endereco': transpEndereco,
      if (transpMunicipio != null && transpMunicipio.isNotEmpty) 'transp_municipio': transpMunicipio,
      if (transpUf != null && transpUf.isNotEmpty) 'transp_uf': transpUf,
      if (transpPlaca != null && transpPlaca.isNotEmpty) 'transp_placa': transpPlaca,
      if (transpPlacaUf != null && transpPlacaUf.isNotEmpty) 'transp_placa_uf': transpPlacaUf,
      if (transpQtdVolumes != null) 'transp_qtd_volumes': transpQtdVolumes,
      if (transpEspecie != null && transpEspecie.isNotEmpty) 'transp_especie': transpEspecie,
      if (transpPesoBruto != null) 'transp_peso_bruto': transpPesoBruto,
      if (transpPesoLiquido != null) 'transp_peso_liquido': transpPesoLiquido,
    };
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
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/emitir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      erroConexao = true;
      // ─── MODO CONTINGÊNCIA ───────────────────────────────────────
      // Bridge offline: salvar na fila e retornar NFCe em contingência
      final now = DateTime.now();
      final numStr = vendaNumero ?? '0';
      debugPrint('>>> [Contingência] Bridge offline. Enfileirando nota $numStr...');

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
      final isNetworkError = detailLower.contains('httpsconnectionpool') ||
          detailLower.contains('nameresolutionerror') ||
          detailLower.contains('failed to resolve') ||
          detailLower.contains('getaddrinfo') ||
          detailLower.contains('timeout') ||
          detailLower.contains('connection refused') ||
          detailLower.contains('connection aborted');

      if (isNetworkError) {
        final now = DateTime.now();
        final numStr = vendaNumero ?? '0';
        debugPrint('>>> [Contingência] Erro de rede ou SEFAZ offline ($detail). Enfileirando nota $numStr...');

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

      // Reservar número para reutilizar na próxima tentativa
      final numInt = int.tryParse((vendaNumero ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
      if (numInt != null && numInt > 0) {
        await NfceContingenciaService.reservarNumero(empresa.id, numInt);
      }
      throw Exception('Erro do Emissor (${response.statusCode}): $detail');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('>>> [NFCeLocal] Resposta: ${data.keys.toList()}');

    // Verificar se a emissão foi bem sucedida
    final statusResp = data['status']?.toString().toLowerCase() ?? '';
    if (statusResp == 'erro' || statusResp == 'error') {
      final msg = data['error'] ?? data['mensagem'] ?? data['message'] ?? 'Erro desconhecido';
      // Reservar número para reutilizar na próxima tentativa (rejeição SEFAZ)
      final numInt = int.tryParse((vendaNumero ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
      if (numInt != null && numInt > 0) {
        await NfceContingenciaService.reservarNumero(empresa.id, numInt);
      }
      throw Exception(msg.toString());
    }

    // Sucesso: limpar número reservado
    await NfceContingenciaService.limparNumeroReservado(empresa.id);

    // Construir objeto NFCe
    final now = DateTime.now();
    final nfce = NFCe(
      id: data['id']?.toString() ?? now.millisecondsSinceEpoch.toString(),
      numero: data['numero']?.toString() ?? vendaNumero ?? '0',
      serie:
          data['serie']?.toString() ??
          (serie?.toString() ?? empresa.serieNFCe ?? '1'),
      chaveAcesso:
          data['chave']?.toString() ??
          data['chave_acesso']?.toString() ??
          data['chNFe']?.toString(),
      protocolo:
          data['protocolo']?.toString() ?? data['nProt']?.toString(),
      dataEmissao: now,
      empresaId: empresa.id,
      itens: nfceItens,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      pagamentos: pagamentos,
      xmlEnviado:
          data['xml_autorizado']?.toString() ?? data['xml']?.toString(),
      qrCode: data['qr_code']?.toString() ?? data['qrCode']?.toString(),
      status: 'autorizada',
      vendaId: vendaId,
      vendaNumero: vendaNumero,
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
        'ambiente_homologacao': empresa.configuracoes?['ambienteHomologacao'] ?? true,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ?? '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ?? '',
      }
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
        // Atualizar status no Supabase
        _atualizarStatusSupabase(nfce.id, 'cancelada').catchError(
          (e) => debugPrint('>>> [NFCeLocal] Erro ao cancelar no Supabase: $e'),
        );
        // Atualizar status no PostgreSQL
        _atualizarStatusPostgres(nfce.id, 'cancelada').catchError(
          (e) => debugPrint('>>> [NFCeLocal] Erro ao cancelar no PostgreSQL: $e'),
        );
      }

      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? data['error'] ?? 'Cancelamento processado',
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
    // 1. Supabase
    _salvarNoSupabase(nfce).catchError(
      (e) => debugPrint('>>> [NFCeLocal] Falha ao salvar no Supabase: $e'),
    );

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
      debugPrint('>>> [NFCeLocal] Supabase offline - NFC-e ficará só no PostgreSQL.');
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
      await SupabaseService.instance.client
          .from('nfces')
          .upsert(data);
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
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
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

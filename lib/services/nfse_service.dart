import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/nfse.dart';
import '../models/servico_realizado.dart';
import '../models/empresa.dart';
import '../services/data_service.dart';

/// Resultado da tentativa de emissão da NFS-e.
class NfseEmitResult {
  final bool sucesso;
  final String? numeroNfse;
  final String? chaveAcesso;
  final String? protocolo;
  final String? mensagem;
  final dynamic respostaBruta;

  NfseEmitResult({
    required this.sucesso,
    this.numeroNfse,
    this.chaveAcesso,
    this.protocolo,
    this.mensagem,
    this.respostaBruta,
  });
}

/// Serviço de emissão de Nota Fiscal de Serviço Eletrônica (NFS-e).
///
/// Prepara os dados da nota a partir de um [ServicoRealizado], calcula o ISS,
/// monta o payload para a API da NFS-e Nacional (ADN) e envia a emissão.
///
/// Configuração necessária na empresa:
/// - [Empresa.cnpj] — CNPJ do emitente
/// - [Empresa.inscricaoMunicipal] — inscrição municipal em São José dos Campos
/// - [Empresa.codigoIBGE] — código IBGE do município (122090 para SJC)
/// - [Empresa.focusNFeToken] ou token de acesso da ADN/NFS-e Nacional
/// - [Empresa.ambienteHomologacao] — true = homologação, false = produção
class NfseService {
  final DataService dataService;
  final Empresa empresa;

  NfseService({required this.dataService, required this.empresa});

  /// CNPJ apenas dígitos.
  String get _cnpjDigits =>
      empresa.cnpj?.replaceAll(RegExp(r'[^\d]'), '') ?? '';

  /// Inscrição municipal apenas dígitos.
  String get _imDigits =>
      empresa.inscricaoMunicipal?.replaceAll(RegExp(r'[^\d]'), '') ?? '';

  /// Código IBGE do município (7 dígitos). São José dos Campos = 1220900? (usar o cadastrado na empresa).
  String get _codigoMunicipio =>
      empresa.codigoIBGE?.replaceAll(RegExp(r'[^\d]'), '') ?? '';

  /// URL base da API da NFS-e Nacional (ADN).
  String get _baseUrl =>
      (empresa.ambienteHomologacao ?? true)
          ? 'https://adn.producaorestrita.nfse.gov.br'
          : 'https://adn.nfse.gov.br';

  /// Cabeçalhos de autenticação. O token deve estar cadastrado na empresa.
  Map<String, String> get _headers {
    final token = empresa.focusNFeToken ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Constrói um [Nfse] (rascunho) a partir de um serviço recebido, sem enviar para a prefeitura.
  Nfse montarNfse(ServicoRealizado servico, {
    required String codigoServico,
    required String descricaoServico,
    required double aliquotaIss,
  }) {
    final tomadorCnpj = (servico.clienteTelefone ?? '')
        .replaceAll(RegExp(r'[^\d]'), '');
    final tomadorNome = servico.clienteNome ?? 'Consumidor final';

    return Nfse(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      servicoId: servico.id,
      numeroServico: servico.numero,
      dataEmissao: DateTime.now(),
      valorServicos: servico.totalGeral,
      aliquotaIss: aliquotaIss,
      valorIss: servico.totalGeral * (aliquotaIss / 100),
      valorTotal: servico.totalGeral * (1 + aliquotaIss / 100),
      codigoServico: codigoServico,
      descricaoServico: descricaoServico,
      cpfCnpjTomador: tomadorCnpj.isEmpty ? '00000000000' : tomadorCnpj,
      nomeTomador: tomadorNome,
      status: NfseStatus.rascunho,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Salva o rascunho da NFS-e vinculada ao serviço no Supabase/local.
  Future<void> salvarRascunho(Nfse nfse) async {
    // TODO: persistir na tabela nfses quando existir; por enquanto mantém em memória
    // via dataService se houver suporte. Aqui apenas registra no log para depuração.
    print('>>> [NFS-e] Rascunho salvo: ${nfse.numeroServico} - ${nfse.valorTotal}');
  }

  /// Envia a NFS-e para a API da NFS-e Nacional (ADN) e retorna o resultado.
  ///
  /// Requer que a empresa tenha `focusNFeToken` (token de acesso da ADN) preenchido.
  Future<NfseEmitResult> emitir(Nfse nfse) async {
    if (empresa.focusNFeToken == null || empresa.focusNFeToken!.isEmpty) {
      return NfseEmitResult(
        sucesso: false,
        mensagem:
            'Token de acesso da NFS-e Nacional não configurado na empresa. '
            'Cadastre o token em Cadastro de Empresa antes de emitir.',
      );
    }

    if (_cnpjDigits.isEmpty) {
      return NfseEmitResult(
        sucesso: false,
        mensagem: 'CNPJ da empresa não cadastrado.',
      );
    }

    final payload = {
      'emitente': {
        'cnpj': _cnpjDigits,
        'inscricao_municipal': _imDigits,
        'codigo_municipio': _codigoMunicipio,
        'razao_social': empresa.razaoSocial,
        'nome_fantasia': empresa.nomeFantasia,
        'endereco': empresa.endereco,
        'numero': empresa.numero,
        'complemento': empresa.complemento,
        'bairro': empresa.bairro,
        'municipio': empresa.cidade,
        'uf': empresa.estado,
        'cep': empresa.cep,
      },
      'tomador': {
        'cpf_cnpj': nfse.cpfCnpjTomador,
        'nome': nfse.nomeTomador,
      },
      'servico': {
        'codigo': nfse.codigoServico,
        'descricao': nfse.descricaoServico,
        'valor_servicos': nfse.valorServicos.toStringAsFixed(2),
        'aliquota_iss': nfse.aliquotaIss.toStringAsFixed(2),
        'valor_iss': nfse.valorIss.toStringAsFixed(2),
        'valor_total': nfse.valorTotal.toStringAsFixed(2),
      },
      'referencia': nfse.numeroServico, // número do serviço no sistema (SRV-...)
      'ambiente': (empresa.ambienteHomologacao ?? true) ? 'homologacao' : 'producao',
    };

    print('>>> [NFS-e] Enviando para ${_baseUrl}/nfse/emitir');
    print('>>> [NFS-e] Payload: ${jsonEncode(payload)}');

    try {
      final resposta = await http.post(
        Uri.parse('${_baseUrl}/nfse/emitir'),
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      print('>>> [NFS-e] Resposta status: ${resposta.statusCode}');
      print('>>> [NFS-e] Resposta corpo: ${resposta.body}');

      if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
        final dados = jsonDecode(resposta.body) as Map<String, dynamic>;
        return NfseEmitResult(
          sucesso: true,
          numeroNfse: dados['numero_nfse']?.toString() ?? dados['numeroNfse']?.toString(),
          chaveAcesso: dados['chave_acesso']?.toString() ?? dados['chaveAcesso']?.toString(),
          protocolo: dados['protocolo']?.toString(),
          mensagem: 'NFS-e emitida com sucesso.',
          respostaBruta: dados,
        );
      } else {
        return NfseEmitResult(
          sucesso: false,
          mensagem: 'Erro ${resposta.statusCode} ao emitir NFS-e.',
          respostaBruta: resposta.body,
        );
      }
    } catch (e) {
      return NfseEmitResult(
        sucesso: false,
        mensagem: 'Erro ao conectar com a NFS-e Nacional: $e',
      );
    }
  }

  /// Consulta o status de uma NFS-e já emitida pelo número/chave.
  ///
  /// Útil para verificar se a nota foi autorizada pela prefeitura.
  Future<Map<String, dynamic>?> consultar(String chaveAcesso) async {
    try {
      final resposta = await http.get(
        Uri.parse('${_baseUrl}/nfse/consultar/$chaveAcesso'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
        return jsonDecode(resposta.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('>>> [NFS-e] Erro ao consultar: $e');
      return null;
    }
  }
}

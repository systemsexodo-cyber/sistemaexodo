import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import 'package:flutter/foundation.dart';

/// Serviço de emissão NFC-e usando API pronta (Focus NFe, NFe.io, etc)
/// Funciona 100% no Flutter - NÃO precisa de backend!
class NFCeApiService {
  final String apiToken;
  final bool ambienteHomologacao;
  final String? baseUrl; // Se null, usa Focus NFe
  
  NFCeApiService({
    required this.apiToken,
    this.ambienteHomologacao = true,
    this.baseUrl,
  });

  String get _baseUrl {
    if (baseUrl != null) return baseUrl!;
    
    // Focus NFe
    return ambienteHomologacao
        ? 'https://homologacao.focusnfe.com.br/v2'
        : 'https://api.focusnfe.com.br/v2';
  }

  /// Emite uma NFC-e usando API pronta
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
  }) async {
    try {
      debugPrint('>>> [NFCeApi] Iniciando emissão via API...');
      
      // Preparar dados da requisição
      final body = _prepararDados(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        valorTotal: valorTotal,
        cpfCnpjConsumidor: cpfCnpjConsumidor,
        nomeConsumidor: nomeConsumidor,
        observacoes: observacoes,
      );

      // Fazer requisição
      final url = Uri.parse('$_baseUrl/nfce');
      final headers = {
        'Authorization': 'Token $apiToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      debugPrint('>>> [NFCeApi] Enviando requisição para: $url');
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('Timeout ao comunicar com a API');
        },
      );

      debugPrint('>>> [NFCeApi] Status: ${response.statusCode}');
      debugPrint('>>> [NFCeApi] Resposta: ${response.body}');

      // Processar resposta
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _processarRespostaSucesso(data, empresa);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(error['mensagem'] ?? 'Erro ao emitir NFC-e');
      }
    } catch (e) {
      debugPrint('>>> [NFCeApi] Erro: $e');
      rethrow;
    }
  }

  /// Prepara dados no formato da API
  Map<String, dynamic> _prepararDados({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
  }) {
    // Referência única (timestamp)
    final ref = DateTime.now().millisecondsSinceEpoch.toString();

    // Preparar itens
    final itens = <Map<String, dynamic>>[];
    for (final produto in produtos) {
      final quantidade = quantidades[produto.id] ?? 1.0;
      final valorUnitario = produto.precoAtual;
      final valorTotalItem = valorUnitario * quantidade;

      itens.add({
        'codigo_produto': produto.codigo ?? produto.id,
        'descricao': produto.nome,
        'ncm': produto.ncm ?? '00000000',
        'cfop': produto.cfop ?? '5102',
        'unidade_comercial': produto.unidade,
        'quantidade_comercial': quantidade.toStringAsFixed(3),
        'valor_unitario_comercial': valorUnitario.toStringAsFixed(2),
        'valor_total': valorTotalItem.toStringAsFixed(2),
        'icms_origem': produto.origem ?? '0',
        'icms_situacao_tributaria': produto.csosn ?? produto.icmsCst ?? '102',
        'icms_aliquota': (produto.icmsAliquota ?? 0).toStringAsFixed(2),
        if (produto.codigoBarras != null)
          'codigo_barras_comercial': produto.codigoBarras,
      });
    }

    // Preparar pagamentos
    final formasPagamento = <Map<String, dynamic>>[];
    for (final pagamento in pagamentos) {
      formasPagamento.add({
        'forma_pagamento': _mapearTipoPagamento(pagamento.tipo),
        'valor': pagamento.valor.toStringAsFixed(2),
      });
    }

    // Montar body
    return {
      'ref': ref,
      'cnpj_emitente': empresa.cnpj?.replaceAll(RegExp(r'[^\d]'), '') ?? '',
      'natureza_operacao': 'VENDA',
      'data_emissao': DateTime.now().toIso8601String(),
      'tipo_documento': '1', // 1=Saída
      'local_destino': '1', // 1=Operação interna
      'finalidade': '1', // 1=Normal
      'consumidor_final': '1', // 1=Sim
      'presenca_comprador': '1', // 1=Presencial
      'itens': itens,
      'valor_total': valorTotal.toStringAsFixed(2),
      'formas_pagamento': formasPagamento,
      if (cpfCnpjConsumidor != null)
        'cpf_consumidor': cpfCnpjConsumidor.replaceAll(RegExp(r'[^\d]'), ''),
      if (nomeConsumidor != null) 'nome_consumidor': nomeConsumidor,
      if (observacoes != null && observacoes.isNotEmpty)
        'informacoes_adicionais_contribuinte': observacoes,
    };
  }

  /// Mapeia tipo de pagamento para código da API
  String _mapearTipoPagamento(String tipo) {
    // Códigos Focus NFe
    const map = {
      '01': '01', // Dinheiro
      '02': '02', // Cheque
      '03': '03', // Cartão de Crédito
      '04': '04', // Cartão de Débito
      '05': '05', // Crédito Loja
      '10': '10', // Vale Alimentação
      '11': '11', // Vale Refeição
      '12': '12', // Vale Presente
      '13': '13', // Vale Combustível
      '99': '99', // Outros
    };
    return map[tipo] ?? '99';
  }

  /// Processa resposta de sucesso
  NFCe _processarRespostaSucesso(Map<String, dynamic> data, Empresa empresa) {
    final status = data['status'] as String? ?? '';
    final chaveAcesso = data['chave_nfe'] as String? ?? '';
    final protocolo = data['protocolo'] as String? ?? '';
    final qrCode = data['url_qrcode'] as String? ?? data['qr_code'] as String? ?? '';
    final xml = data['xml'] as String? ?? '';

    if (status == 'autorizado' || status == 'processado') {
      return NFCe(
        id: chaveAcesso,
        chaveAcesso: chaveAcesso,
        numero: data['numero'] as String? ?? '',
        serie: data['serie'] as String? ?? '1',
        protocolo: protocolo,
        status: 'autorizada',
        xml: xml,
        qrCode: qrCode,
        dataEmissao: DateTime.now(),
        empresaId: empresa.id,
      );
    } else {
      throw Exception('NFC-e não autorizada: ${data['mensagem'] ?? status}');
    }
  }

  /// Consulta status de uma NFC-e
  Future<Map<String, dynamic>> consultar(String referencia) async {
    try {
      final url = Uri.parse('$_baseUrl/nfce/$referencia');
      final headers = {
        'Authorization': 'Token $apiToken',
        'Accept': 'application/json',
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Erro ao consultar NFC-e');
      }
    } catch (e) {
      debugPrint('>>> [NFCeApi] Erro ao consultar: $e');
      rethrow;
    }
  }

  /// Cancela uma NFC-e
  Future<void> cancelar(String chaveAcesso, String justificativa) async {
    try {
      final url = Uri.parse('$_baseUrl/nfce/$chaveAcesso/cancelamento');
      final headers = {
        'Authorization': 'Token $apiToken',
        'Content-Type': 'application/json',
      };

      final body = {
        'justificativa': justificativa,
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(error['mensagem'] ?? 'Erro ao cancelar NFC-e');
      }
    } catch (e) {
      debugPrint('>>> [NFCeApi] Erro ao cancelar: $e');
      rethrow;
    }
  }
}



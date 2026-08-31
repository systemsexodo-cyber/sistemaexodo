import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import 'package:flutter/foundation.dart';

/// Serviço simplificado para Focus NFe
/// Funciona 100% no Flutter - NÃO precisa de backend!
/// 
/// Como usar:
/// 1. Crie conta em https://focusnfe.com.br
/// 2. Obtenha seu token de API
/// 3. Configure o token na empresa
/// 4. Use este serviço para emitir NFC-e
class NFCeFocusService {
  final String apiToken;
  final bool ambienteHomologacao;

  NFCeFocusService({
    required this.apiToken,
    this.ambienteHomologacao = true,
  });

  String get baseUrl => ambienteHomologacao
      ? 'https://homologacao.focusnfe.com.br/v2'
      : 'https://api.focusnfe.com.br/v2';

  /// Emite uma NFC-e
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
      debugPrint('>>> [FocusNFe] Emitindo NFC-e...');

      // Preparar dados
      final ref = DateTime.now().millisecondsSinceEpoch.toString();
      
      final body = {
        'ref': ref,
        'cnpj_emitente': empresa.cnpj?.replaceAll(RegExp(r'[^\d]'), '') ?? '',
        'natureza_operacao': 'VENDA',
        'data_emissao': DateTime.now().toIso8601String(),
        'tipo_documento': '1',
        'local_destino': '1',
        'finalidade': '1',
        'consumidor_final': '1',
        'presenca_comprador': '1',
        'itens': produtos.map((p) {
          final qtd = quantidades[p.id] ?? 1.0;
        
          String cfopFinal = p.cfop?.replaceAll(RegExp(r'[^0-9]'), '') ?? '5102';
          String csosnFinal = p.csosn?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          // Validação CFOP × CSOSN (Rejeição SEFAZ 386)
          if (empresa.crt != 3 && csosnFinal.isNotEmpty) {
            final correcao = _corrigirCfopCsosn(cfopFinal, csosnFinal);
            cfopFinal = correcao['cfop']!;
            csosnFinal = correcao['csosn']!;
          } else if ((csosnFinal == '500' || p.icmsCst == '60') && (cfopFinal == '5102' || cfopFinal == '5101')) {
            cfopFinal = '5405';
          }
          final valorUnitario = p.aplicarPromocoes(p.preco, quantidade: qtd);
          return {
            'codigo_produto': p.codigo ?? p.id,
            'descricao': p.nome,
            'ncm': p.ncm?.replaceAll(RegExp(r'[^0-9]'), '') ?? '00000000',
            'cfop': cfopFinal,
            'unidade_comercial': p.unidade,
            'quantidade_comercial': qtd.toStringAsFixed(3),
            'valor_unitario_comercial': valorUnitario.toStringAsFixed(2),
            'valor_total': (valorUnitario * qtd).toStringAsFixed(2),
            'icms_origem': p.origem ?? '0',
            'icms_situacao_tributaria': (empresa.crt == 3) ? (p.icmsCst ?? '00') : (p.csosn ?? '102'),
            'icms_aliquota': (p.icmsAliquota ?? 0).toStringAsFixed(2),
          };
        }).toList(),
        'valor_total': valorTotal.toStringAsFixed(2),
        'formas_pagamento': pagamentos.map((p) => {
          'forma_pagamento': _mapearPagamento(p.tipo),
          'valor': p.valor.toStringAsFixed(2),
        }).toList(),
        if (cpfCnpjConsumidor != null)
          'cpf_consumidor': cpfCnpjConsumidor.replaceAll(RegExp(r'[^\d]'), ''),
        if (nomeConsumidor != null) 'nome_consumidor': nomeConsumidor,
        if (observacoes != null && observacoes.isNotEmpty)
          'informacoes_adicionais_contribuinte': observacoes,
      };

      // Enviar requisição
      final url = Uri.parse('$baseUrl/nfce');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Token $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (data['status'] == 'autorizado' || data['status'] == 'processado') {
          // Converter produtos para NFCeItem
          final itens = produtos.map((p) {
            final qtd = quantidades[p.id] ?? 1.0;
            
            String cfopFinal = p.cfop?.replaceAll(RegExp(r'[^0-9]'), '') ?? '5102';
            final csosnRaw = p.csosn?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
            final cstRaw = p.icmsCst?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
            
            if ((csosnRaw == '500' || cstRaw == '60') && (cfopFinal == '5102' || cfopFinal == '5101')) {
              cfopFinal = '5405';
            }

            return NFCeItem(
              produtoId: p.id,
              codigo: p.codigo ?? p.id,
              descricao: p.nome,
              quantidade: qtd,
              valorUnitario: p.aplicarPromocoes(p.preco, quantidade: qtd),
              valorTotal: p.aplicarPromocoes(p.preco, quantidade: qtd) * qtd,
              ncm: p.ncm?.replaceAll(RegExp(r'[^0-9]'), '') ?? '00000000',
              cfop: cfopFinal,
              unidade: p.unidade,
              origem: p.origem ?? '0',
              csosn: p.csosn ?? (empresa.crt == 3 ? null : '102'),
              icmsCst: p.icmsCst ?? (empresa.crt == 3 ? '00' : null),
              icmsAliquota: p.icmsAliquota,
            );
          }).toList();

          return NFCe(
            id: data['chave_nfe'] as String? ?? '',
            numero: data['numero']?.toString() ?? '',
            serie: data['serie']?.toString() ?? '1',
            dataEmissao: DateTime.now(),
            empresaId: empresa.id,
            itens: itens,
            valorTotal: valorTotal,
            pagamentos: pagamentos,
            chaveAcesso: data['chave_nfe'] as String? ?? '',
            protocolo: data['protocolo'] as String? ?? '',
            status: 'autorizada',
            qrCode: data['url_qrcode'] as String? ?? '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        } else {
          throw Exception(data['mensagem'] ?? 'NFC-e não autorizada');
        }
      } else {
        throw Exception(data['mensagem'] ?? 'Erro ao emitir NFC-e');
      }
    } catch (e) {
      debugPrint('>>> [FocusNFe] Erro: $e');
      rethrow;
    }
  }

  String _mapearPagamento(String tipo) {
    const map = {
      '01': '01', // Dinheiro
      '02': '02', // Cheque
      '03': '03', // Cartão de Crédito
      '04': '04', // Cartão de Débito
      '99': '99', // Outros
    };
    return map[tipo] ?? '99';
  }

  /// Valida e corrige combinações CFOP × CSOSN incompatíveis (Rejeição 386).
  static Map<String, String> _corrigirCfopCsosn(String cfop, String csosn) {
    String cfopCorrigido = cfop;
    String csosnCorrigido = csosn;

    // CFOPs aceitos para CSOSNs de tributação / imune / não-tributada
    final cfopsTributados = {'5102', '1102', '6102', '7102', '5101', '1101', '6101', '7101'};
    // CFOPs aceitos para CSOSN 500 (substituição tributária)
    final cfopsSt = {'5405', '1551', '5551', '6551', '7551', '5403', '1403', '6403'};
    // CSOSNs que usam CFOPs de tributação (inclui imune 300 e não-tributada 400)
    final csosnsTributados = {'101', '102', '103', '201', '202', '203', '300', '400', '600'};

    if (csosnsTributados.contains(csosn)) {
      if (!cfopsTributados.contains(cfop)) {
        cfopCorrigido = '5102';
      }
    } else if (csosn == '500') {
      if (!cfopsSt.contains(cfop) && !cfopsTributados.contains(cfop)) {
        cfopCorrigido = '5405';
      }
    } else if (csosn == '900') {
      // CSOSN Outros → aceita qualquer CFOP
    } else if (cfop == '5949' && csosn != '900') {
      csosnCorrigido = '900';
    }

    return {'cfop': cfopCorrigido, 'csosn': csosnCorrigido};
  }
}



import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/carrinho_item.dart';
import '../models/cliente.dart';
import '../models/empresa.dart';

class NfceService {
  // URL base dinâmica para permitir uso de túneis (Ngrok/Zrok) quando no Firebase
  String _baseUrl = 'http://localhost:8000';

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    print('>>> [NFC-e] Nova URL configurada: $_baseUrl');
  }

  String get baseUrl => _baseUrl;

  /// Envia os dados da venda para o backend Python emitir a NFC-e
  Future<Map<String, dynamic>> emitirNfce({
    required int numeroVenda,
    required Empresa empresa,
    required List<CarrinhoItem> itens,
    Cliente? cliente,
    String? cpfNota,
    double valorTotal = 0.0,
    double valorDesconto = 0.0,
  }) async {
    final url = Uri.parse('$_baseUrl/emitir_nfce');

    // Monta o payload JSON esperado pelo Pydantic do backend
    final Map<String, dynamic> payload = {
      'numero': numeroVenda,
      'data_emissao': DateTime.now().toIso8601String(),
      'cpf_cliente': cpfNota ?? cliente?.cpfCnpj,
      'valor_total': valorTotal,
      'valor_desconto': valorDesconto,
      'itens': itens.map((item) {
        return {
          'codigo': item.itemId,
          'descricao': item.nome,
          'ncm': '00000000', // TODO: Pegar do produto real
          'cfop': '5102',
          'quantidade': item.quantidade.toDouble(),
          'valor_unitario': item.preco,
          'valor_total': item.preco * item.quantidade,
        };
      }).toList(),
    };

    try {
      print('>>> [NFC-e] Enviando requisição para $_baseUrl...');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);
        print('>>> [NFC-e] Nota emitida com sucesso!');
        return dados;
      } else {
        print('>>> [NFC-e] Erro do servidor: ${response.statusCode} ${response.body}');
        throw Exception('Falha ao emitir NFC-e: ${response.body}');
      }
    } catch (e) {
      print('>>> [NFC-e] Erro de conexão: $e');
      throw Exception('Não foi possível conectar ao servidor de NFC-e. Verifique se o backend Python está rodando.');
    }
  }
  
  /// Verifica se o backend Python está online
  Future<bool> verificarStatusBackend() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

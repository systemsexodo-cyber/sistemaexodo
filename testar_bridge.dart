import 'dart:convert';
import 'dart:io';

/// Script para testar endpoints do bridge NFC-e
Future<void> main() async {
  const baseUrl = 'http://localhost:8000';
  
  print('🔍 Testando Bridge NFC-e em $baseUrl\n');
  
  // Testar 1: Status check
  await testEndpoint('GET', '$baseUrl/', null);
  
  // Testar 2: Endpoint antigo /emitir
  await testEndpoint('POST', '$baseUrl/emitir', getTestPayload());
  
  // Testar 3: Endpoint novo /api/nfce/emitir
  await testEndpoint('POST', '$baseUrl/api/nfce/emitir', getTestPayload());
  
  print('\n✅ Testes concluídos!');
}

Future<void> testEndpoint(String method, String url, Map<String, dynamic>? body) async {
  print('📡 Testando: $method $url');
  
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    
    HttpClientRequest request;
    if (method == 'POST') {
      request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      if (body != null) {
        request.add(utf8.encode(jsonEncode(body)));
      }
    } else {
      request = await client.getUrl(Uri.parse(url));
    }
    
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    client.close();
    
    print('   Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      print('   ✅ Sucesso!');
      if (responseBody.isNotEmpty) {
        print('   Resposta: ${responseBody.substring(0, 100)}...');
      }
    } else {
      print('   ❌ Erro: ${response.statusCode}');
      print('   Resposta: $responseBody');
    }
    
  } catch (e) {
    print('   ❌ Falha: $e');
  }
  
  print('');
}

Map<String, dynamic> getTestPayload() {
  return {
    "empresa": {
      "cnpj": "12345678901234",
      "razao_social": "Empresa Teste LTDA",
      "nome_fantasia": "Teste",
      "inscricao_estadual": "123456789",
      "logradouro": "Rua Teste",
      "numero": "123",
      "bairro": "Centro",
      "municipio": "São Paulo",
      "codigo_municipio": "3550308",
      "uf": "SP",
      "cep": "01234567",
      "crt": 1,
      "ambiente": 2, // Homologação
      "certificado_base64": "",
      "senha_certificado": "",
      "csc": "",
      "csc_id": ""
    },
    "itens": [
      {
        "codigo": "001",
        "descricao": "Produto Teste",
        "ncm": "00000000",
        "cfop": "5102",
        "quantidade": 1.0,
        "valor_unitario": 10.0,
        "valor_total": 10.0
      }
    ],
    "pagamentos": [
      {
        "tipo": "01",
        "valor": 10.0
      }
    ],
    "valor_total": 10.0,
    "venda_numero": "001",
    "cpf_cliente": "",
    "serie": "1"
  };
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  test('vendas_balcao conta como dado novo na sincronização', () {
    final data = {
      'vendas_balcao': [
        {'id': 'venda-1', 'empresa_id': 'empresa-1'},
      ],
    };

    expect(DataService.possuiDadosParaSincronizacao(data), isTrue);
  });

  test('lista vazia não deve ser considerada como dado novo', () {
    final data = {
      'vendas_balcao': <Map<String, dynamic>>[],
      'pedidos': <Map<String, dynamic>>[],
    };

    expect(DataService.possuiDadosParaSincronizacao(data), isFalse);
  });
}

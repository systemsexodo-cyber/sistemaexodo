import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';

void main() {
  test('test loading and parsing of all sales in database', () async {
    final db = DatabaseService();
    db.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');

    print('>>> Loading sales list from DatabaseService...');
    final list = await db.carregarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_exodo_vendas_balcao');
    print('>>> Loaded list size: ${list.length}');

    int parsedCount = 0;
    int failedCount = 0;

    for (final map in list) {
      try {
        final venda = VendaBalcao.fromMap(map);
        parsedCount++;
      } catch (e, st) {
        failedCount++;
        print('>>> ❌ FAILED TO PARSE SALE ID: ${map['id']} / Numero: ${map['numero']}');
        print('Error: $e');
        print('Stack trace: $st');
        print('Map content: $map');
        print('-----------------------------------------');
      }
    }

    print('>>> Total parsed successfully: $parsedCount');
    print('>>> Total failed to parse: $failedCount');

    expect(failedCount, equals(0));
  });

  test('test parsing null-valued map to simulate sync-test-999', () {
    final map = {
      'id': 'sync-test-999',
      'numero': null,
      'cancelado': null,
      'created_at': null,
      'updated_at': null,
      'data_venda': null,
    };
    final venda = VendaBalcao.fromMap(map);
    print('Successfully parsed null map! updatedAt: ${venda.updatedAt}');
  });
}

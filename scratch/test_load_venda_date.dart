import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  test('Test load data_venda in Dart', () async {
    final dbService = DatabaseService();
    dbService.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');
    final list = await dbService.carregarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_exodo_vendas_balcao');
    
    print('=== VENDAS CARREGADAS PELO DART ===');
    for (var i = 0; i < 5 && i < list.length; i++) {
      final item = list[i];
      print('Venda ${item['numero']}:');
      print('  ID: ${item['id']}');
      print('  dataVenda (raw in map): ${item['dataVenda']} (${item['dataVenda'].runtimeType})');
      if (item['dataVenda'] is DateTime) {
        final dt = item['dataVenda'] as DateTime;
        print('    isUtc: ${dt.isUtc}');
        print('    toLocal(): ${dt.toLocal()}');
      }
    }
  });
}

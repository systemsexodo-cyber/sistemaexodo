import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';

void main() {
  test('Test VendaBalcao parsing date', () async {
    final dbService = DatabaseService();
    dbService.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');
    final list = await dbService.carregarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_exodo_vendas_balcao');
    
    print('=== VENDAS PARSED ===');
    for (var i = 0; i < 5 && i < list.length; i++) {
      final map = list[i];
      final venda = VendaBalcao.fromMap(map);
      print('Venda ${venda.numero}:');
      print('  dataVenda in Model: ${venda.dataVenda}');
      print('  dataVenda isUtc: ${venda.dataVenda.isUtc}');
    }
  });
}

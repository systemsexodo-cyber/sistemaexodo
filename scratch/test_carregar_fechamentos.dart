import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  test('Test load fechamentos in Dart', () async {
    final dbService = DatabaseService();
    dbService.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');
    final list = await dbService.carregarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_exodo_fechamentos_caixa');
    
    print('=== FECHAMENTOS CARREGADOS PELO DART ===');
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      print('Item $i:');
      print('  ID: ${item['id']}');
      print('  dataFechamento: ${item['dataFechamento']} (${item['dataFechamento'].runtimeType})');
      print('  createdAt: ${item['createdAt']} (${item['createdAt'].runtimeType})');
      print('  responsavel: ${item['responsavel']}');
    }
  });
}

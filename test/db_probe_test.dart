import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  test('reproduz upsert do save list com empresa escopada', () async {
    final db = DatabaseService();
    db.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');

    final item = {
      'id': 'probe-prod-1',
      'codigo': 'P-TESTE-1',
      'nome': 'Probe Produto',
      'descricao': 'Produto de teste',
      'unidade': 'UN',
      'grupo': 'Teste',
      'preco': 10.5,
      'preco_custo': 7.0,
      'estoque': 5,
      'estoque_minimo': 0,
      'empresa_id': '22ae2c16-a730-43f3-a4f9-19f105eb0d13',
      'created_at': '2026-07-13T12:00:00.000Z',
      'updated_at': '2026-07-13T12:00:00.000Z',
    };

    await db.salvarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_produtos', [item]);

    await db.salvarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_cache', [
      {
        'id': 'probe-cache-1',
        'createdAt': DateTime.now(),
        'status': 'ok',
      },
    ]);

    final loaded = await db.carregarLista(
      'empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_cache',
    );
    expect(loaded, isNotEmpty);
    expect(loaded.first['createdAt'], isA<String>());
    expect(loaded.first['status'], equals('ok'));
  });
}

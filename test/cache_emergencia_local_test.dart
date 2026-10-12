import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

void main() {
  test('cache de emergência preserva lista e marca pendência do PostgreSQL', () async {
    final dir = await Directory.systemTemp.createTemp('exodo-cache-test-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStorageService(emergencyCacheDirectory: dir);
    final dados = [
      {'id': 'P1', 'nome': 'Produto offline'},
    ];

    await storage.salvarCacheEmergencia(
      'empresa_E1_exodo_produtos',
      dados,
      pendente: true,
    );

    final salvo = await storage.carregarCacheEmergencia(
      'empresa_E1_exodo_produtos',
    );
    expect(salvo?['pendente'], isTrue);
    expect(salvo?['valor'], dados);
  });

  test('salvarLista usa o cache de emergência quando o PostgreSQL falha', () async {
    final dir = await Directory.systemTemp.createTemp('exodo-cache-fallback-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStorageService(
      emergencyCacheDirectory: dir,
      databaseListWriter: (key, lista, {bool isSync = false}) async {
        throw StateError('PostgreSQL indisponível');
      },
      databaseListReader: (key) async {
        throw StateError('PostgreSQL indisponível');
      },
    );
    final dados = [
      {'id': 'V1', 'numero': 'VND-1'},
    ];

    await storage.salvarLista('empresa_E1_exodo_vendas', dados);

    final salvo = await storage.carregarCacheEmergencia(
      'empresa_E1_exodo_vendas',
    );
    expect(salvo?['pendente'], isTrue);
    expect(salvo?['valor'], dados);
    expect(
      await storage.carregarLista('empresa_E1_exodo_vendas'),
      dados,
    );
  });

  test('cache de emergência serializa datas do PostgreSQL em ISO', () async {
    final dir = await Directory.systemTemp.createTemp('exodo-cache-datetime-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStorageService(emergencyCacheDirectory: dir);
    final data = DateTime(2026, 10, 1, 14, 30);

    await storage.salvarCacheEmergencia('caixa', [
      {'id': 'C1', 'data_abertura': data},
    ]);

    final salvo = await storage.carregarCacheEmergencia('caixa');
    expect(salvo?['valor'][0]['data_abertura'], data.toIso8601String());
  });
}
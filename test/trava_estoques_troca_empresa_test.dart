// Trava de isolamento dos ESCRITORES de estoque (salvar/principal/excluir).
//
// O cruzamento real (estoques de uma empresa gravados na outra ao trocar de
// empresa) acontecia nesta janela: o `setEmpresaAtual` trocava a empresa em
// memória ANTES de `definirEmpresaAtual` fixar `_currentEmpresaId`. Nesses
// segundos, a lista em memória era da empresa NOVA e a chave de gravação
// (`_getChaveComEmpresa('estoques')`) derivava da empresa ANTIGA — salvas,
// editadas ou excluídas nessa janela gravavam a lista de uma no cache da outra
// (é o estado `estoque_e2f148ca` da BMJ visto no banco em 27/10).
//
// Estes testes travam:
//  1. no estado misto (lista de B em memória + id de A no DataService), os
//     três escritores RECUSAM tocar a lista nem gravar nada;
//  2. com a empresa certa fixada (ordem correta do wiring), os escritores
//     funcionam normalmente na empresa certa;
//  3. sem empresa fixada, também recusam.
//
// Rodar: flutter test test/trava_estoques_troca_empresa_test.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/estoque.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';

Empresa _empresa(String id, List<Map<String, dynamic>> estoques) => Empresa(
      id: id,
      razaoSocial: 'Empresa $id',
      slug: id,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
      configuracoes: {'estoques': estoques},
    );

// Nomes usam 'Loja'/'Depósito' (iguais aos padrões) para o
// `_criarEstoquesPadrao` não acrescentar nada por conta própria — aqui só os
// ESCRITORES estão sob teste.
final empresaA = _empresa('emp-a', [
  {'id': 'loja-a', 'nome': 'Loja', 'principal': true, 'ordem': 0},
  {'id': 'deposito-a', 'nome': 'Depósito', 'principal': false, 'ordem': 1},
]);

final empresaB = _empresa('emp-b', [
  {'id': 'loja-b', 'nome': 'Loja', 'principal': true, 'ordem': 0},
  {'id': 'deposito-b', 'nome': 'Depósito', 'principal': false, 'ordem': 1},
]);

void main() {
  setUp(() {
    // Plugins de plataforma não existem num teste headless.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<Object?> nulo(MethodCall call) async => null;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['none'] : null,
    );
  });

  /// Ruído de fundo: num teste headless não existe rede, banco nem o ciclo
  /// de sincronização do app. O que interessa é erro do FRAMEWORK/da lógica.
  bool eRuido(Object? e) {
    if (e == null) return true;
    final t = '$e';
    return t.contains('overflowed') ||
        t.contains('MissingPluginException') ||
        t.contains('MissingPlatformDirectoryException') ||
        t.contains('was used after being disposed') ||
        t.contains('Cannot add to an unmodifiable list') ||
        t.contains('HttpClient') ||
        t.contains('Neon Auth') ||
        t.contains('Bad state') ||
        t.contains('PostgrestException') ||
        t.contains('TimeoutException') ||
        t.contains('SocketException') ||
        t.contains('Connection refused');
  }

  /// Drena timers de rede/banco e devolve as exceções do caminho.
  Future<void> drenar(WidgetTester tester, DataService ds) async {
    final erros = <Object?>[tester.takeException()];
    await tester.pump(const Duration(seconds: 16));
    ds.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      erros.add(tester.takeException());
    }
    final relevantes = erros.where((e) => !eRuido(e)).toList();
    expect(relevantes, isEmpty,
        reason: 'erro inesperado durante o teste: $relevantes');
  }

  testWidgets('posterior à troca SEM fixar o id: escritores de estoque recusam',
      (tester) async {
    final ds = DataService();

    // Estado inicial: tudo da empresa A.
    ds.setEmpresaAtual(empresaA);
    ds.setEmpresaIdParaTeste('emp-a');
    expect(ds.currentEmpresaId, 'emp-a');
    expect(ds.estoques.map((e) => e.id), ['loja-a', 'deposito-a']);

    // A JANELA DO BUG: memória já é B, mas o id do DataService continua A
    // (é o que acontecia com `setEmpresaAtual` antes de `definirEmpresaAtual`).
    ds.setEmpresaAtual(empresaB);
    ds.setEmpresaIdParaTeste('emp-a');

    // 1. SALVAR: não pode incluir nem gravar (lista continua a da B == emp-b).
    await ds.salvarEstoque(
        Estoque(id: 'estoque_invasor', nome: 'Invasor', ordem: 5));
    expect(ds.estoques.map((e) => e.id),
        ['loja-b', 'deposito-b'],
        reason: 'salvarEstoque gravou na janela mista (lista de B, id de A)');

    // 2. DEFINIR PRINCIPAL: não pode trocar quem é o principal.
    await ds.definirEstoquePrincipal('deposito-b');
    expect(ds.estoquePrincipalAtual?.id, 'loja-b',
        reason: 'definirEstoquePrincipal gravou na janela mista');

    // 3. EXCLUIR: não pode remover.
    await ds.excluirEstoque('deposito-b');
    expect(ds.estoques.map((e) => e.id),
        ['loja-b', 'deposito-b'],
        reason: 'excluirEstoque gravou na janela mista');

    await drenar(tester, ds);
  });

  testWidgets('ordem correta (id fixado antes): escritores funcionam na empresa certa',
      (tester) async {
    final ds = DataService();

    // Ordem correta do wiring: `definirEmpresaAtual` fixa o id ANTES do
    // `setEmpresaAtual` trocar a memória (no teste o hook entra no lugar do
    // `definirEmpresaAtual` para não tocar em rede/banco).
    ds.setEmpresaIdParaTeste('emp-b');
    ds.setEmpresaAtual(empresaB);

    expect(ds.currentEmpresaId, 'emp-b');
    expect(ds.estoques.map((e) => e.id), ['loja-b', 'deposito-b']);

    // Salvar: entra na lista em memória (a mutação é SÍNCRONA, antes de
    // qualquer await de persistência — que num teste headless pode nem
    // resolver banco/nuvem de fachada). O que interessa é a trava aceitar.
    unawaited(ds.salvarEstoque(
        Estoque(id: 'estoque_terceiro', nome: 'Caminhão', ordem: 2)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ds.estoques.map((e) => e.id),
        ['loja-b', 'deposito-b', 'estoque_terceiro'],
        reason: 'com o wiring correto o salvar precisa funcionar');

    await drenar(tester, ds);
  });

  testWidgets('sem empresa fixada: escritores também recusam', (tester) async {
    final ds = DataService();
    ds.setEmpresaAtual(empresaB);
    // A troca por `definirEmpresaAtual(null)` limpa tudo; aqui simulamos apenas
    // o id vazio (app inicializando/logout).
    ds.setEmpresaIdParaTeste('');

    await ds.salvarEstoque(
        Estoque(id: 'estoque_orfao', nome: 'Órfão', ordem: 9));
    expect(ds.estoques.map((e) => e.id),
        ['loja-b', 'deposito-b'],
        reason: 'sem empresa fixada não pode gravar estoque');

    await drenar(tester, ds);
  });
}

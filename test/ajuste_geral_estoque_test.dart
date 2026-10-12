// Seletor de estoque na tela "Ajuste Geral • Estoque e Preço".
//
// A tela passou a ajustar UM estoque por vez (Loja, Depósito e os que forem
// cadastrados na tela de Estoques) em vez de sempre mexer no total do produto.
// Estes testes travam três coisas que, se perderem, regravam o catálogo errado:
//
//  1. o seletor abre no estoque PRINCIPAL da empresa;
//  2. trocar de estoque muda o cabeçalho da coluna EST. (é o número que a
//     tabela mostra, que os filtros usam e que a regra aplica);
//  3. trocar de estoque limpa os valores digitados item a item — eles eram do
//     estoque anterior (5 na Loja viraria "5 no Depósito").
//
// Rodar: flutter test test/ajuste_geral_estoque_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/pages/ajuste_estoque_massa_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

Empresa _empresaComEstoques() => Empresa(
      id: 'EMPRESA-TESTE-AJUSTE-GERAL',
      razaoSocial: 'Empresa Teste Ajuste Geral',
      slug: 'empresa-teste-ajuste-geral',
      createdAt: DateTime(2026, 9, 27),
      updatedAt: DateTime(2026, 9, 27),
      configuracoes: {
        'estoques': [
          {'id': 'estoque_loja', 'nome': 'Loja', 'principal': true, 'ordem': 0},
          {
            'id': 'estoque_deposito',
            'nome': 'Deposito',
            'principal': false,
            'ordem': 1,
          },
        ],
      },
    );

void main() {
  setUp(() {
    // Plugins de plataforma não existem num teste headless.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<Object?> nulo(MethodCall call) async => null;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['none'] : null,
    );
  });

  testWidgets('abre no estoque principal e trocar de estoque muda a coluna',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dataService = DataService();
    dataService.setEmpresaAtual(_empresaComEstoques());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: dataService),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: AjusteEstoqueMassaPage()),
      ),
    );

    // Erros de LAYOUT são os que interessam aqui: o seletor fica dentro de um
    // FittedBox (igual às linhas de regra) e um dropdown em largura não
    // limitada derrubaria a tela com RenderFlex, mesmo com o texto na árvore.
    final errosDeLayout = <String>[];
    void anotarErro() {
      final e = tester.takeException();
      final texto = '$e';
      if (e != null &&
          (texto.contains('RenderFlex') ||
              texto.contains('unbounded') ||
              texto.contains('overflowed') ||
              texto.contains('not exactly one item'))) {
        errosDeLayout.add(texto);
      }
    }

    // A tela monta o lote (5676 no caso real) e liga os serviços de sync.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      anotarErro();
      if (find.text('ESTOQUE AJUSTADO').evaluate().isNotEmpty) break;
    }

    expect(errosDeLayout, isEmpty,
        reason: 'erro de layout ao montar o seletor: $errosDeLayout');

    expect(find.text('ESTOQUE AJUSTADO'), findsOneWidget,
        reason: 'o seletor de estoque (Loja/Depósito) sumiu da tela');
    expect(find.text('Loja (principal)'), findsOneWidget,
        reason: 'a tela não abriu no estoque PRINCIPAL da empresa');
    expect(find.text('EST. LOJA'), findsOneWidget,
        reason: 'a coluna EST. não diz que o número é o da Loja');

    // Troca para o Depósito: o cabeçalho passa a dizer de qual estoque os
    // números falam — é ele que filtros, regras e APLICAR usam.
    await tester.tap(find.text('Loja (principal)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Deposito').last);
    await tester.pump(const Duration(milliseconds: 400));
    anotarErro();

    expect(errosDeLayout, isEmpty,
        reason: 'erro de layout ao trocar de estoque: $errosDeLayout');
    expect(find.text('EST. DEPOSITO'), findsOneWidget,
        reason: 'trocar o estoque não mudou o cabeçalho da coluna EST.');

    // Drena timers de rede/banco: sem isso o flutter_test acusa "A Timer is
    // still pending" (nada a ver com a tela).
    await tester.pump(const Duration(seconds: 16));
    dataService.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      tester.takeException();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

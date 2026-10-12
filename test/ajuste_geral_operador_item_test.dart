// Ajuste Geral • Estoque e Preço: o número digitado NA LINHA entra conforme o
// operador do item — e o operador do item, quando o usuário não escolheu nada
// na própria linha, é o modo da REGRA GERAL escolhido no topo (Somar
// quantidade / Subtrair quantidade / Definir valor).
//
// Antes disso, escolher "Somar quantidade" no topo e digitar 12 na linha
// DEFINE o saldo em 12 (6 → 12) em vez de somar (6 → 18): o número digitado
// contradizia o modo escolhido, que é a reclamação do usuário.
//
// Rodar: flutter test test/ajuste_geral_operador_item_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/pages/ajuste_estoque_massa_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

Empresa _empresaComEstoques() => Empresa(
      id: 'EMPRESA-TESTE-OPERADOR-ITEM',
      razaoSocial: 'Empresa Teste Operador Item',
      slug: 'empresa-teste-operador-item',
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

/// "teste 123" do print do usuário: 6 na Loja — o item que ele digitou 12.
Produto _produto({double saldoLoja = 6}) => Produto(
      id: 'P-TESTE-123',
      nome: 'teste 123',
      unidade: 'peca',
      grupo: 'Sem Grupo',
      preco: 24,
      estoque: saldoLoja,
      estoquePorEstoque: {'estoque_loja': saldoLoja},
      estoquePadraoId: 'estoque_loja',
      createdAt: DateTime(2026, 9, 27),
      updatedAt: DateTime(2026, 9, 27),
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

  /// Monta a tela com o produto do print e devolve o campo NOVO da linha.
  ///
  /// O campo é achado pelo valor que ele mostra (o saldo do item no estoque
  /// escolhido), não por chave: a chave carrega a `_geracao` interna da tela,
  /// que muda a cada regra aplicada.
  Future<TextField> abrirTela(WidgetTester tester, DataService ds) async {
    tester.view.physicalSize = const Size(1500, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ds.setEmpresaAtual(_empresaComEstoques());
    ds.produtos.add(_produto());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: ds),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: AjusteEstoqueMassaPage()),
      ),
    );

    // A tela monta o lote e liga os serviços de sync.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('teste 123').evaluate().isNotEmpty) break;
    }
    expect(find.text('teste 123'), findsOneWidget,
        reason: 'o produto não chegou na tabela do Ajuste Geral');

    final campo = tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
          (campo) => campo.controller?.text == '6',
          orElse: () => throw StateError(
              'não achei o campo NOVO do estoque (a linha deveria mostrar 6)'),
        );
    return campo;
  }

  /// Drena timers de rede/banco: sem isso o flutter_test acusa "A Timer is
  /// still pending" (nada a ver com a regra em teste).
  Future<void> drenar(WidgetTester tester, DataService ds) async {
    await tester.pump(const Duration(seconds: 16));
    ds.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      tester.takeException();
    }
  }

  testWidgets(
      'com "Somar quantidade" no topo, digitar 12 na linha soma ao saldo',
      (tester) async {
    final ds = DataService();
    await abrirTela(tester, ds);

    // Regra geral do topo: Somar quantidade (a coluna NOVO da linha segue).
    await tester.tap(find.text('Definir valor (ajustar)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Somar quantidade').last);
    await tester.pump(const Duration(milliseconds: 400));

    final campo = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((c) => c.controller?.text == '6');
    await tester.enterText(find.byWidget(campo), '12');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('→ 18'), findsOneWidget,
        reason: 'com "Somar quantidade", 12 na linha tem que virar 18 '
            '(6 + 12) — não definir o saldo em 12');
    expect(find.text('+12'), findsOneWidget,
        reason: 'a variação tem que ser +12, não +6');

    await drenar(tester, ds);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'ainda sem regra no topo, digitar 12 na linha DEFINE o saldo (padrão)',
      (tester) async {
    final ds = DataService();
    await abrirTela(tester, ds);

    final campo = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((c) => c.controller?.text == '6');
    await tester.enterText(find.byWidget(campo), '12');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('→ 18'), findsNothing,
        reason: 'com "=" o campo já é o valor final, então não há seta');
    expect(find.text('+6'), findsOneWidget,
        reason: 'o padrão continua sendo definir (6 → 12, Δ +6)');

    await drenar(tester, ds);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'trocar a regra geral para Subtrair muda o operador das linhas na hora',
      (tester) async {
    final ds = DataService();
    await abrirTela(tester, ds);

    await tester.tap(find.text('Definir valor (ajustar)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Subtrair quantidade').last);
    await tester.pump(const Duration(milliseconds: 400));

    final campo = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((c) => c.controller?.text == '6');
    await tester.enterText(find.byWidget(campo), '2');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('→ 4'), findsOneWidget,
        reason: '6 com "Subtrair quantidade" e 2 digitado tem que virar 4');
    expect(find.text('-2'), findsOneWidget,
        reason: 'a variação tem que ser -2');

    await drenar(tester, ds);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

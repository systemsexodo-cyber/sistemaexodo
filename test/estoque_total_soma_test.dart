// O campo de estoque do cadastro mostra o TOTAL do produto (Loja + Depósito),
// não o saldo de um estoque só.
//
// Era isso que fazia o usuário ler "33.0" ao lado do seletor "Loja (principal)"
// como se fosse o estoque da loja — o da loja era 32 e o outro 1 estava no
// depósito. Estes testes travam as duas coisas que tiraram a ambiguidade:
//
//  1. o campo passa a se chamar "Estoque Total (soma dos estoques)" quando o
//     produto tem saldo separado por estoque (produto sem split continua
//     "Estoque Atual", que é o caso da maioria do catálogo);
//  2. embaixo dele sai a linha "Total = Loja 32.00 + Deposito 1.00".
//
// Rodar: flutter test test/estoque_total_soma_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/produto_form.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';

Empresa _empresaComEstoques() => Empresa(
      id: 'EMPRESA-TESTE-ESTOQUE-TOTAL',
      razaoSocial: 'Empresa Teste Estoque Total',
      slug: 'empresa-teste-estoque-total',
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
        'departamentos': [
          {'id': 'dep-cozinha', 'nome': 'Cozinha'},
        ],
      },
    );

Produto _produto({
  required String id,
  required double estoque,
  Map<String, double> porEstoque = const {},
  String? padraoId,
}) =>
    Produto(
      id: id,
      nome: 'coca cola',
      unidade: 'un',
      grupo: 'Teste',
      preco: 24,
      estoque: estoque,
      estoquePorEstoque: porEstoque,
      estoquePadraoId: padraoId,
      createdAt: DateTime(2026, 9, 27),
      updatedAt: DateTime(2026, 9, 27),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
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
  });

  /// Passes com tempo fixo: com campo focado o `pumpAndSettle` nunca volta
  /// (cursor piscando).
  Future<void> assentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Cadastro aberto em bottom sheet, igual ao produtos_page (forma real).
  Future<void> abrirFormulario(
      DataService ds, Produto produto, WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: ds),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SizedBox(
                      height: 1600,
                      child: ProdutoServicoForm(
                        item: produto,
                        onSave: (p) async {},
                      ),
                    ),
                  ),
                  child: const Text('ABRIR CADASTRO'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await assentar(tester);
    await tester.tap(find.text('ABRIR CADASTRO'));
    await assentar(tester);
  }

  /// Ruído de fundo: num teste headless não existe rede, banco, áudio nem o
  /// ciclo de sincronização do app.
  bool eRuido(Object? e) =>
      e == null ||
      '$e'.contains('overflowed') ||
      '$e'.contains('MissingPluginException') ||
      '$e'.contains('was used after being disposed') ||
      '$e'.contains('Cannot add to an unmodifiable list');

  /// Drena timers de rede/banco e devolve as exceções do caminho.
  Future<List<Object?>> drenar(WidgetTester tester, DataService ds) async {
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
    return erros;
  }

  testWidgets('produto separado em Loja/Depósito mostra o TOTAL e a soma',
      (tester) async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresaComEstoques());

    await abrirFormulario(
      ds,
      _produto(
        id: 'PRODUTO-SPLIT',
        estoque: 33,
        porEstoque: const {'estoque_loja': 32, 'estoque_deposito': 1},
        padraoId: 'estoque_loja',
      ),
      tester,
    );

    expect(find.text('Estoque Total (soma dos estoques)'), findsOneWidget,
        reason: 'o campo continua dizendo só "Estoque Atual" num produto '
            'separado em estoques — era o que fazia 33 parecer o da loja');
    expect(find.text('Total = Loja 32.00 + Deposito 1.00'), findsOneWidget,
        reason: 'a tela não diz que 33 é 32 da loja + 1 do depósito');

    final erros = await drenar(tester, ds);
    final relevantes = erros.where((e) => !eRuido(e)).toList();
    expect(relevantes, isEmpty, reason: 'erros ao abrir o cadastro: $relevantes');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('produto sem saldo por estoque continua com o campo simples',
      (tester) async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresaComEstoques());

    await abrirFormulario(
      ds,
      _produto(id: 'PRODUTO-SEM-SPLIT', estoque: 5),
      tester,
    );

    expect(find.text('Estoque Atual'), findsOneWidget,
        reason: 'produto sem split deve continuar com o rótulo de sempre');
    expect(find.textContaining('Total = '), findsNothing,
        reason: 'não há soma por estoque para mostrar nesse produto');

    final erros = await drenar(tester, ds);
    final relevantes = erros.where((e) => !eRuido(e)).toList();
    expect(relevantes, isEmpty, reason: 'erros ao abrir o cadastro: $relevantes');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

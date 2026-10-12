// Blindagem do diálogo "Ajuste de Estoque".
//
// A tela vermelha que o usuário via ("'_dependents.isEmpty': is not true")
// vinha do próprio diálogo: um erro de BUILD em um dos campos troca o campo
// por um ErrorWidget de 100000 px, a coluna do diálogo (que não rolava) estoura
// ~300000 px (erro_flutter.log: "overflowed by 299391 pixels") e o Flutter
// derruba o app. Estes testes cobrem os dois caminhos que produziam isso:
//
//  1. o estoque escolhido some da lista (a sincronização troca os estoques da
//     empresa com o diálogo aberto) → o DropdownButtonFormField estoura
//     "There should be exactly one item with [DropdownButton]'s value";
//  2. o usuário fecha o diálogo no meio do ajuste → o ajuste terminava e dava
//     um SEGUNDO `Navigator.pop`, fechando a tela do cadastro por baixo.
//
// Rodar: flutter test test/ajuste_estoque_blindagem_test.dart

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

Empresa _empresaComEstoques(List<Map<String, dynamic>> estoques) => Empresa(
      id: 'EMPRESA-TESTE-BLINDAGEM',
      razaoSocial: 'Empresa Teste Blindagem',
      slug: 'empresa-teste-blindagem',
      createdAt: DateTime(2026, 9, 27),
      updatedAt: DateTime(2026, 9, 27),
      configuracoes: {
        'estoques': estoques,
        'departamentos': [
          {'id': 'dep-cozinha', 'nome': 'Cozinha'},
        ],
      },
    );

final _loja = {'id': 'estoque_loja', 'nome': 'Loja', 'principal': true, 'ordem': 0};
final _deposito = {
  'id': 'estoque_deposito',
  'nome': 'Deposito',
  'principal': false,
  'ordem': 1,
};

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

  final produto = Produto(
    id: 'PRODUTO-TESTE-BLINDAGEM',
    nome: 'Produto Teste Blindagem',
    unidade: 'un',
    grupo: 'Teste',
    preco: 10,
    estoque: 5,
    createdAt: DateTime(2026, 9, 27),
    updatedAt: DateTime(2026, 9, 27),
    estoquePadraoId: 'estoque_loja',
  );

  /// Passes com tempo fixo: com campo focado o `pumpAndSettle` nunca volta
  /// (cursor piscando).
  Future<void> assentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Cadastro aberto em bottom sheet, igual ao produtos_page (forma real).
  Future<void> abrirFormulario(DataService ds, WidgetTester tester) async {
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

  Future<void> abrirDialogo(WidgetTester tester) async {
    final botao = find.text('AJUSTAR').first;
    await tester.ensureVisible(botao);
    await assentar(tester);
    await tester.tap(botao);
    await assentar(tester);
    expect(find.text('Ajuste de Estoque'), findsOneWidget,
        reason: 'o diálogo de Ajuste de Estoque não abriu');
  }

  /// Ruído de fundo: num teste headless não existe rede, banco, áudio nem o
  /// ciclo de sincronização do app. O que interessa aqui é erro do FRAMEWORK
  /// em cima do diálogo.
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

  testWidgets('estoque escolhido apagado pela sincronização não estoura o '
      'diálogo (o valor sumia da lista do DropdownButton)', (tester) async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresaComEstoques([_loja, _deposito]));
    expect(ds.estoques, hasLength(2));

    await abrirFormulario(ds, tester);
    await abrirDialogo(tester);
    expect(find.textContaining('Estoque de destino'), findsWidgets,
        reason: 'o seletor de estoque não apareceu no diálogo');

    // A sincronização troca os estoques da empresa COM O DIÁLOGO ABERTO — o
    // "Loja" (que era o destino escolhido) deixa de existir.
    ds.setEmpresaAtual(_empresaComEstoques([
      {
        'id': 'estoque_novo',
        'nome': 'Estoque Novo',
        'principal': true,
        'ordem': 0,
      },
    ]));
    await assentar(tester);

    // Qualquer toque no diálogo o reconstrói (é o caminho que estourava).
    await tester.tap(find.text('SAÍDA'));
    await assentar(tester);

    expect(find.text('Ajuste de Estoque'), findsOneWidget,
        reason: 'o diálogo foi derrubado quando o estoque escolhido sumiu');
    // O estoque que sumiu continua na lista (marcado como removido): é isso que
    // impede o estouro do DropdownButtonFormField.
    expect(find.textContaining('(removido)'), findsWidgets,
        reason: 'o estoque removido sumiu da lista do seletor');

    final erros = await drenar(tester, ds);
    final relevantes = erros.where((e) => !eRuido(e)).toList();
    expect(relevantes, isEmpty,
        reason: 'erro ao trocar os estoques com o diálogo aberto: $relevantes');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('fechar o diálogo no meio do ajuste não fecha o cadastro '
      '(sem pop duplo)', (tester) async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresaComEstoques([_loja, _deposito]));

    await abrirFormulario(ds, tester);
    await abrirDialogo(tester);

    final campoQtd = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(campoQtd.first, '3');
    await assentar(tester);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CONFIRMAR')));
    // Um único frame: o ajuste ainda está sendo gravado quando o CANCELAR vem.
    await tester.pump(const Duration(milliseconds: 1));

    final cancelar = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CANCELAR'));
    if (cancelar.evaluate().isNotEmpty) {
      await tester.tap(cancelar);
    }
    await assentar(tester);

    // O ajuste terminou DEPOIS do usuário fechar o diálogo: o cadastro precisa
    // continuar na tela. Antes, o código dava outro `Navigator.pop` e levava o
    // bottom sheet junto (e com ele a árvore de widgets toda).
    expect(find.byType(ProdutoServicoForm), findsOneWidget,
        reason: 'o cadastro foi fechado junto com o ajuste (pop duplo)');
    expect(find.text('AJUSTAR'), findsWidgets,
        reason: 'o botão do cadastro sumiu — a tela foi fechada por engano');

    final erros = await drenar(tester, ds);
    final relevantes = erros.where((e) => !eRuido(e)).toList();
    expect(relevantes, isEmpty, reason: 'erros ao fechar no meio: $relevantes');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

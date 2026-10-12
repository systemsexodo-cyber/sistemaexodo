// Reprodução do "Failed assertion: '_dependents.isEmpty': is not true" que o
// usuário vê (tela vermelha) quando vai ajustar o estoque pelo cadastro do
// produto.
//
// Aqui o diálogo "Ajuste de Estoque" é aberto de verdade (dentro de um
// MaterialApp com os mesmos providers do app), a quantidade é preenchida e o
// diálogo é fechado. Qualquer exceção do framework é capturada e conferida —
// é isso que falta para achar a causa.
//
// O final do teste drena os timers de rede/auth/banco com o mesmo ritual de
// monitor_page_test.dart; senão o flutter_test reclama de "Timer is still
// pending" e mascara o resultado.
//
// Rodar: flutter test test/ajuste_estoque_dialogo_erro_test.dart

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
    id: 'PRODUTO-TESTE-ERRO-DEP',
    nome: 'Produto Teste Ajuste',
    unidade: 'un',
    grupo: 'Teste',
    preco: 10,
    estoque: 5,
    createdAt: DateTime(2026, 9, 25),
    updatedAt: DateTime(2026, 9, 25),
  );

  /// Assenta a árvore com passes limitados. O pumpAndSettle padrão fica para
  /// sempre se um campo com cursor piscando estiver focado (e esse teste foca
  /// o campo de quantidade) — daí o loop com tempo fixo.
  Future<void> assentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> abrirFormulario(DataService ds, WidgetTester tester) async {
    // Tela grande o suficiente: o botão AJUSTAR fica no fim do cadastro.
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
            body: ProdutoServicoForm(
              item: produto,
              onSave: (p) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
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

  /// Drena os timers de rede/auth/banco e devolve as exceções que apareceram
  /// no caminho (precisamos delas porque o takeException zera a fila).
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

  void conferir(List<Object?> erros, String contexto) {
    // Overflow de layout é ruído (o form é grande e o teste usa tela fixa) e
    // MissingPluginException vem dos plugins de áudio/rede que não existem num
    // teste headless — o que interessa é a falha do framework que derruba o app.
    final relevantes = erros
        .where((e) =>
            e != null &&
            !'$e'.contains('overflowed') &&
            !'$e'.contains('MissingPluginException'))
        .toList();
    final dependents =
        relevantes.where((e) => '$e'.contains("_dependents.isEmpty")).toList();
    expect(dependents, isEmpty,
        reason: 'deu erro ao $contexto (tela vermelha): $dependents');

    // A primeira posição é a exceção colhida logo após a interação com o
    // diálogo — é ela que interessa. O resto é ruído de fundo (Supabase não
    // inicializado num teste headless), que o monitor_page_test também ignora.
    expect(relevantes, isEmpty, reason: 'erros ao $contexto: $relevantes');
  }

  testWidgets('abrir e confirmar o Ajuste de Estoque não derruba o app',
      (tester) async {
    final ds = DataService();
    await abrirFormulario(ds, tester);
    await abrirDialogo(tester);

    // Preenche a quantidade e confirma: é o caminho que o usuário dispara.
    final campoQtd = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(campoQtd, findsWidgets);
    await tester.enterText(campoQtd.first, '3');
    await assentar(tester);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CONFIRMAR')));
    await assentar(tester);

    conferir(await drenar(tester, ds), 'ajustar o estoque');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('com estoques cadastrados e o cadastro em bottom sheet (forma '
      'real do app), o ajuste não derruba o app', (tester) async {
    final ds = DataService();
    // Empresa com os DOIS estoques padrão (Loja/Depósito): é o que a máquina do
    // usuário tem, e é o que faz o seletor de estoque aparecer no diálogo.
    ds.setEmpresaAtual(Empresa(
      id: 'EMPRESA-TESTE-AJUSTE',
      razaoSocial: 'Empresa Teste Ajuste',
      slug: 'empresa-teste-ajuste',
      createdAt: DateTime(2026, 9, 25),
      updatedAt: DateTime(2026, 9, 25),
      configuracoes: {
        'estoques': [
          {'id': 'estoque_loja', 'nome': 'Loja', 'principal': true, 'ordem': 0},
          {
            'id': 'estoque_deposito',
            'nome': 'Deposito',
            'principal': false,
            'ordem': 1
          },
        ],
        'departamentos': [
          {'id': 'dep-cozinha', 'nome': 'Cozinha'},
          {'id': 'dep-bar', 'nome': 'Bar'},
        ],
      },
    ));
    expect(ds.estoques, hasLength(2), reason: 'os estoques não carregaram');

    // Mesmo formato do produtos_page: o cadastro abre em bottom sheet e o
    // diálogo de ajuste é chamado de lá por cima.
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
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: 1600,
                        child: ProdutoServicoForm(
                          item: produto,
                          onSave: (p) async {},
                        ),
                      ),
                    );
                  },
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
    await abrirDialogo(tester);

    // O seletor de estoque precisa estar lá (é o que a versão nova do diálogo
    // traz e é novo neste fluxo).
    expect(find.textContaining('Estoque de destino'), findsWidgets,
        reason: 'o seletor de estoque não apareceu no diálogo');

    final campoQtd = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(campoQtd.first, '3');
    await assentar(tester);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CONFIRMAR')));
    await assentar(tester);

    conferir(await drenar(tester, ds), 'ajustar o estoque (forma real do app)');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('se um alerta da Home abre junto do fechamento do ajuste, '
      'o app não derruba', (tester) async {
    final ds = DataService();
    await abrirFormulario(ds, tester);

    // A Home faz exatamente isso: quando o DataService notifica com um erro
    // novo de sincronização, ela abre um AlertDialog por cima
    // (home_page._mostrarAlertaErroSync). Aqui simulamos o alerta de sync
    // caindo NO MESMO MOMENTO em que o ajuste de estoque é confirmado.
    final contextDaHome = tester.element(find.byType(MaterialApp));
    var alertaMostrado = false;
    void mostrarAlerta() {
      if (alertaMostrado) return;
      alertaMostrado = true;
      showDialog<void>(
        context: contextDaHome,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro na Sincronização'),
          content: const Text('upload vendas_balcao: HTTP 409'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('FECHAR'),
            ),
          ],
        ),
      );
    }

    await abrirDialogo(tester);

    final campoQtd = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(campoQtd.first, '3');
    await assentar(tester);

    // Liga o alerta SÓ AGORA: assim a primeira notificação do ajuste é a que
    // derruba o diálogo em cima — que é o que acontece na máquina real.
    ds.addListener(mostrarAlerta);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CONFIRMAR')));
    await assentar(tester);
    ds.removeListener(mostrarAlerta);

    // Fecha o alerta que abriu por cima, se houver.
    final fechar = find.text('FECHAR');
    if (fechar.evaluate().isNotEmpty) {
      await tester.tap(fechar);
      await assentar(tester);
    }

    conferir(await drenar(tester, ds),
        'ajustar o estoque com alerta de sync abrindo junto');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('fechar o diálogo pelo CANCELAR também não derruba o app',
      (tester) async {
    final ds = DataService();
    await abrirFormulario(ds, tester);
    await abrirDialogo(tester);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('CANCELAR')));
    await assentar(tester);

    conferir(await drenar(tester, ds), 'fechar o diálogo de ajuste');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

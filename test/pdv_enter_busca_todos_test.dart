// ENTER NO PDV → campo de busca com a opção "TODOS OS PRODUTOS".
//
// Pedido do caixa: "ao dar Enter no PDV vá para o campo de busca e opção todos
// os produtos".
//
// Antes disso, a grade abria VAZIA (nenhuma categoria escolhida) e o Enter com o
// campo de busca vazio só devolvia o foco ao próprio campo (`onSubmitted('')` →
// `_buscaFocusNode.requestFocus()`): o operador ficava sem ver produto nenhum.
// Depois de lançar um item, a grade continuava filtrada pela categoria anterior.
//
// Agora os dois Enter terminam no mesmo estado de trabalho: foco no campo de
// busca + grade mostrando o catálogo inteiro ("Todos os produtos").
//
// O teclado de verdade no Windows manda o "done" pelo canal de texto, então o
// caminho do campo vazio é exercitado chamando o `onSubmitted` real do TextField
// (é o callback que o app roda); o Enter que lança item vem pelo caminho de
// tecla, com `sendKeyEvent`.
//
// Rodar: flutter test test/pdv_enter_busca_todos_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/pages/venda_direta_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/clock_check_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/nfce_contingencia_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

final _empresa = Empresa(
  id: 'E1',
  razaoSocial: 'Loja Teste PDV',
  slug: 'loja-teste-pdv',
  createdAt: DateTime(2026, 10, 11),
  updatedAt: DateTime(2026, 10, 11),
);

Produto _produto(String id, String nome, String grupo) => Produto(
      id: id,
      nome: nome,
      unidade: 'un',
      grupo: grupo,
      codigo: id,
      preco: 10,
      estoque: 50,
      createdAt: DateTime(2026, 10, 11),
      updatedAt: DateTime(2026, 10, 11),
    );

DataService _dataService() {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa);
  ds.produtos.addAll([
    _produto('P1', 'X-Burger', 'Lanches'),
    _produto('P2', 'Refri Lata', 'Bebidas'),
  ]);
  // Caixa aberto: sem isso o PDV abre o diálogo de abertura de caixa.
  ds.aberturasCaixa.add(AberturaCaixa(
    id: 'C1',
    numero: 'CAIXA-001',
    dataAbertura: DateTime(2026, 10, 11, 8),
    valorInicial: 100,
  ));
  return ds;
}

void _mockCanais() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final canal in const [
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
    'dev.fluttercommunity.plus/connectivity',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
  }
}

/// Ruído de layout do teste: a janela de 1600px não é a tela real, e o PDV
/// estoura alguns Rows por poucos pixels.
void _drenarRuido(WidgetTester tester) {
  while (true) {
    final erro = tester.takeException();
    if (erro == null) break;
    final texto = '$erro';
    // 'Multiple exceptions' é o aglomerado que o framework monta quando vários
    // estouros de layout caem no mesmo frame — o detalhe se perde no texto.
    if (texto.contains('overflowed') ||
        texto.contains('Multiple exceptions') ||
        texto.contains('MissingPluginException')) {
      continue;
    }
    throw erro;
  }
}

Future<void> _pump(WidgetTester tester,
    [Duration d = const Duration(milliseconds: 300)]) async {
  await tester.pump(d);
  _drenarRuido(tester);
}

Future<DataService> _abrirPdv(WidgetTester tester) async {
  final ds = _dataService();

  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      // Mesmos provedores do app (main.dart): o PDV usa tema, carrinho,
      // contingência e o relógio da máquina.
      providers: [
        ChangeNotifierProvider<DataService>.value(value: ds),
        ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        ChangeNotifierProvider<ClienteAuthService>.value(
            value: ClienteAuthService()),
        ChangeNotifierProvider<CarrinhoService>.value(
            value: CarrinhoService()),
        ChangeNotifierProvider<NfceContingenciaService>.value(
            value: NfceContingenciaService.instance),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
        ChangeNotifierProvider<ClockCheckService>(
            create: (_) => ClockCheckService()),
      ],
      child: MaterialApp(home: VendaDiretaPage()),
    ),
  );
  await _pump(tester, const Duration(milliseconds: 500));
  await _pump(tester, const Duration(milliseconds: 500));
  return ds;
}

/// Fecha o PDV e drena os timers de rede/banco que o DataService cria — sem
/// isso o teste falha em "A Timer is still pending".
Future<void> _fecharPdv(WidgetTester tester, DataService ds) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  ds.dispose();
  SyncMonitorService.instance.dispose();
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(minutes: 7));
    _drenarRuido(tester);
  }
}

/// Campo de busca da barra superior (o único com o "🔍" no hint).
TextField _campoBusca(WidgetTester tester) => tester.widget<TextField>(
      find
          .ancestor(
            of: find.textContaining('🔍'),
            matching: find.byType(TextField),
          )
          .first,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockCanais();
  });

  testWidgets('ENTER com a grade vazia mostra TODOS os produtos e foca a busca',
      (tester) async {
    final ds = await _abrirPdv(tester);

    // Estado inicial: nenhuma categoria escolhida → grade vazia.
    expect(find.text('X-BURGER'), findsNothing,
        reason: 'sem categoria escolhida a grade abre vazia');
    expect(find.text('REFRI LATA'), findsNothing);

    _campoBusca(tester).onSubmitted!('');
    await _pump(tester);

    expect(find.text('X-BURGER'), findsOneWidget,
        reason: 'o Enter tem de mostrar o catálogo inteiro');
    expect(find.text('REFRI LATA'), findsOneWidget);
    expect(find.text('🔍 Todos...'), findsOneWidget,
        reason: 'a busca fica com a opção TODOS OS PRODUTOS ativa');
    expect(_campoBusca(tester).focusNode!.hasPrimaryFocus, isTrue,
        reason: 'o foco tem de ficar no campo de busca');

    await _fecharPdv(tester, ds);
  });

  testWidgets('depois de filtrar por categoria, o ENTER volta para TODOS',
      (tester) async {
    final ds = await _abrirPdv(tester);

    await tester.tap(find.text('Bebidas').first);
    await _pump(tester);

    expect(find.text('REFRI LATA'), findsOneWidget);
    expect(find.text('X-BURGER'), findsNothing,
        reason: 'a categoria Bebidas esconde os lanches');

    _campoBusca(tester).onSubmitted!('');
    await _pump(tester);

    expect(find.text('X-BURGER'), findsOneWidget,
        reason: 'o Enter volta a grade para todos os produtos');
    expect(find.text('🔍 Todos...'), findsOneWidget);
    expect(_campoBusca(tester).focusNode!.hasPrimaryFocus, isTrue);

    await _fecharPdv(tester, ds);
  });

  testWidgets('lançar um item com o ENTER mantém a busca e TODOS os produtos',
      (tester) async {
    final ds = await _abrirPdv(tester);

    _campoBusca(tester).onSubmitted!(''); // grade: todos os produtos
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // categorias
    await _pump(tester, const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // grade, item 0
    await _pump(tester, const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // lança o item
    await _pump(tester, const Duration(milliseconds: 400));

    expect(find.text('🔍 Todos...'), findsOneWidget,
        reason: 'depois de lançar, a grade continua em todos os produtos');
    expect(_campoBusca(tester).focusNode!.hasPrimaryFocus, isTrue,
        reason: 'o próximo item deve ser digitado direto na busca');

    await _fecharPdv(tester, ds);
  });
}

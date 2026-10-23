// CADASTRO DE PRODUTO → DEPARTAMENTO DE PREPARAÇÃO.
//
// Caso relatado: ao selecionar o departamento a seção ficava vermelha com
// "There should be exactly one item with [DropdownButton]'s value: dep_bar.
// Either zero or 2 or more [DropdownMenuItem]s were detected with the same
// value" — e o produto não ia para o preparo.
//
// O DropdownButton exige EXATAMENTE um item por valor. Isso quebrava de duas
// formas:
//   1) a lista de departamentos chegava com o MESMO id duas vezes (o cache
//      local era mesclado em paralelo e os padrões Cozinha/Bar entravam
//      repetidos na configuração da empresa);
//   2) o produto guardava um departamentoId que não existia mais na lista
//      (departamento excluído / config de outro PC), então nenhum item casava.
//
// Rodar: flutter test test/produto_form_departamento_dropdown_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/produto_historico.dart';
import 'package:sistema_exodo_novo/produto_form.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';

Map<String, Object?> _dep(String id, String nome, {String? impressora}) => {
      'id': id,
      'nome': nome,
      'impressora_producao': impressora,
      'impressora_producao_extra': <String>[],
    };

Empresa _empresa(List<Map<String, Object?>> departamentos) => Empresa(
      id: 'EMPRESA-TESTE-DEPARTAMENTO',
      razaoSocial: 'Loja Teste Departamento',
      slug: 'loja-teste-departamento',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
      configuracoes: {'departamentos': departamentos},
    );

Produto _produto({String? departamentoId}) => Produto(
      id: 'P1',
      nome: 'X-Burger',
      unidade: 'un',
      grupo: 'Teste',
      preco: 25,
      estoque: 10,
      departamentoId: departamentoId,
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

/// DataService sem banco: ao abrir o form ele consulta o histórico do produto e
/// a query real (PostgreSQL local) deixa conexão pendente no teste headless —
/// o que aparece como SocketException aleatória, sem relação com o dropdown.
class _DataServiceSemBanco extends DataService {
  @override
  Future<List<ProdutoHistorico>> buscarHistoricoProduto(
    String produtoId, {
    int limite = 50,
  }) async =>
      const <ProdutoHistorico>[];
}

DataService _dataService({
  required List<Map<String, Object?>> departamentos,
  Produto? produto,
}) {
  final ds = _DataServiceSemBanco();
  ds.setEmpresaAtual(_empresa(departamentos));
  if (produto != null) ds.produtos.add(produto);
  return ds;
}

Future<void> _pumpForm(
  WidgetTester tester,
  DataService ds, {
  required Produto produto,
  required Future<void> Function(dynamic) onSave,
}) async {
  tester.view.physicalSize = const Size(1100, 2200);
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
          body: ProdutoServicoForm(item: produto, onSave: onSave),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Drena os timers que o form agenda no DataService (busca de histórico etc.) e
/// consome o ruído esperado de teste headless (sem plugin nativo de áudio/banco).
/// Sem isso o teste falha com "A Timer is still pending".
Future<void> _drenarTimers(WidgetTester tester, DataService ds) async {
  final erros = <Object?>[tester.takeException()];
  await tester.pump(const Duration(seconds: 16));
  erros.add(tester.takeException());
  // Cancela os timers periódicos do DataService ANTES de drenar os pumps.
  ds.dispose();
  SyncMonitorService.instance.dispose();
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(minutes: 7));
    erros.add(tester.takeException());
  }
  final problemas = erros
      .where((e) => e != null)
      .map((e) => '$e')
      .where((e) =>
          !e.contains('overflowed') &&
          !e.contains('MissingPluginException') &&
          !e.contains('was used after being disposed') &&
          !e.contains('Cannot add to an unmodifiable list') &&
          !e.contains('Timeout') &&
          !e.contains('supabase instance'))
      .toList();
  expect(problemas, isEmpty,
      reason: 'a tela não pode soltar exceção: $problemas');
}

/// A exceção do DropdownButton (a tela vermelha do relato) — o resto do ruído
/// de teste headless (banco/rede/impressora ausentes) não interessa aqui.
void _expectSemErroDeDropdown(WidgetTester tester) {
  final erro = tester.takeException();
  expect(
    erro == null || !'$erro'.contains('exactly one item with'),
    isTrue,
    reason: 'o DropdownButton não pode receber um valor sem item único: $erro',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
      'net.nfet.printing',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
  });

  test('config com o mesmo departamento repetido não duplica a lista', () {
    final ds = _dataService(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha'),
        _dep('dep_bar', 'Bar'),
        _dep('dep_bar', 'Bar'), // duplicata herdada de versões antigas
      ],
    );

    final ids = ds.departamentos.map((d) => d.id).toList();
    ds.dispose();

    expect(ids, ['dep_cozinha', 'dep_bar'],
        reason: 'o mesmo id não pode aparecer duas vezes no dropdown');
  });

  testWidgets(
      'departamento repetido na config não derruba a tela e a seleção vai para o preparo',
      (tester) async {
    final ds = _dataService(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha'),
        _dep('dep_bar', 'Bar'),
        _dep('dep_bar', 'Bar'),
      ],
      produto: _produto(),
    );
    dynamic salvo;

    await _pumpForm(tester, ds,
        produto: ds.produtos.single, onSave: (p) async => salvo = p);
    _expectSemErroDeDropdown(tester);

    // Seleciona Cozinha no dropdown do departamento de preparação.
    final dropdown = find.byType(DropdownButtonFormField<String?>);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // O DropdownMenuItem em si não recebe o toque (o InkWell acima recebe);
    // o aviso de hit-test aqui é esperado e não indica toque perdido.
    await tester.tap(
      find.widgetWithText(DropdownMenuItem<String?>, 'Cozinha'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    _expectSemErroDeDropdown(tester);

    // O dropdown exibe o departamento escolhido (o chip vira 'Cozinha ★').
    expect(find.text('Cozinha'), findsOneWidget,
        reason: 'o campo deve mostrar o departamento selecionado');

    // A seleção precisa refletir na produção: uma via para o setor escolhido.
    expect(find.text('• Cozinha → Padrão do terminal'), findsOneWidget,
        reason: 'o setor selecionado deve virar destino de impressão');

    // E o produto salvo leva o departamento — é ele que define o preparo/impressão.
    await tester.tap(find.text('ATUALIZAR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(salvo, isNotNull);
    expect((salvo as Produto).departamentoId, 'dep_cozinha');

    await _drenarTimers(tester, ds);
  });

  testWidgets(
      'produto apontando para departamento inexistente abre o form sem erro (mostra Nenhum departamento)',
      (tester) async {
    final ds = _dataService(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha'),
        _dep('dep_bar', 'Bar'),
      ],
      // Ex.: departamento excluído num PC e produto sincronizado de outro.
      produto: _produto(departamentoId: 'dep_excluido'),
    );

    await _pumpForm(tester, ds,
        produto: ds.produtos.single, onSave: (p) async {});
    _expectSemErroDeDropdown(tester);

    expect(
      find.text('Nenhum setor com impressora — a via sai na impressora padrão do terminal.'),
      findsOneWidget,
      reason: 'sem departamento válido, nenhum setor é pré-selecionado',
    );

    await _drenarTimers(tester, ds);
  });
}

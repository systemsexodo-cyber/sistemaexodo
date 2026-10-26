// Inventário da Loja: contar sem tirar a mão do teclado e sem medo de perder.
//
// Pedido do usuário: "no inventário de estoque precisa ser mais fácil dar um
// ENTER ir para a linha de baixo e pode gravar para continuar depois também".
//
// Estes testes travam as duas partes:
//   1. ENTER no campo de contagem foca a linha de baixo (próximo produto);
//   2. as contagens viram rascunho gravado (SharedPreferences) e voltam quando
//      a tela é reaberta — só o rascunho é apagado ao aplicar o inventário.
//
// Rodar: flutter test test/inventario_enter_rascunho_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/pages/inventario_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/clock_check_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

final _empresa = Empresa(
  id: 'E1',
  razaoSocial: 'Loja Teste Inventário',
  slug: 'loja-teste-inventario',
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
);

Produto _produto(String id, String nome, {double estoque = 10}) => Produto(
      id: id,
      nome: nome,
      unidade: 'un',
      grupo: 'Geral',
      codigo: id,
      preco: 10,
      estoque: estoque,
      createdAt: DateTime(2026, 10, 22),
      updatedAt: DateTime(2026, 10, 22),
    );

/// Mesma janela/escala do teste do PDV: a lista de produtos precisa caber.
Future<DataService> _abrirInventario(WidgetTester tester) async {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa);
  ds.produtos.addAll([
    _produto('P1', 'Açaí 500ml'),
    _produto('P2', 'Bolo de fubá'),
    _produto('P3', 'Café torrado'),
  ]);

  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await _pumpPagina(tester, ds);
  return ds;
}

Future<void> _pumpPagina(WidgetTester tester, DataService ds) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DataService>.value(value: ds),
        ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        // O CustomAppBar (e o resto do app) também lê tema e relógio.
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
        ChangeNotifierProvider<ClockCheckService>(
            create: (_) => ClockCheckService()),
      ],
      child: const MaterialApp(home: InventarioPage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Fecha a página e drena os timers que o DataService cria.
Future<void> _fechar(WidgetTester tester, DataService ds) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  ds.dispose();
  SyncMonitorService.instance.dispose();
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(minutes: 7));
  }
}

/// Campos na ordem da árvore: [0] é a busca, depois um por produto.
Finder _campoProduto(int indiceProduto) =>
    find.byType(TextField).at(indiceProduto + 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ENTER no campo leva o foco para a linha de baixo', (tester) async {
    final ds = await _abrirInventario(tester);

    expect(find.byType(TextField), findsNWidgets(4),
        reason: 'busca + 3 produtos');

    await tester.enterText(_campoProduto(0), '5');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final primeiro =
        tester.widget<TextField>(_campoProduto(0)).focusNode;
    final segundo = tester.widget<TextField>(_campoProduto(1)).focusNode;
    final terceiro = tester.widget<TextField>(_campoProduto(2)).focusNode;

    expect(segundo!.hasPrimaryFocus, isTrue,
        reason: 'o ENTER tem de focar a linha de baixo (P2)');
    expect(primeiro!.hasPrimaryFocus, isFalse);
    expect(terceiro!.hasPrimaryFocus, isFalse,
        reason: 'não pode pular uma linha');

    // E digitar em seguida cai na linha certa.
    await tester.enterText(_campoProduto(1), '7');
    await tester.pump();
    expect(tester.widget<TextField>(_campoProduto(1)).controller!.text, '7');

    await _fechar(tester, ds);
  });

  testWidgets('ENTER na última linha solta o foco', (tester) async {
    final ds = await _abrirInventario(tester);

    await tester.enterText(_campoProduto(2), '3');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final terceiro = tester.widget<TextField>(_campoProduto(2)).focusNode;
    expect(terceiro!.hasPrimaryFocus, isFalse,
        reason: 'acabaram as linhas: o foco é liberado');

    await _fechar(tester, ds);
  });

  testWidgets('as contagens viram rascunho e voltam ao reabrir a tela',
      (tester) async {
    final ds = await _abrirInventario(tester);

    await tester.enterText(_campoProduto(1), '7');
    await tester.pump(const Duration(milliseconds: 800)); // debounce do rascunho
    await tester.pump();

    expect(find.textContaining('Rascunho gravado'), findsOneWidget,
        reason: 'a tela avisa que gravou');

    // Sai da tela (o dispose faz a gravação final).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));

    // Volra para a tela: as contagens estão lá de novo.
    await _pumpPagina(tester, ds);
    expect(
      tester.widget<TextField>(_campoProduto(1)).controller!.text,
      '7,00',
      reason: 'o rascunho reabre a contagem já preenchida',
    );
    expect(find.text('−3.00'), findsOneWidget,
        reason: 'a comparação com o sistema (10 − 7) já aparece');

    await _fechar(tester, ds);
  });
}
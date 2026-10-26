// Diálogo "O que deseja abrir?" → busca por nome lista SÓ pedidos em aberto.
//
// Pedido do caixa: na busca por nome desse diálogo devem aparecer apenas os
// pedidos em aberto (Pendente / Parcialmente Pago / Em Andamento); quitados
// ('Pago' ou totalmente recebidos) e cancelados ficam de fora.
//
// A lista é montada por `_buscarVendasSalvas` (lib/pages/venda_direta_page.dart),
// então o teste abre o diálogo de verdade pelo botão do teclado numérico e
// digita o nome do cliente no campo "Número ou nome do cliente".
//
// Rodar: flutter test test/busca_vendas_em_aberto_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
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
  razaoSocial: 'Loja Teste Busca',
  slug: 'loja-teste-busca',
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
);

/// Pedido de Charles com `preco` de total e pagamento opcional.
Pedido _pedidoCharles({
  required String numero,
  String status = 'Pendente',
  double preco = 10,
  bool pagamentoRecebido = false,
  bool temPagamento = false,
}) =>
    Pedido(
      id: numero,
      numero: numero,
      clienteNome: 'Charles',
      status: status,
      dataPedido: DateTime(2026, 10, 22, 20, 42),
      produtos: [
        ItemPedido(
          id: 'P1',
          nome: 'X-Burger',
          quantidade: 1,
          preco: preco,
        ),
      ],
      servicos: <ItemServico>[],
      pagamentos: temPagamento
          ? [
              PagamentoPedido(
                id: 'PG-$numero',
                tipo: TipoPagamento.pix,
                valor: preco,
                recebido: pagamentoRecebido,
              ),
            ]
          : null,
    );

DataService _dataService() {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa);
  // Mesma abertura de caixa do teste do PDV: sem isso a página pede caixa.
  ds.aberturasCaixa.add(
    AberturaCaixa(
      id: 'C1',
      numero: 'CAIXA-001',
      dataAbertura: DateTime(2026, 10, 22, 8),
      valorInicial: 100,
    ),
  );
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

/// Ruído de layout da janela de teste (linhas que estouram por poucos pixels).
void _drenarRuido(WidgetTester tester) {
  while (true) {
    final erro = tester.takeException();
    if (erro == null) break;
    final texto = '$erro';
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

/// Fecha a página e drena os timers que o DataService cria.
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

/// Abre o diálogo "O que deseja abrir?" e busca por nome.
Future<void> _buscarPorNome(WidgetTester tester, String nome) async {
  await tester.tap(
      find.byTooltip('Abrir comanda/mesa por número ou buscar venda salva'));
  await _pump(tester);

  final campo = find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));
  expect(campo, findsOneWidget, reason: 'o diálogo tem um campo de busca');

  await tester.enterText(campo, nome);
  await _pump(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockCanais();
  });

  testWidgets('a busca por nome no diálogo lista só os pedidos em aberto',
      (tester) async {
    final ds = await _abrirPdv(tester);

    ds.pedidos.addAll([
      _pedidoCharles(numero: 'PED-ABERTO', status: 'Pendente'),
      _pedidoCharles(numero: 'PED-PARCIAL', status: 'Parcialmente Pago'),
      _pedidoCharles(numero: 'PED-ANDAMENTO', status: 'Em Andamento'),
      // Fiado: pagamento lançado mas NÃO recebido → continua em aberto.
      _pedidoCharles(
          numero: 'PED-FIADO',
          temPagamento: true,
          pagamentoRecebido: false),
      // Quitados e cancelados ficam de fora.
      _pedidoCharles(numero: 'PED-PAGO', status: 'Pago'),
      _pedidoCharles(
          numero: 'PED-QUITADO',
          temPagamento: true,
          pagamentoRecebido: true),
      _pedidoCharles(numero: 'PED-CANCELADO', status: 'Cancelado'),
    ]);

    await _buscarPorNome(tester, 'charles');
    await _pump(tester);

    expect(find.textContaining('PED-ABERTO'), findsOneWidget,
        reason: 'pedido pendente é em aberto e tem de aparecer');
    expect(find.textContaining('PED-PARCIAL'), findsOneWidget,
        reason: 'parcialmente pago é em aberto');
    expect(find.textContaining('PED-ANDAMENTO'), findsOneWidget,
        reason: 'em andamento é em aberto');
    expect(find.textContaining('PED-FIADO'), findsOneWidget,
        reason: 'fiado não recebido continua em aberto');

    expect(find.textContaining('PED-PAGO'), findsNothing,
        reason: 'pedido quitado não entra na lista');
    expect(find.textContaining('PED-QUITADO'), findsNothing,
        reason: 'totalmente recebido mesmo sem status Pago também sai');
    expect(find.textContaining('PED-CANCELADO'), findsNothing,
        reason: 'cancelado nunca aparece');

    await _fecharPdv(tester, ds);
  });
}
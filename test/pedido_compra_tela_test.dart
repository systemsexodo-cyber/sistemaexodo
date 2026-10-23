// Ponto a ponto da TELA: relatório de reposição → pedido salvo → lista →
// detalhe → recebimento no estoque.
//
// O teste de serviço (`pedido_compra_fluxo_test.dart`) prova a regra; este
// prova que a tela realmente chama a regra e mostra o resultado:
//   1. selecionar tudo e "GERAR PEDIDO" salva um pedido por fornecedor;
//   2. "SALVAR E ENVIAR" deixa os pedidos como enviados;
//   3. o atalho "VER PEDIDOS" abre a lista com os pedidos;
//   4. tocar no pedido abre o detalhe;
//   5. "Receber no estoque" + "CONFIRMAR ENTRADA NO ESTOQUE" baixa o pedido e
//      soma as quantidades no produto.
//
// Rodar: flutter test test/pedido_compra_tela_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/pedido_compra.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/pages/estoque_reposicao_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

Empresa _empresa() => Empresa(
  id: 'EMPRESA-PEDIDO-TELA-TESTE',
  razaoSocial: 'Empresa Teste Pedido Tela',
  slug: 'empresa-teste-pedido-tela',
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
  configuracoes: {
    'estoques': [
      {'id': 'estoque_loja', 'nome': 'Loja', 'principal': true, 'ordem': 0},
    ],
  },
);

Produto _produto({
  required String id,
  required String nome,
  required double estoque,
  required double minimo,
  required String fornecedor,
  required double custo,
}) => Produto(
  id: id,
  nome: nome,
  unidade: 'UN',
  grupo: 'Teste',
  preco: custo * 2,
  precoCusto: custo,
  estoque: estoque,
  estoqueMinimo: minimo,
  estoquePorEstoque: {'estoque_loja': estoque},
  estoquePadraoId: 'estoque_loja',
  fornecedorNome: fornecedor,
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'plugins.flutter.io/path_provider',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(canal),
        (call) async => null,
      );
    }
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(canal),
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
    }

    EnvConfig.aplicarOverrides({
      'DB_HOST': 'banco-de-teste.invalid',
      'DB_HOST_FALLBACK': '',
      'DB_CLOUD_HOST': '',
    });
    NeonConfig.aplicarOverrides({
      'NEON_DATA_API_URL': '',
      'NEON_DATA_API_BASE_URL': '',
      'NEON_DATABASE_URL': '',
      'DATABASE_URL': '',
      'NEON_DATABASE_URL_UNPOOLED': '',
      'DATABASE_URL_UNPOOLED': '',
      'NEON_AUTH_BASE_URL': '',
      'NEON_AUTH_JWKS_URL': '',
      'NEON_FUNCTION_HELLO_BASE_URL': '',
      'NEON_FUNCTIONS_URL': '',
      'NEON_AWS_ENDPOINT_URL_S3': '',
      'AWS_ENDPOINT_URL_S3': '',
    });
  });

  testWidgets('relatório salva por fornecedor e o pedido é recebido pela tela',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ds = DataService();
    ds.setEmpresaAtual(_empresa());

    final racao = _produto(
      id: 'tela-racao',
      nome: 'Ração Premium',
      estoque: 2,
      minimo: 10,
      fornecedor: 'Fornecedor A',
      custo: 5,
    );
    final brinquedo = _produto(
      id: 'tela-brinquedo',
      nome: 'Brinquedo',
      estoque: 0,
      minimo: 5,
      fornecedor: 'Fornecedor A',
      custo: 2,
    );
    final petisco = _produto(
      id: 'tela-petisco',
      nome: 'Petisco',
      estoque: 1,
      minimo: 3,
      fornecedor: 'Fornecedor B',
      custo: 4,
    );
    await ds.addProduto(racao, registrarHistorico: false);
    await ds.addProduto(brinquedo, registrarHistorico: false);
    await ds.addProduto(petisco, registrarHistorico: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: ds),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: EstoqueReposicaoPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Os três produtos abaixo do mínimo aparecem no relatório.
    expect(find.text('Ração Premium'), findsOneWidget);
    expect(find.text('Brinquedo'), findsOneWidget);
    expect(find.text('Petisco'), findsOneWidget);

    // Seleciona todos e gera o pedido.
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pump();
    expect(find.text('GERAR PEDIDO'), findsOneWidget);
    await tester.tap(find.text('GERAR PEDIDO'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Finalizar Pedido de Compra'), findsOneWidget);
    expect(find.text('SALVAR E ENVIAR'), findsOneWidget);

    // Salvar e enviar: agrupa por fornecedor e já nasce enviado.
    await tester.tap(find.text('SALVAR E ENVIAR'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('2 pedidos salvos').evaluate().isNotEmpty) break;
    }

    expect(find.text('2 pedidos salvos'), findsOneWidget,
        reason: 'os três itens deveriam virar dois pedidos (A e B)');
    expect(find.text('VER PEDIDOS'), findsOneWidget);

    expect(ds.pedidosCompra, hasLength(2));
    final pedidoA = ds.pedidosCompra.firstWhere(
      (pedido) => pedido.fornecedorNome == 'Fornecedor A',
    );
    final pedidoB = ds.pedidosCompra.firstWhere(
      (pedido) => pedido.fornecedorNome == 'Fornecedor B',
    );
    expect(pedidoA.status, StatusPedidoCompra.enviado);
    expect(pedidoB.status, StatusPedidoCompra.enviado);
    expect(pedidoA.itens, hasLength(2));
    expect(pedidoB.itens, hasLength(1));
    expect(pedidoA.quantidadeTotal, 8 + 5);
    expect(pedidoB.quantidadeTotal, 2);

    // O atalho abre a lista de pedidos salvos.
    await tester.tap(find.text('VER PEDIDOS'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pedidos de Compra'), findsOneWidget);
    expect(find.text(pedidoA.numero), findsOneWidget);
    expect(find.text(pedidoB.numero), findsOneWidget);
    expect(find.textContaining('Fornecedor A'), findsWidgets);
    expect(find.textContaining('Fornecedor B'), findsWidgets);

    // Abre o pedido do fornecedor A e recebe tudo pela tela.
    await tester.tap(find.textContaining('Fornecedor A').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ITENS DO PEDIDO'), findsOneWidget);
    expect(find.text('Receber no estoque'), findsOneWidget);

    await tester.tap(find.text('Receber no estoque'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Receber Pedido de Compra'), findsOneWidget);
    expect(find.text('CONFIRMAR ENTRADA NO ESTOQUE'), findsOneWidget);

    await tester.tap(find.text('CONFIRMAR ENTRADA NO ESTOQUE'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Pedido recebido').evaluate().isNotEmpty) break;
    }
    expect(find.text('Pedido recebido'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));

    // De volta ao detalhe, o pedido aparece recebido.
    expect(find.text('Recebido'), findsWidgets);
    expect(ds.pedidoCompraPorId(pedidoA.id)!.status, StatusPedidoCompra.recebido);
    expect(
      ds.produtos.firstWhere((p) => p.id == racao.id).estoque,
      10,
      reason: '2 em estoque + 8 recebidos',
    );
    expect(
      ds.produtos.firstWhere((p) => p.id == brinquedo.id).estoque,
      5,
      reason: '0 em estoque + 5 recebidos',
    );
    expect(
      ds.produtos.firstWhere((p) => p.id == petisco.id).estoque,
      1,
      reason: 'o pedido do outro fornecedor não foi recebido',
    );

    // Drena os timers de rede/banco antes de desmontar (padrão dos testes de
    // tela deste projeto).
    await tester.pump(const Duration(seconds: 16));
    ds.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(minutes: 7));
      tester.takeException();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

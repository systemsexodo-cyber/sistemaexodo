// Setas ↑/↓ na tela de Pedidos: a borda de destaque acompanha a lista e o
// Enter abre o pedido destacado.
//
// O teste roda com banco/nuvem apontados para host inválido (só a memória do
// DataService importa), no mesmo padrão dos outros testes de tela.
//
// Rodar: flutter test test/pedidos_setas_teclado_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/pages/lancar_pedido_page.dart';
import 'package:sistema_exodo_novo/pages/pedidos_page.dart';
import 'package:sistema_exodo_novo/pages/venda_direta_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

Empresa _empresa() => Empresa(
  id: 'EMPRESA-SETAS-PEDIDOS-TESTE',
  razaoSocial: 'Empresa Teste Setas Pedidos',
  slug: 'empresa-teste-setas-pedidos',
  createdAt: DateTime(2026, 11, 3),
  updatedAt: DateTime(2026, 11, 3),
);

Pedido _pedido(String numero, {String? cliente}) => Pedido(
  id: 'pedido-$numero',
  numero: numero,
  clienteNome: cliente,
  dataPedido: DateTime(2026, 11, 3, 10),
  status: 'Pendente',
  // Um item dá total > 0: sem itens o pedido conta como "quitado" e o Enter
  // abriria o diálogo de pedido pago em vez do lançamento.
  produtos: [
    ItemPedido(id: 'item-$numero', nome: 'Ração', quantidade: 1, preco: 10),
  ],
  servicos: const [],
);

/// Card que está com a borda de destaque do teclado (ciano).
Finder _destaque() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border?.top.color == Colors.cyanAccent,
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
      'plugins.flutter.io/shared_preferences',
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

  testWidgets('setas movem a borda de destaque e o Enter abre o pedido',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ds = DataService();
    ds.setEmpresaAtual(_empresa());

    // Pedidos suficientes para a lista rolar: provar que a borda acompanha as
    // setas mesmo quando o card destacado ainda não foi construído.
    await tester.runAsync(() async {
      for (var i = 1; i <= 12; i++) {
        await ds.addPedido(
          _pedido('PED-90${i.toString().padLeft(2, '0')}',
              cliente: 'Cliente $i'),
        );
      }
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: ds),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: PedidosPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cliente 1'), findsOneWidget);
    expect(_destaque(), findsNothing,
        reason: 'a lista abre sem nenhum pedido destacado');

    // Abre a busca e escreve: as setas precisam correr a lista mesmo com o
    // cursor no texto.
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'PED-9');
    await tester.pump();
    expect(find.text('PED-9'), findsOneWidget,
        reason: 'o campo de busca aceita a digitação');

    // 1ª seta para baixo já cai no primeiro pedido.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_destaque(), findsOneWidget);

    // Desce até o segundo: a borda anda com a seta.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byWidget(tester.widget<Container>(_destaque())),
        matching: find.text('Cliente 2'),
      ),
      findsOneWidget,
      reason: 'a 2ª seta para baixo destaca o 2º pedido',
    );

    // Continua descendo além do que cabe na tela: a lista rola junto para a
    // borda não "sumir" (o ListView.builder só monta os cards próximos).
    // Vários quadros por tecla = o que a tela faz a 60fps no app real.
    for (var i = 3; i <= 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      for (var quadro = 0; quadro < 12; quadro++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(
      find.descendant(
        of: find.byWidget(tester.widget<Container>(_destaque())),
        matching: find.text('Cliente 12'),
      ),
      findsOneWidget,
      reason: 'a borda acompanha a rolagem até o último pedido',
    );

    // Sobe de volta até o primeiro.
    for (var i = 1; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      for (var quadro = 0; quadro < 12; quadro++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(
      find.descendant(
        of: find.byWidget(tester.widget<Container>(_destaque())),
        matching: find.text('Cliente 1'),
      ),
      findsOneWidget,
      reason: 'a seta para cima volta para o pedido anterior',
    );

    // Enter abre o pedido destacado.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LancarPedidoPage), findsOneWidget);
    expect(find.byType(VendaDiretaPage), findsNothing,
        reason: 'o Enter na lista não pode disparar o atalho de PDV');

    // Drena os timers de rede/banco antes de desmontar (padrão dos testes de
    // tela deste projeto).
    await tester.pumpWidget(const SizedBox.shrink());
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
  });
}

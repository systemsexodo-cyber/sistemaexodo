// Teste de fumaca da tela "Monitor de Sincronizacao".
//
// Sem nuvem configurada no ambiente de teste o Supabase responde vazio, e e
// exatamente esse o cenario que precisa funcionar: a tela mostra o resumo, os
// filtros e a mensagem de "nenhum erro", sem estourar excecao.
//
// A conta de "dias offline" e de "erro pendente" mora no modelo StatusSync e e
// testada em status_sync_test.dart, longe da UI: e o calculo que nao pode errar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/pages/monitor_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

void main() {
  setUp(() {
    // Plugins de plataforma (connectivity/audioplayers/path_provider/
    // shared_preferences) nao existem num teste headless e nao tem relacao com
    // o monitor — sem isso eles derrubam o teste com MissingPluginException.
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

  testWidgets('monitor abre, mostra contadores, filtros e painel de erros',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dataService = DataService();
    final authService = AuthService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: dataService),
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const MaterialApp(home: MonitorPage()),
      ),
    );

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
      if (find.text('Monitor de Sincronizacao').evaluate().isNotEmpty) break;
    }

    expect(find.text('Monitor de Sincronizacao'), findsOneWidget);

    // Contadores e filtros com os cortes que o suporte usa. "Online" e
    // "Offline +1 dia" aparecem nos dois lugares (contador e filtro).
    expect(find.text('Online'), findsWidgets);
    expect(find.text('Com erro'), findsOneWidget);
    expect(find.text('Com Erro'), findsWidgets);
    expect(find.text('Offline +1 dia'), findsWidgets);
    expect(find.text('Nunca sincronizou'), findsWidgets);
    expect(find.text('Nunca sync'), findsOneWidget);

    // Sem erro reportado pelos clientes: painel verde, nao lista vermelha.
    expect(
      find.text('Nenhum erro de sincronização registrado pelos clientes.'),
      findsOneWidget,
    );
    expect(find.textContaining('recarrega sozinho a cada 15s'), findsOneWidget);

    // ignore: avoid_print
    print('OK: monitor renderiza contadores, filtros e painel de erros');

    // O AuthService/DataService abrem conexao com o banco local e agendam
    // timeouts de seguranca de 15s; sem drenar isso o flutter_test acusa
    // "Multiple exceptions / A Timer is still pending" (nada a ver com a tela).
    await tester.pump(const Duration(seconds: 16));
    dataService.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      tester.takeException();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

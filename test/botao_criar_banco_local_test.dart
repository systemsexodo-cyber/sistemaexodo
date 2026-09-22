// Teste: confere que o botão "Criar Banco Local (se apagado)" aparece na tela de
// Backup e que ele responde (abre a confirmação) — sem executar a criação.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/pages/backup_restore_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

void main() {
  setUp(() {
    // Sem isso o teste headless morre com MissingPluginException de
    // connectivity/audioplayers/path_provider/shared_preferences (plugins de
    // plataforma nao existem no ambiente de teste) — nada a ver com o botao.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  testWidgets('botao Criar Banco Local aparece e responde', (tester) async {
    tester.view.physicalSize = const Size(1400, 6000);
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
        child: const MaterialApp(home: BackupRestorePage()),
      ),
    );

    // A tela le os backups .sql de C:\ExodoBackups\1 (dezenas de arquivos): cada
    // leitura e um I/O real, entao precisamos de varias voltas do event loop.
    for (var i = 0; i < 400; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      // erros de plugin (connectivity/audioplayers/path_provider) nao existem
      // num teste headless e nao tem relacao com o botao.
      tester.takeException();
      if (find.text('Criar Banco Local (se apagado)').evaluate().isNotEmpty) break;
    }

    final botao = find.text('Criar Banco Local (se apagado)');
    expect(botao, findsOneWidget, reason: 'o botao precisa aparecer na tela');
    // ignore: avoid_print
    print('OK: botao encontrado na tela de Backup');

    await tester.ensureVisible(botao);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(botao);

    for (var i = 0; i < 20 && find.text('Criar banco local').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Criar banco local'), findsOneWidget,
        reason: 'tocar no botao deve abrir a confirmacao');
    expect(find.textContaining('Nada é apagado'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
    // ignore: avoid_print
    print('OK: confirmacao abriu com Cancelar/Confirmar');

    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Criar banco local'), findsNothing);
    // ignore: avoid_print
    print('OK: cancelar fechou a confirmacao sem executar nada');

    // O AuthService agenda um timeout de seguranca de 15s no construtor e o
    // DatabaseService um de 15s por conexao; sem isso o flutter_test acusa
    // "A Timer is still pending" depois do teste.
    await tester.pump(const Duration(seconds: 16));
    // Cancela os timers periodicos do DataService (sync/fila/connectivity) e o
    // heartbeat do SyncMonitorService (singleton).
    dataService.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      tester.takeException();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

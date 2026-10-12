// O chip da versão no topo (`V1.0.40`) abre as novidades da versão.
//
// Este teste cobre a tela do diálogo: ela precisa ABRIR mesmo sem nuvem (sem
// detalhes publicados, sem bucket, sem Supabase inicializado) — é o caso de
// qualquer cliente no meio de uma queda de rede.
//
// Rodar: flutter test test/novidades_versao_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';
import 'package:sistema_exodo_novo/widgets/novidades_versao_dialog.dart';

void main() {
  testWidgets('abre mostrando a versão instalada e fecha no FECHAR',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => NovidadesVersaoDialog.mostrar(context),
              child: const Text('ABRIR'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ABRIR'));
    // Passes com tempo fixo: a tela busca as notas na nuvem (que não existe
    // aqui) e não pode ficar travada em "carregando".
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('Atualizações do sistema'), findsOneWidget,
        reason: 'o diálogo das novidades não abriu');
    expect(find.text('Você está na versão ${AppUpdateService.currentAppVersion}'),
        findsOneWidget,
        reason: 'a versão instalada não apareceu');
    expect(find.text('O QUE MUDOU NESTA VERSÃO'), findsOneWidget);
    // Sem nuvem, a explicação tem que ser essa — e não uma tela de erro.
    expect(
      find.textContaining('não publicou os detalhes desta versão'),
      findsOneWidget,
      reason: 'sem detalhes publicados o diálogo precisa explicar, não estourar',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'ficou travado carregando');

    await tester.tap(find.text('FECHAR'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Atualizações do sistema'), findsNothing);

    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

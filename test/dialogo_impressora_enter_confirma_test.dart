// Teste do teclado no diálogo "Selecionar Impressora Padrão".
//
// O caixa trabalha com leitor de código de barras: tudo o que ele precisa é
// bater o ENTER. Na finalização da venda o Enter já dispara a impressão, mas
// antes disso a impressora é perguntada — e essa pergunta também tem que ser
// resolvida com Enter (ou dispensada com Esc), sem clicar.
//
// O que fica travado aqui:
//   1. Enter no diálogo devolve o nome da impressora selecionada (imprime);
//   2. Escape devolve null (cancelamento);
//   3. o Enter não cai em "Cancelar" nem em "Salvar como impressora padrão".
//
// O canal do plugin `printing` é mockado (info/listPrinters) — o teste não
// depende de impressora instalada na máquina.
//
// Rodar: flutter test test/dialogo_impressora_enter_confirma_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/impressao_service.dart';

const _canalPrinting = MethodChannel('net.nfet.printing');

/// Abre o diálogo pelo MESMO caminho usado pelo PDV
/// (ImpressaoService.selecionarImpressoraPadrao) e devolve o Future do
/// showDialog, que resolve com o nome da impressora ou null (cancelado).
Future<Future<String?>> _abrirDialogo(WidgetTester tester) async {
  Future<String?>? resultado;

  // O diálogo tem altura fixa (cabeçalho + dropdown + 2 checkboxes + botões).
  // A janela de teste padrão (800x600) é menor que a janela real do PDV e
  // dispara overflow de layout — que não é o que este teste verifica.
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                resultado = ImpressaoService.selecionarImpressoraPadrao(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();

  expect(find.text('Selecionar Impressora Padrão'), findsOneWidget);
  expect(resultado, isNotNull, reason: 'O diálogo não chegou a ser aberto.');
  return resultado!;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalPrinting, (call) async {
      switch (call.method) {
        case 'printingInfo':
          return {'canListPrinters': true, 'canPickPrinter': true};
        case 'listPrinters':
          // O plugin 'printing' usa 'default'/'available' (não isDefault).
          return [
            {
              'name': 'Microsoft Print to PDF',
              'url': 'winspool://MS_PDF',
              'default': true,
              'available': true,
            },
            {
              'name': 'Impressora Exodo',
              'url': 'winspool://EXODO',
              'default': false,
              'available': true,
            },
          ];
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalPrinting, null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Enter no diálogo confirma a impressora', (tester) async {
    final resultado = await _abrirDialogo(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(await resultado, 'Microsoft Print to PDF');
    expect(find.text('Selecionar Impressora Padrão'), findsNothing);
  });

  testWidgets('Escape no diálogo cancela', (tester) async {
    final resultado = await _abrirDialogo(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await resultado, isNull);
    expect(find.text('Selecionar Impressora Padrão'), findsNothing);
  });
}
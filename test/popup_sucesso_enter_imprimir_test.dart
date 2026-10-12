// Teste do teclado na tela de "VENDA FINALIZADA!" (PopupSucessoVenda).
//
// Pedido do caixa: na finalização, o ENTER já tinha que imprimir, sem precisar
// mirar/clicar no botão "Imprimir".
//
// Dois defeitos anteriores causavam isso:
//   1. o foco inicial caía no botão "Fechar" — o Enter fechava a tela e a venda
//      ficava sem cupom impresso;
//   2. o `KeyboardListener` usava um `FocusNode()` criado dentro do `build` e
//      nunca focado: esse nó não recebia teclas, e o Enter ia para o botão em
//      foco (Fechar). Agora é um `Focus` de ouvinte, ancestral dos botões.
//
// O que fica travado aqui:
//   1. ao abrir, o foco real (primaryFocus) já é o do botão Imprimir;
//   2. Enter imprime exatamente UMA vez (sem imprimir em duplicado);
//   3. Enter também FINALIZA: a tela verde sai de cena antes da impressão —
//      sem isso ela ficava aberta de fundo, atrás do diálogo de impressora;
//   4. setas ← → andam pelos botões e o Enter segue o botão em foco;
//   5. Escape fecha;
//   6. sem callback de impressão, o Enter cai no Fechar.
//
// Rodar: flutter test test/popup_sucesso_enter_imprimir_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/pages/venda_direta_page.dart';

/// Deixa o timer de auto-fechar (2,5s) do popup expirar antes de o teste
/// encerrar — o `flutter test` falha se sobrar timer pendente.
Future<void> _vencerTimerAutoFechar(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 3000));
  await tester.pumpAndSettle();
}

/// Abre o popup de venda finalizada e devolve o estado da impressão.
class _Cenario {
  _Cenario(this.impressoes, this.fechou);

  int impressoes;
  bool fechou;
}

/// Monta o app com um botão "abrir" que mostra o popup de venda finalizada.
Future<_Cenario> _abrir(
  WidgetTester tester, {
  bool comImprimir = true,
}) async {
  final cenario = _Cenario(0, false);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                PopupSucessoVenda.mostrar(
                  context,
                  valor: 22.0,
                  titulo: 'VENDA FINALIZADA!',
                  subtitulo: 'CX1-0049',
                  onDismiss: () => cenario.fechou = true,
                  onImprimir: comImprimir ? () => cenario.impressoes++ : null,
                );
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
  return cenario;
}

void main() {
  testWidgets('ao abrir, o foco inicial já é o do botão Imprimir',
      (tester) async {
    await _abrir(tester);

    expect(find.text('VENDA FINALIZADA!'), findsOneWidget);

    final botao = tester.widget<ElevatedButton>(find.ancestor(
      of: find.text('Imprimir'),
      matching: find.byType(ElevatedButton),
    ));
    expect(botao.focusNode, isNotNull);
    expect(
      identical(FocusManager.instance.primaryFocus, botao.focusNode),
      isTrue,
      reason: 'O Enter precisa cair em Imprimir já no primeiro toque de tecla.',
    );

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('Enter imprime exatamente uma vez', (tester) async {
    final cenario = await _abrir(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.impressoes, 1,
        reason: 'O Enter na finalização deve imprimir 1 única vez.');

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('Enter imprime E finaliza: a tela verde sai de cena',
      (tester) async {
    final cenario = await _abrir(tester);

    expect(find.text('VENDA FINALIZADA!'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.impressoes, 1);
    expect(cenario.fechou, isTrue,
        reason: 'Imprimir já finaliza a venda (onDismiss precisa rodar).');
    expect(find.text('VENDA FINALIZADA!'), findsNothing,
        reason: 'A tela verde não pode ficar aberta de fundo após imprimir.');

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets(
      'a tela que a impressão abre depois não é fechada pelo popup',
      (tester) async {
    // Este é o defeito de ordem: se imprimíssemos ANTES de fechar a tela verde,
    // o `Navigator.pop` do fechamento cairia sobre a rota de cima (o diálogo de
    // impressora) e o fecharia no lugar da tela de venda finalizada. Aqui
    // simulamos a impressão abrindo uma rota e conferimos que ela sobrevive.
    final navChave = GlobalKey<NavigatorState>();
    final cenario = _Cenario(0, false);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navChave,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  PopupSucessoVenda.mostrar(
                    context,
                    valor: 22.0,
                    titulo: 'VENDA FINALIZADA!',
                    subtitulo: 'CX1-0049',
                    onDismiss: () => cenario.fechou = true,
                    onImprimir: () {
                      cenario.impressoes++;
                      navChave.currentState!.push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Center(child: Text('DIALOGO IMPRESSORA')),
                          ),
                        ),
                      );
                    },
                  );
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

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.impressoes, 1);
    expect(cenario.fechou, isTrue, reason: 'A venda precisa ser finalizada.');
    expect(find.text('DIALOGO IMPRESSORA'), findsOneWidget,
        reason: 'O fechamento do popup não pode derrubar a impressão.');
    expect(find.text('VENDA FINALIZADA!'), findsNothing);

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('Enter com o Fechar em foco fecha em vez de imprimir',
      (tester) async {
    final cenario = await _abrir(tester);

    // Botões visíveis: [Imprimir, Fechar]. Uma seta à direita vai para Fechar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final botaoFechar = tester.widget<ElevatedButton>(find.ancestor(
      of: find.text('Fechar'),
      matching: find.byType(ElevatedButton),
    ));
    expect(identical(FocusManager.instance.primaryFocus, botaoFechar.focusNode),
        isTrue,
        reason: 'A seta à direita deve ir de Imprimir para Fechar.');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.impressoes, 0,
        reason: 'Com o Fechar em foco, o Enter não pode imprimir.');
    expect(cenario.fechou, isTrue, reason: 'O Enter no Fechar deve fechar.');

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('seta à esquerda volta do Fechar para Imprimir', (tester) async {
    final cenario = await _abrir(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // -> Fechar
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // -> Imprimir
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.impressoes, 1);

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('Escape fecha o popup', (tester) async {
    final cenario = await _abrir(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(cenario.fechou, isTrue);
    expect(find.text('VENDA FINALIZADA!'), findsNothing);

    await _vencerTimerAutoFechar(tester);
  });

  testWidgets('sem callback de impressão, o Enter inicial fecha o popup',
      (tester) async {
    final cenario = await _abrir(tester, comImprimir: false);

    expect(find.text('Imprimir'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(cenario.fechou, isTrue);
    expect(cenario.impressoes, 0);

    await _vencerTimerAutoFechar(tester);
  });
}
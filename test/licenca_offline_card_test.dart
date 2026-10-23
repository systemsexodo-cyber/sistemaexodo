// Cartão da "Licença Offline" na tela de empresa.
//
// O cartão nasceu porque o código de liberação só era mostrado uma vez, no
// cadastro da empresa — depois ficava invisível, e não havia como o suporte
// pegar o código para passar ao cliente. Estes testes verificam o que o suporte
// vê e clica.
//
// Rodar: flutter test test/licenca_offline_card_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/widgets/licenca_offline_card.dart';

Widget _app({
  String codigo = 'EXO-BMJ01',
  int limite = 7,
  VoidCallback? onCopiar,
  VoidCallback? onGerarNovo,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: SingleChildScrollView(
      child: LicencaOfflineCard(
        codigo: codigo,
        limiteDiasOffline: limite,
        onCopiar: onCopiar ?? () {},
        onGerarNovo: onGerarNovo ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('mostra o código atual da empresa e o limite de dias', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Licença Offline (liberação do cliente)'), findsOneWidget);
    expect(find.text('EXO-BMJ01'), findsOneWidget);
    expect(
      find.textContaining('passar de 7 dias sem internet'),
      findsOneWidget,
    );
  });

  testWidgets('explica de onde vem o limite quando não é o padrão', (
    tester,
  ) async {
    await tester.pumpWidget(_app(limite: 3));
    await tester.pump();

    expect(
      find.textContaining('passar de 3 dias sem internet'),
      findsOneWidget,
    );
    expect(find.textContaining('limite desta empresa'), findsOneWidget);
  });

  testWidgets('o botão de copiar dispara a ação da tela', (tester) async {
    var copiou = false;
    await tester.pumpWidget(_app(onCopiar: () => copiou = true));
    await tester.pump();

    await tester.tap(find.text('Copiar código'));
    await tester.pump();

    expect(copiou, isTrue);
  });

  testWidgets('o botão de gerar novo dispara a ação da tela', (tester) async {
    var gerou = false;
    await tester.pumpWidget(_app(onGerarNovo: () => gerou = true));
    await tester.pump();

    await tester.tap(find.text('Gerar novo código'));
    await tester.pump();

    expect(gerou, isTrue);
  });

  testWidgets('empresa sem código não quebra: mostra um traço', (tester) async {
    await tester.pumpWidget(_app(codigo: '   '));
    await tester.pump();

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Copiar código'), findsOneWidget);
  });
}

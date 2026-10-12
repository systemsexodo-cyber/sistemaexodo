// Teste do CARD "Horários que mais vendem" do dashboard.
//
// O cálculo já tem teste próprio (`horarios_pico_test.dart`); aqui o que se
// garante é a TELA: se o pico aparece escrito, se a troca valor/quantidade
// funciona, se quem não vê totais não vê dinheiro, e se período sem venda
// mostra aviso em vez de um card vazio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_exodo_novo/utils/horarios_pico.dart';
import 'package:sistema_exodo_novo/widgets/horarios_pico_card.dart';

/// Vendas de exemplo: nada de manhã, forte das 18h às 20h.
List<MovimentoHora> _movimentosDeExemplo() {
  final dia = DateTime(2026, 9, 1);
  return [
    MovimentoHora(DateTime(2026, 9, 1, 10, 15), 20),
    MovimentoHora(DateTime(2026, 9, 1, 18, 5), 300),
    MovimentoHora(DateTime(2026, 9, 1, 18, 40), 250),
    MovimentoHora(DateTime(2026, 9, 1, 19, 30), 400),
    MovimentoHora(DateTime(2026, 9, 2, 19, 10), 350),
    MovimentoHora(DateTime(2026, 9, 2, 20, 45), 120),
    // A venda de um real é do dia 'dia' para o dia da semana não variar.
    MovimentoHora(dia.add(const Duration(hours: 21)), 1),
  ];
}

Future<void> _mostrar(
  WidgetTester tester, {
  required ResumoHorarios resumo,
  bool podeVerTotais = true,
  VoidCallback? onTrocarMetrica,
  String rotuloPeriodo = 'do Mês',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          child: HorariosPicoCard(
            resumo: resumo,
            podeVerTotais: podeVerTotais,
            rotuloPeriodo: rotuloPeriodo,
            onTrocarMetrica: onTrocarMetrica,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o pico, a melhor hora e o período no título',
      (tester) async {
    final resumo = calcularHorariosDePico(_movimentosDeExemplo());

    await _mostrar(tester, resumo: resumo);

    expect(find.text('Horários que mais vendem do Mês'), findsOneWidget);
    // Pico das 19h: as horas 18 e 19 passam de metade do pico, então a faixa
    // sai "18h às 20h" (a última hora entra inteira).
    expect(find.textContaining('Pico: 18h às 20h'), findsOneWidget);
    expect(find.textContaining('Melhor hora: 19h'), findsOneWidget);
    expect(find.text('Horas com mais movimento:'), findsOneWidget);
    expect(find.text('Dias que mais vendem:'), findsOneWidget);
    // 19h é o maior faturamento somado (400 + 350). O espaço depois do R$ é
    // fixo no intl (U+00A0), por isso a comparação é por expressão regular.
    expect(
      find.textContaining(RegExp(r'19h · R\$\s*750,00')),
      findsOneWidget,
    );
  });

  testWidgets('o pico por quantidade ignora os valores', (tester) async {
    final resumo = calcularHorariosDePico(
      _movimentosDeExemplo(),
      metrica: MetricaPico.quantidade,
    );

    await _mostrar(tester, resumo: resumo);

    // Contando vendas, 18h e 19h empatam com 2 cada (empate fica com a mais
    // cedo) — e nada de R$ na tela.
    expect(find.textContaining('Melhor hora: 18h'), findsOneWidget);
    expect(find.textContaining('2 vendas'), findsWidgets);
    expect(find.textContaining('R\$'), findsNothing);
  });

  testWidgets('a troca de métrica chama o callback e some quem não vê totais',
      (tester) async {
    var trocas = 0;
    final resumo = calcularHorariosDePico(_movimentosDeExemplo());

    await _mostrar(
      tester,
      resumo: resumo,
      onTrocarMetrica: () => trocas++,
    );

    expect(find.text('Ver pico por:'), findsOneWidget);
    await tester.tap(find.text('Quantidade'));
    expect(trocas, 1);

    // Sem permissão de totais, o seletor não aparece.
    await _mostrar(tester, resumo: resumo, podeVerTotais: false);
    expect(find.text('Ver pico por:'), findsNothing);
  });

  testWidgets('período sem venda avisa em vez de mostrar zero', (tester) async {
    final resumo = calcularHorariosDePico(const <MovimentoHora>[]);

    await _mostrar(tester, resumo: resumo);

    expect(
      find.text('Nenhuma venda no período para calcular o horário de pico'),
      findsOneWidget,
    );
    expect(find.textContaining('Pico:'), findsNothing);
    expect(find.text('Horas com mais movimento:'), findsNothing);
  });
}

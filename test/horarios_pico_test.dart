// Testes dos HORÁRIOS QUE MAIS VENDEM (o "horário de pico" do dashboard).
//
// O que está travado aqui:
//   • hora é hora CHEIA (19:59 conta como 19h);
//   • o pico é por FATURAMENTO (não por quantidade) e empate fica com a hora
//     mais cedo do dia — sem ordem aleatória;
//   • a faixa de pico só estica para o lado que continua vendendo (>= metade do
//     pico), então uma hora forte isolada não "contamina" a faixa;
//   • as horas sem movimento continuam existindo (com zero), para o gráfico não
//     pular horários;
//   • por dia da semana, cada dia tem a SUA hora de pico, pela mesma régua;
//   • período sem venda não inventa pico (horaDePico == -1).

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/utils/horarios_pico.dart';

/// Atalho para montar movimentos: `m(18, 30, 100)` = 18:30 valendo R$ 100.
MovimentoHora _m(int hora, int minuto, double valor, {DateTime? dia}) {
  final base = dia ?? DateTime(2026, 9, 23);
  return MovimentoHora(
      DateTime(base.year, base.month, base.day, hora, minuto), valor);
}

void main() {
  test('agrupa por hora cheia e mantém as 24 horas', () {
    final resumo = calcularHorariosDePico([
      _m(19, 5, 100),
      _m(19, 59, 50), // ainda é a hora 19
      _m(20, 0, 30), // e esta é a 20
      _m(11, 15, 10),
    ]);

    expect(resumo.porHora.length, 24);
    expect(resumo.porHora[19].total, 150);
    expect(resumo.porHora[19].quantidade, 2);
    expect(resumo.porHora[20].total, 30);
    expect(resumo.porHora[11].total, 10);
    // hora sem venda existe, zerada
    expect(resumo.porHora[3].total, 0);
    expect(resumo.porHora[3].quantidade, 0);
    expect(resumo.porHora[19].rotulo, '19h');
    expect(resumo.porHora[9].rotulo, '09h');
    expect(resumo.total, 190);
    expect(resumo.quantidade, 4);
  });

  test('o pico é por faturamento, não por quantidade', () {
    final resumo = calcularHorariosDePico([
      // 10h: três vendas pequenas
      _m(10, 0, 5),
      _m(10, 10, 5),
      _m(10, 20, 5),
      // 19h: uma venda grande
      _m(19, 0, 300),
    ]);

    expect(resumo.porHora[10].quantidade, 3);
    expect(resumo.horaDePico, 19, reason: 'R\$ 300 > R\$ 15');
    expect(resumo.horaDoPico!.total, 300);
  });

  test('empate no pico fica com a hora mais cedo', () {
    final resumo =
        calcularHorariosDePico([_m(21, 0, 200), _m(12, 0, 200), _m(18, 0, 100)]);
    expect(resumo.horaDePico, 12);
  });

  test('faixa de pico só estica para o lado que continua vendendo', () {
    final resumo = calcularHorariosDePico([
      _m(12, 0, 40), // hora forte mas ISOLADA
      _m(18, 0, 100),
      _m(19, 0, 400), // pico
      _m(20, 0, 250), // >= metade do pico, entra na faixa
      _m(21, 0, 60), // caiu demais, fica fora
    ]);

    expect(resumo.horaDePico, 19);
    expect(resumo.janelaDePico, [19, 20]);
    expect(resumo.rotuloJanela, '19h às 21h',
        reason: 'a faixa vai das 19h até o fim da hora 20');
    expect(resumo.parteNaJanela, closeTo((400 + 250) / 850, 0.0001));
  });

  test('uma hora só, sem vizinhas, não vira faixa longa', () {
    final resumo = calcularHorariosDePico([_m(9, 30, 50), _m(15, 0, 5)]);
    expect(resumo.horaDePico, 9);
    expect(resumo.janelaDePico, [9]);
    expect(resumo.rotuloJanela, '09h');
  });

  test('melhores horas ficam em ordem e sem as vazias', () {
    final resumo = calcularHorariosDePico([
      _m(18, 0, 100),
      _m(19, 0, 400),
      _m(20, 0, 250),
      _m(21, 0, 60),
      _m(12, 0, 40),
    ]);

    expect(resumo.melhoresHoras.map((h) => h.rotulo).toList(),
        ['19h', '20h', '18h', '21h', '12h']);
    expect(resumo.melhoresHoras.map((h) => h.hora).toList(), [19, 20, 18, 21, 12]);
  });

  test('por dia da semana: cada dia tem a sua hora de pico', () {
    final sabado = DateTime(2026, 9, 5);
    final domingo = DateTime(2026, 9, 6);
    final segunda = DateTime(2026, 9, 7);
    expect(sabado.weekday, DateTime.saturday);
    expect(domingo.weekday, DateTime.sunday);
    expect(segunda.weekday, DateTime.monday);

    final resumo = calcularHorariosDePico([
      _m(10, 0, 50, dia: sabado),
      _m(19, 0, 900, dia: sabado), // sábado vende bem de noite
      _m(11, 0, 80, dia: domingo),
      _m(12, 0, 120, dia: domingo),
      _m(9, 0, 30, dia: segunda), // segunda é fraca, e o pico é de manhã
      _m(9, 30, 45, dia: segunda),
    ]);

    // os dias vêm do que mais vende para o que menos vende
    expect(resumo.porDia.map((d) => d.diaSemana).toList(),
        [sabado.weekday, domingo.weekday, segunda.weekday]);

    final doSabado = resumo.porDia.first;
    expect(doSabado.nome, 'Sábado');
    expect(doSabado.total, 950);
    expect(doSabado.quantidade, 2);
    expect(doSabado.horaDePico, 19);

    final daSegunda = resumo.porDia.last;
    expect(daSegunda.nome, 'Segunda');
    expect(daSegunda.horaDePico, 9);
  });

  test('dá para olhar por quantidade: a hora muda de dono', () {
    final movimentos = [
      // 10h: muitas vendas pequenas (é o pico em QUANTIDADE)
      _m(10, 0, 5),
      _m(10, 10, 5),
      _m(10, 20, 5),
      _m(10, 30, 5),
      // 19h: uma venda grande (é o pico em VALOR)
      _m(19, 0, 300),
    ];

    final porValor = calcularHorariosDePico(movimentos);
    expect(porValor.metrica, MetricaPico.valor);
    expect(porValor.horaDePico, 19);
    expect(porValor.total, 320);
    expect(porValor.parteNaJanela, closeTo(300 / 320, 0.0001));

    final porQuantidade = calcularHorariosDePico(
      movimentos,
      metrica: MetricaPico.quantidade,
    );
    expect(porQuantidade.metrica, MetricaPico.quantidade);
    expect(porQuantidade.horaDePico, 10);
    expect(porQuantidade.total, 5);
    expect(porQuantidade.quantidade, 5);
    expect(porQuantidade.janelaDePico, [10]);
  });

  test('sem venda no período não existe pico', () {
    final resumo = calcularHorariosDePico(const []);
    expect(resumo.vazio, isTrue);
    expect(resumo.horaDePico, -1);
    expect(resumo.horaDoPico, isNull);
    expect(resumo.janelaDePico, isEmpty);
    expect(resumo.rotuloJanela, '—');
    expect(resumo.parteNaJanela, 0);
    expect(resumo.melhoresHoras, isEmpty);
    expect(resumo.porDia, isEmpty);
    expect(resumo.quantidade, 0);
  });
}

/// Horários que mais vendem (horário de pico).
///
/// Fica fora da tela de propósito: é conta pura, com teste próprio — o
/// dashboard só desenha o resultado. Assim o pico não depende de widget nenhum
/// e pode ser reaproveitado (relatório, dashboards de vendedor) sem copiar
/// lógica.
library;

/// Um movimento (venda ou pedido) reduzido ao que o cálculo precisa.
class MovimentoHora {
  final DateTime quando;
  final double valor;

  const MovimentoHora(this.quando, this.valor);
}

/// O que define "mais vende": o dinheiro que entrou ou a quantidade de vendas.
///
/// Os dois não caem sempre na mesma hora (uma hora pode ter muitas vendas
/// pequenas e outra poucas vendas grandes), por isso o dashboard deixa escolher.
enum MetricaPico { valor, quantidade }

/// Como uma hora do dia se comporta somando o período todo.
class HoraDePico {
  final int hora; // 0 a 23
  final double total;
  final int quantidade;

  const HoraDePico({
    required this.hora,
    required this.total,
    required this.quantidade,
  });

  /// "19h"
  String get rotulo => '${hora.toString().padLeft(2, '0')}h';

  @override
  String toString() => '$rotulo: R\$ ${total.toStringAsFixed(2)} ($quantidade)';
}

/// Como um dia da semana se comporta (para saber QUANDO o movimento acontece).
class DiaDePico {
  static const List<String> nomes = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];

  final int diaSemana; // 1 = segunda ... 7 = domingo
  final double total;
  final int quantidade;
  final int horaDePico; // -1 se não houve movimento

  const DiaDePico({
    required this.diaSemana,
    required this.total,
    required this.quantidade,
    required this.horaDePico,
  });

  String get nome => nomes[diaSemana - 1];
}

/// O retrato do período: as 24 horas, o pico, a faixa de pico e os dias.
class ResumoHorarios {
  /// Sempre 24 posições (as horas sem venda entram com zero).
  final List<HoraDePico> porHora;

  /// Horas com movimento, da que mais vende para a que menos vende.
  final List<HoraDePico> melhoresHoras;

  /// Hora que mais vendeu (por faturamento; empate fica com a mais cedo).
  final int horaDePico;

  /// Horas em volta do pico que continuam "cheias" (>= metade do pico), na
  /// régua escolhida.
  final List<int> janelaDePico;

  /// Dias da semana com movimento, do que mais vende para o que menos vende.
  final List<DiaDePico> porDia;

  /// Soma da métrica escolhida (dinheiro ou número de vendas).
  final double total;
  final int quantidade;

  /// Qual régua foi usada para achar o pico.
  final MetricaPico metrica;

  const ResumoHorarios({
    required this.porHora,
    required this.melhoresHoras,
    required this.horaDePico,
    required this.janelaDePico,
    required this.porDia,
    required this.total,
    required this.quantidade,
    this.metrica = MetricaPico.valor,
  });

  bool get vazio => quantidade == 0;

  HoraDePico? get horaDoPico =>
      horaDePico >= 0 && horaDePico < porHora.length ? porHora[horaDePico] : null;

  /// Quanto do movimento do período está na faixa de pico (0 a 1), na régua
  /// escolhida (faturamento ou quantidade).
  double get parteNaJanela {
    if (total <= 0 || janelaDePico.isEmpty) return 0;
    final naJanela = janelaDePico.fold<double>(0, (s, h) => s + porHora[h].total);
    return naJanela / total;
  }

  /// "18h às 22h" (a última hora entra inteira, por isso o +1h no fim).
  String get rotuloJanela {
    if (janelaDePico.isEmpty) return '—';
    final primeira = janelaDePico.first;
    final ultima = janelaDePico.last;
    if (primeira == ultima) return '${_hh(primeira)}h';
    return '${_hh(primeira)}h às ${_hh(ultima + 1)}h';
  }

  /// Hora "cheia" usada só para o rótulo (ex: 9 → "09").
  static String _hh(int hora) => hora.toString().padLeft(2, '0');
}

/// Limite de "hora cheia" para a faixa de pico: a hora vizinha entra na faixa
/// quando ainda vende pelo menos metade do que a hora de pico vendeu.
const double _limiteDaJanela = 0.5;

/// Agrupa os movimentos por hora do dia, acha o pico e a faixa de pico.
///
/// [metrica] diz se "mais vende" é dinheiro (`valor`, padrão) ou número de
/// vendas (`quantidade`).
ResumoHorarios calcularHorariosDePico(
  Iterable<MovimentoHora> movimentos, {
  MetricaPico metrica = MetricaPico.valor,
}) {
  final totais = List<double>.filled(24, 0);
  final quantidades = List<int>.filled(24, 0);
  final totaisDia = <int, double>{};
  final quantidadesDia = <int, int>{};
  // Matriz dia da semana × hora: é dela que sai a hora de pico de CADA dia
  // (mesma régua do pico do período: maior faturamento).
  final totaisDiaHora = <int, List<double>>{};

  var total = 0.0;
  var quantidade = 0;

  for (final movimento in movimentos) {
    final hora = movimento.quando.hour;
    final dia = movimento.quando.weekday;
    final peso = metrica == MetricaPico.valor ? movimento.valor : 1.0;
    totais[hora] += peso;
    quantidades[hora] += 1;
    totaisDia[dia] = (totaisDia[dia] ?? 0) + peso;
    quantidadesDia[dia] = (quantidadesDia[dia] ?? 0) + 1;
    final porHoraDoDia =
        totaisDiaHora.putIfAbsent(dia, () => List<double>.filled(24, 0));
    porHoraDoDia[hora] += peso;
    total += peso;
    quantidade += 1;
  }

  /// Hora de maior faturamento num conjunto de 24 posições (-1 se vazio).
  int picoDoDia(List<double> valores) {
    var melhor = -1;
    for (var hora = 0; hora < 24; hora++) {
      if (valores[hora] <= 0) continue;
      if (melhor == -1 || valores[hora] > valores[melhor]) melhor = hora;
    }
    return melhor;
  }

  final porHora = List<HoraDePico>.generate(
    24,
    (hora) => HoraDePico(
      hora: hora,
      total: totais[hora],
      quantidade: quantidades[hora],
    ),
  );

  // Hora de pico: mais faturamento; empate fica com a mais cedo do dia.
  var horaDePico = -1;
  for (var hora = 0; hora < 24; hora++) {
    if (totais[hora] <= 0) continue;
    if (horaDePico == -1 || totais[hora] > totais[horaDePico]) horaDePico = hora;
  }

  final janela = <int>[];
  if (horaDePico != -1) {
    final limite = totais[horaDePico] * _limiteDaJanela;
    var inicio = horaDePico;
    var fim = horaDePico;
    while (inicio > 0 && totais[inicio - 1] >= limite) {
      inicio--;
    }
    while (fim < 23 && totais[fim + 1] >= limite) {
      fim++;
    }
    for (var hora = inicio; hora <= fim; hora++) {
      janela.add(hora);
    }
  }

  final melhores = porHora.where((h) => h.total > 0).toList()
    ..sort((a, b) {
      final comparacao = b.total.compareTo(a.total);
      return comparacao != 0 ? comparacao : a.hora.compareTo(b.hora);
    });

  final dias = totaisDia.keys.map((dia) {
    return DiaDePico(
      diaSemana: dia,
      total: totaisDia[dia] ?? 0,
      quantidade: quantidadesDia[dia] ?? 0,
      horaDePico: picoDoDia(totaisDiaHora[dia] ?? List<double>.filled(24, 0)),
    );
  }).toList()
    ..sort((a, b) {
      final comparacao = b.total.compareTo(a.total);
      return comparacao != 0 ? comparacao : a.diaSemana.compareTo(b.diaSemana);
    });

  return ResumoHorarios(
    porHora: porHora,
    melhoresHoras: melhores,
    horaDePico: horaDePico,
    janelaDePico: janela,
    porDia: dias,
    total: total,
    quantidade: quantidade,
    metrica: metrica,
  );
}

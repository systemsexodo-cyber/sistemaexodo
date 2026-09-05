/// Tipo da regra de promoção.
enum TipoRegraPromocao {
  data('data', 'Período (data a data)'),
  diaSemana('diaSemana', 'Dia da semana'),
  quantidade('quantidade', 'Por quantidade'),
  valorMinimo('valorMinimo', 'Por valor mínimo');

  const TipoRegraPromocao(this.codigo, this.rotulo);

  final String codigo;
  final String rotulo;

  static TipoRegraPromocao fromCodigo(String? codigo) {
    for (final t in TipoRegraPromocao.values) {
      if (t.codigo == codigo) return t;
    }
    return TipoRegraPromocao.data;
  }
}

/// Uma regra de promoção configurada no produto.
///
/// Várias regras podem coexistir e seus descontos **empilham** (somam-se).
/// Cada regra pode conceder um desconto percentual OU um preço fixo, e pode
/// ser condicionada por período, dia da semana (com horário opcional),
/// quantidade mínima levada ou valor mínimo do produto no carrinho.
class RegraPromocao {
  final TipoRegraPromocao tipo;
  final String? nome; // Rótulo opcional (ex: "Terça da Ração")
  final bool ativo;
  final double? descontoPercentual; // % de desconto (0-100)
  final double? precoFixo; // Preço fixo promocional
  final DateTime? dataInicio; // Início da validade (opcional)
  final DateTime? dataFim; // Fim da validade (opcional)
  final List<int> diasSemana; // 1=segunda-feira ... 7=domingo (weekday do Dart)
  final int? horaInicioMin; // Horário de início em minutos desde 00:00 (opcional)
  final int? horaFimMin; // Horário de fim em minutos desde 00:00 (opcional)
  final double? quantidadeMinima; // Para tipo 'quantidade'
  final double? valorMinimo; // Para tipo 'valorMinimo'

  const RegraPromocao({
    required this.tipo,
    this.nome,
    this.ativo = true,
    this.descontoPercentual,
    this.precoFixo,
    this.dataInicio,
    this.dataFim,
    this.diasSemana = const [],
    this.horaInicioMin,
    this.horaFimMin,
    this.quantidadeMinima,
    this.valorMinimo,
  });

  bool get usaPercentual => descontoPercentual != null && descontoPercentual! > 0;
  bool get usaPrecoFixo => precoFixo != null && precoFixo! > 0;
  bool get temDesconto => usaPercentual || usaPrecoFixo;

  bool get temConfiguracoesRelevantes {
    if (!temDesconto) return false;
    switch (tipo) {
      case TipoRegraPromocao.data:
        return dataInicio != null || dataFim != null;
      case TipoRegraPromocao.diaSemana:
        return diasSemana.isNotEmpty || horaInicioMin != null || horaFimMin != null;
      case TipoRegraPromocao.quantidade:
        return (quantidadeMinima ?? 0) > 0;
      case TipoRegraPromocao.valorMinimo:
        return (valorMinimo ?? 0) > 0;
    }
  }

  /// Verifica apenas a janela de tempo (datas) e o dia/horário da semana.
  /// Não considera a condição de quantidade/valor mínimo (que depende do carrinho).
  bool janelaValidaNoMomento([DateTime? agora]) {
    if (!ativo) return false;
    final a = agora ?? DateTime.now();
    if (dataInicio != null && a.isBefore(dataInicio!)) return false;
    if (dataFim != null && a.isAfter(dataFim!)) return false;
    if (tipo == TipoRegraPromocao.diaSemana) {
      if (diasSemana.isNotEmpty && !diasSemana.contains(a.weekday)) return false;
      if (horaInicioMin != null && horaFimMin != null) {
        final minuto = a.hour * 60 + a.minute;
        if (minuto < horaInicioMin! || minuto > horaFimMin!) return false;
      }
    }
    return true;
  }

  /// Avalia a regra completa considerando o contexto do carrinho.
  bool aplicaPara({
    required double quantidade,
    required double? subtotalItem,
    DateTime? agora,
  }) {
    if (!janelaValidaNoMomento(agora)) return false;
    switch (tipo) {
      case TipoRegraPromocao.data:
        return true;
      case TipoRegraPromocao.diaSemana:
        return true; // janela já validou o dia/horário
      case TipoRegraPromocao.quantidade:
        return quantidade >= (quantidadeMinima ?? 0);
      case TipoRegraPromocao.valorMinimo:
        return (subtotalItem ?? 0) >= (valorMinimo ?? 0);
    }
  }

  /// Percentual de desconto que esta regra contribui (preço fixo é convertido
  /// em percentual equivalente relativo ao [precoBase]).
  double contribuicaoPercentual(double precoBase) {
    if (usaPercentual) return descontoPercentual!;
    if (usaPrecoFixo && precoBase > 0) {
      final pct = (precoBase - precoFixo!) / precoBase * 100;
      return pct > 0 ? pct : 0;
    }
    return 0;
  }

  /// Rótulo curto da condição (para exibir na lista).
  String get descricaoCondicao {
    switch (tipo) {
      case TipoRegraPromocao.data:
        final ini = dataInicio != null
            ? '${dataInicio!.day.toString().padLeft(2, '0')}/${dataInicio!.month.toString().padLeft(2, '0')}'
            : 'início';
        final fim = dataFim != null
            ? '${dataFim!.day.toString().padLeft(2, '0')}/${dataFim!.month.toString().padLeft(2, '0')}'
            : 'sem fim';
        return 'de $ini até $fim';
      case TipoRegraPromocao.diaSemana:
        const nomes = ['', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
        final dias = diasSemana.map((d) => nomes[d.clamp(1, 7)]).join(' · ');
        final hora = horaInicioMin != null && horaFimMin != null
            ? ' ${fmtHora(horaInicioMin!)}–${fmtHora(horaFimMin!)}'
            : '';
        return dias.isEmpty ? 'dias não definidos$hora' : '$dias$hora';
      case TipoRegraPromocao.quantidade:
        return 'a partir de ${_fmtNum(quantidadeMinima ?? 0)} un.';
      case TipoRegraPromocao.valorMinimo:
        return 'acima de R\$ ${_fmtNum(valorMinimo ?? 0)}';
    }
  }

  String get descricaoDesconto {
    if (usaPercentual) return '${_fmtNum(descontoPercentual!)}% off';
    if (usaPrecoFixo) return 'R\$ ${_fmtNum(precoFixo!)} fixo';
    return 'sem desconto definido';
  }

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String fmtHora(int minutos) {
    final h = (minutos ~/ 60).toString().padLeft(2, '0');
    final m = (minutos % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  RegraPromocao copyWith({
    TipoRegraPromocao? tipo,
    String? nome,
    bool? ativo,
    double? descontoPercentual,
    double? precoFixo,
    DateTime? dataInicio,
    DateTime? dataFim,
    List<int>? diasSemana,
    int? horaInicioMin,
    int? horaFimMin,
    double? quantidadeMinima,
    double? valorMinimo,
  }) {
    return RegraPromocao(
      tipo: tipo ?? this.tipo,
      nome: nome ?? this.nome,
      ativo: ativo ?? this.ativo,
      descontoPercentual: descontoPercentual ?? this.descontoPercentual,
      precoFixo: precoFixo ?? this.precoFixo,
      dataInicio: dataInicio ?? this.dataInicio,
      dataFim: dataFim ?? this.dataFim,
      diasSemana: diasSemana ?? this.diasSemana,
      horaInicioMin: horaInicioMin ?? this.horaInicioMin,
      horaFimMin: horaFimMin ?? this.horaFimMin,
      quantidadeMinima: quantidadeMinima ?? this.quantidadeMinima,
      valorMinimo: valorMinimo ?? this.valorMinimo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.codigo,
      'nome': nome,
      'ativo': ativo,
      'descontoPercentual': descontoPercentual,
      'precoFixo': precoFixo,
      'dataInicio': dataInicio?.toIso8601String(),
      'dataFim': dataFim?.toIso8601String(),
      'diasSemana': diasSemana,
      'horaInicioMin': horaInicioMin,
      'horaFimMin': horaFimMin,
      'quantidadeMinima': quantidadeMinima,
      'valorMinimo': valorMinimo,
    };
  }

  factory RegraPromocao.fromMap(Map<String, dynamic> map) {
    double? getDbl(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? getInt(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    DateTime? getDate(String key) {
      final v = map[key];
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return RegraPromocao(
      tipo: TipoRegraPromocao.fromCodigo(map['tipo']?.toString()),
      nome: map['nome']?.toString(),
      ativo: map['ativo'] != false,
      descontoPercentual: getDbl('descontoPercentual'),
      precoFixo: getDbl('precoFixo'),
      dataInicio: getDate('dataInicio'),
      dataFim: getDate('dataFim'),
      diasSemana: (map['diasSemana'] as List?)?.map((e) => (e is num) ? e.toInt() : (int.tryParse(e.toString()) ?? 0)).toList() ?? const [],
      horaInicioMin: getInt('horaInicioMin'),
      horaFimMin: getInt('horaFimMin'),
      quantidadeMinima: getDbl('quantidadeMinima'),
      valorMinimo: getDbl('valorMinimo'),
    );
  }
}

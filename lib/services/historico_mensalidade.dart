/// Histórico dos pagamentos da mensalidade da empresa.
///
/// Os registros vivem dentro de `empresas.configuracoes['historico_pagamentos']`
/// como uma lista de mapas:
/// `{competencia: '2026-11', valor: 120.0, pagamento_id: '123',
///   pago_em: '2026-11-04T12:00:00.000Z', origem: 'mercado_pago' | 'manual'}`.
///
/// Ficar nas configurações (em vez de uma tabela nova) faz o histórico chegar
/// junto com a empresa em toda leitura já existente — inclusive offline — e
/// não exige migração no banco.
class HistoricoMensalidade {
  const HistoricoMensalidade._();

  static const String chave = 'historico_pagamentos';

  /// Guarda só os registros mais recentes para a configuração não crescer sem
  /// fim (36 meses = 3 anos de mensalidades).
  static const int maximoRegistros = 36;

  static const List<String> _campos = [
    'competencia',
    'valor',
    'pagamento_id',
    'pago_em',
    'origem',
  ];

  /// Lê o histórico das configurações, ignorando entradas inválidas.
  static List<Map<String, dynamic>> ler(Map<String, dynamic>? configuracoes) {
    final bruto = configuracoes?[chave];
    if (bruto is! List) return const [];
    final registros = <Map<String, dynamic>>[];
    for (final item in bruto) {
      if (item is! Map) continue;
      final registro = <String, dynamic>{};
      for (final campo in _campos) {
        if (item[campo] != null) registro[campo] = item[campo];
      }
      final competencia = registro['competencia']?.toString().trim() ?? '';
      if (competencia.isEmpty) continue;
      registro['competencia'] = competencia;
      registros.add(registro);
    }
    return registros;
  }

  /// Devolve uma cópia das configurações com o pagamento registrado.
  ///
  /// A chave de deduplicação é o id do pagamento do Mercado Pago; nos OKs
  /// manuais (sem id) é a própria competência, para reconfirmar o mesmo mês
  /// atualizar o registro em vez de duplicá-lo.
  static Map<String, dynamic> registrar(
    Map<String, dynamic> configuracoes, {
    required String competencia,
    double? valor,
    String? pagamentoId,
    DateTime? pagoEm,
    String origem = 'mercado_pago',
  }) {
    final mes = competencia.trim();
    final idPagamento = (pagamentoId ?? '').trim();
    if (mes.isEmpty) return Map<String, dynamic>.from(configuracoes);

    final chaveRegistro = idPagamento.isNotEmpty
        ? 'pix:$idPagamento'
        : 'manual:$mes';
    final registros =
        ler(
            configuracoes,
          ).where((registro) => _chaveDe(registro) != chaveRegistro).toList()
          ..add({
            'competencia': mes,
            if (valor != null) 'valor': valor,
            if (idPagamento.isNotEmpty) 'pagamento_id': idPagamento,
            'pago_em': (pagoEm ?? DateTime.now()).toUtc().toIso8601String(),
            'origem': origem,
          });

    final novas = Map<String, dynamic>.from(configuracoes);
    novas[chave] = registros.length > maximoRegistros
        ? registros.sublist(registros.length - maximoRegistros)
        : registros;
    return novas;
  }

  /// Une duas versões do histórico (local × nuvem) sem duplicar: a chave é o
  /// id do pagamento (ou a competência, nos OKs manuais) e fica a versão mais
  /// recente de cada entrada.
  static List<Map<String, dynamic>> mesclar(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final porChave = <String, Map<String, dynamic>>{};
    for (final registro in [...a, ...b]) {
      final chave = _chaveDe(registro);
      final existente = porChave[chave];
      final dataRegistro = (registro['pago_em'] ?? '').toString();
      final dataExistente = (existente?['pago_em'] ?? '').toString();
      if (existente == null || dataRegistro.compareTo(dataExistente) >= 0) {
        porChave[chave] = registro;
      }
    }
    final registros = porChave.values.toList()
      ..sort(
        (x, y) => (x['pago_em'] ?? '').toString().compareTo(
          (y['pago_em'] ?? '').toString(),
        ),
      );
    return registros.length > maximoRegistros
        ? registros.sublist(registros.length - maximoRegistros)
        : registros;
  }

  static String _chaveDe(Map<String, dynamic> registro) {
    final id = (registro['pagamento_id'] ?? '').toString().trim();
    return id.isNotEmpty ? 'pix:$id' : 'manual:${registro['competencia']}';
  }

  /// '2026-11' -> '11/2026' (mantém o texto original se não reconhecer).
  static String rotuloCompetencia(String competencia) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(competencia.trim());
    if (match == null) return competencia;
    return '${match.group(2)}/${match.group(1)}';
  }

  /// Data do pagamento em dd/MM/yyyy ('' quando não reconhecida).
  static String rotuloData(Object? pagoEm) {
    final data = DateTime.tryParse((pagoEm ?? '').toString());
    if (data == null) return '';
    final local = data.toLocal();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    return '$dia/$mes/${local.year}';
  }

  /// Registros do mais recente para o mais antigo.
  static List<Map<String, dynamic>> recentesPrimeiro(
    List<Map<String, dynamic>> registros,
  ) {
    final ordenados = List<Map<String, dynamic>>.from(registros);
    ordenados.sort((a, b) {
      final dataA = (a['pago_em'] ?? '').toString();
      final dataB = (b['pago_em'] ?? '').toString();
      final porData = dataB.compareTo(dataA);
      if (porData != 0) return porData;
      return (b['competencia'] ?? '').toString().compareTo(
        (a['competencia'] ?? '').toString(),
      );
    });
    return ordenados;
  }
}

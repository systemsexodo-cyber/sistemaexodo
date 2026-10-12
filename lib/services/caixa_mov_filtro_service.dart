/// Filtro de movimentações do caixa por janela de horário.
///
/// O gestor precisa responder perguntas como "quanto entrou de PIX entre 18h e
/// 20h?" — as movimentações do caixa têm data (dia) e hora, mas a tela só
/// filtrava por forma de pagamento. A regra da janela de horário fica aqui,
/// fora da UI, para poder ser testada e reaproveitada pela barra de filtros do
/// Fluxo de Caixa e pelo modal de movimentações de um caixa já encerrado.
///
/// As horas são passadas como minutos desde a meia-noite (08:30 → 510) para
/// não depender de tipos do Flutter.
class CaixaMovFiltroService {
  const CaixaMovFiltroService._();

  /// Minutos desde a meia-noite de [data] (08:30 → 510).
  static int minutosDoDia(DateTime data) => data.hour * 60 + data.minute;

  /// 'HH:mm' a partir de minutos desde a meia-noite.
  static String formatarMinutos(int minutos) {
    final m = minutos % (24 * 60);
    final h = m ~/ 60;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  /// A janela está ativa? Só filtra quando início E fim foram escolhidos —
  /// um extremo só não define um intervalo.
  static bool janelaAtiva(int? inicioMin, int? fimMin) =>
      inicioMin != null && fimMin != null;

  /// [minutos] cai em [inicioMin]..[fimMin] (inclusivo nas duas pontas)?
  ///
  /// Se o fim for menor que o início a janela atravessa a meia-noite
  /// (ex.: 22:00 → 02:00), comum em bar/restaurante.
  static bool dentroDaJanela(int minutos, int inicioMin, int fimMin) {
    if (inicioMin <= fimMin) return minutos >= inicioMin && minutos <= fimMin;
    return minutos >= inicioMin || minutos <= fimMin;
  }

  /// Movimentações cujo horário cai na janela [inicioMin]..[fimMin].
  ///
  /// Janela inativa (faltando um dos extremos) devolve a lista intacta. Espera
  /// o formato de mapa usado pelo Fluxo de Caixa, onde 'data' é DateTime.
  static List<Map<String, dynamic>> porHorario(
    List<Map<String, dynamic>> movs, {
    int? inicioMin,
    int? fimMin,
  }) {
    if (!janelaAtiva(inicioMin, fimMin)) return List.of(movs);
    return movs.where((m) {
      final data = m['data'];
      if (data is! DateTime) return false;
      return dentroDaJanela(minutosDoDia(data.toLocal()), inicioMin!, fimMin!);
    }).toList();
  }

  /// Rótulo da janela ativa ('08:00 → 12:00'), ou `null` quando inativa.
  static String? rotulo(int? inicioMin, int? fimMin) {
    if (!janelaAtiva(inicioMin, fimMin)) return null;
    return '${formatarMinutos(inicioMin!)} → ${formatarMinutos(fimMin!)}';
  }
}

/// Helpers shared by NFC-e automatic retry flows.
class NfceDuplicidadeHelper {
  static bool ehDuplicidade(String? mensagem) {
    if (mensagem == null || mensagem.isEmpty) return false;
    return RegExp(r'\b539\b').hasMatch(mensagem) ||
        mensagem.toLowerCase().contains('duplicidade') ||
        mensagem.toLowerCase().contains('duplicada');
  }

  /// Reads nNF from the 44-digit access key cited in a SEFAZ 539 response.
  static int? numeroDaChaveDuplicada(String? mensagem) {
    if (mensagem == null) return null;
    final chave = RegExp(r'chNFe:(\d{44})').firstMatch(mensagem)?.group(1);
    if (chave == null) return null;
    return int.tryParse(chave.substring(25, 34));
  }

  static List<int> numerosDuplicados(String? mensagem) {
    if (mensagem == null || mensagem.isEmpty) return const [];
    final numeros = <int>{};
    for (final match in RegExp(r'chNFe:(\d{44})').allMatches(mensagem)) {
      final chave = match.group(1)!;
      final numero = int.tryParse(chave.substring(25, 34));
      if (numero != null && numero > 0) numeros.add(numero);
    }
    for (final match in RegExp(
      r'Números ocupados SEFAZ:\s*([\d, ]+)',
    ).allMatches(mensagem)) {
      for (final parte in match.group(1)!.split(',')) {
        final numero = int.tryParse(parte.trim());
        if (numero != null && numero > 0) numeros.add(numero);
      }
    }
    final resultado = numeros.toList()..sort();
    return resultado;
  }

  /// Número da nota pendente para reenvio. Zero/vazio não vale — aí a
  /// sequência pega o próximo livre.
  static int? numeroOriginalReenvio(String? numero) {
    final valor = int.tryParse((numero ?? '').trim()) ?? 0;
    return valor > 0 ? valor : null;
  }

  /// Número a usar neste reenvio: o original, salvo duplicidade 539 — aí
  /// avança. A emissão original não pula; o pulo só existe no reenvio.
  static int? numeroDoReenvio({
    required String? numeroAtual,
    String? mensagemErro,
    Iterable<int> ocupados = const [],
    int numeroInicial = 1,
  }) {
    final original = numeroOriginalReenvio(numeroAtual);
    if (original == null) return null;
    if (!ehDuplicidade(mensagemErro)) return original;
    return proximoAposDuplicidade(
      numeroTentado: original,
      ocupados: ocupados,
      duplicados: numerosDuplicados(mensagemErro),
      numeroInicial: numeroInicial,
    );
  }

  /// Só avança DEPOIS de duplicidade 539: sai do número recusado e dos
  /// números que a SEFAZ citou, sem varrer buracos para trás (cada teste
  /// extra é uma ida completa à SEFAZ).
  static int proximoAposDuplicidade({
    required int numeroTentado,
    Iterable<int> ocupados = const [],
    Iterable<int> duplicados = const [],
    int numeroInicial = 1,
  }) {
    final usados = <int>{
      ...ocupados,
      ...duplicados,
      if (numeroTentado > 0) numeroTentado,
    };
    final piso = numeroInicial < 1 ? 1 : numeroInicial;
    var candidato = numeroTentado < piso ? piso : numeroTentado + 1;
    final maiorDuplicado = duplicados.fold<int>(
      0,
      (atual, numero) => numero > atual ? numero : atual,
    );
    if (maiorDuplicado >= candidato) candidato = maiorDuplicado + 1;
    if (candidato < piso) candidato = piso;
    while (usados.contains(candidato)) {
      candidato++;
    }
    return candidato;
  }
}

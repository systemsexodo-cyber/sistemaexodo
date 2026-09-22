/// Sanitização de texto para o banco LOCAL do app.
///
/// O PostgreSQL empacotado com o sistema foi inicializado com o locale do
/// Windows em português, então o banco do app nasceu em **WIN1252** (não UTF8).
/// O pacote `postgres` do Dart trabalha em UTF8, e o Postgres recusa gravar
/// qualquer caractere que o WIN1252 não tenha, com o erro `22P05`:
///
///   "caractere com sequência de bytes 0xe2 0x86 0x92 na codificação UTF8
///    não tem equivalente na codificação WIN1252"
///
/// Isso não vale só para emoji: o histórico de produtos do app escreve
/// "Estoque: 10 → 8 unidades", e era essa a seta que fazia a tabela
/// `produto_historico` nunca fechar na conferência local × nuvem.
///
/// A carga útil do WIN1252 é: ASCII, LATIN-1 (0xA0–0xFF) e 27 caracteres
/// "altos" que vieram da extensão da Microsoft (€ „ … † ‡ • – — “ ” ‘ ’ ™ …).
/// Os testados na prática contra o banco do sistema estão em
/// `test/win1252_test.dart`. Tudo o que está fora disso — setas (→ ← ↑ ↓),
/// checkmarks (✅ ❌ ✓), emojis — não entra; aqui esses símbolos viram um
/// equivalente ASCII (mesma tabela usada pelo sincronizador da bandeja, em
/// `sincronizar_local_supabase.py`) e o resto vira `?`, em vez de derrubar a
/// gravação.
///
/// O caminho definitivo para não precisar disso é migrar o banco local para
/// UTF8 (`MIGRAR_BANCO_LOCAL_UTF8.bat`).
library;

class Win1252 {
  const Win1252._();

  /// Símbolos usados pelo sistema que não existem no WIN1252 e seu equivalente.
  ///
  /// Só entram aqui caracteres RECUSADOS pelo banco local — travessões, aspas
  /// curvas, bullets e reticências são preservados porque o WIN1252 os guarda.
  static const Map<String, String> _substituicoes = {
    '\u2192': '->', // → seta (aparece no histórico: "10 → 8")
    '\u2190': '<-', // ← seta
    '\u2191': '^', //  ↑ seta
    '\u2193': 'v', //  ↓ seta
    '\u21d2': '=>', // ⇒
    '\u21d0': '<=', // ⇐
    '\u274c': 'X', //  ❌
    '\u2705': 'OK', // ✅
    '\u2714': 'OK', // ✔
    '\u2713': 'OK', // ✓
    '\u2717': 'X', //  ✗
    '\u2718': 'X', //  ✘
    '\u26a0': '!', //  ⚠
    '\u2139': 'i', //  ℹ
    '\u200b': '', //   zero width space
    '\u200c': '',
    '\u200d': '',
    '\u200e': '',
    '\u200f': '',
    '\ufeff': '', //   BOM
  };

  /// Os 27 caracteres que só existem no WIN1252 (faixa 0x80–0x9F da Microsoft)
  /// e que, por isso, não aparecem numa checagem por faixa de código.
  static const Set<int> _altosDoCp1252 = {
    0x20AC, // €
    0x201A, // ‚
    0x0192, // ƒ
    0x201E, // „
    0x2026, // …
    0x2020, // †
    0x2021, // ‡
    0x02C6, // ˆ
    0x2030, // ‰
    0x0160, // Š
    0x2039, // ‹
    0x0152, // Œ
    0x017D, // Ž
    0x2018, // ‘
    0x2019, // ’
    0x201C, // “
    0x201D, // ”
    0x2022, // •
    0x2013, // –
    0x2014, // —
    0x02DC, // ˜
    0x2122, // ™
    0x0161, // š
    0x203A, // ›
    0x0153, // œ
    0x017E, // ž
    0x0178, // Ÿ
  };

  /// Bytes que o WIN1252 não define (a faixa 0x80–0x9F tem buracos).
  static const Set<int> _naoDefinidos = {0x81, 0x8D, 0x8F, 0x90, 0x9D};

  /// Este caractere (ponto de código Unicode) pode ser gravado no WIN1252?
  static bool representavel(int rune) =>
      _altosDoCp1252.contains(rune) ||
      (rune >= 0x20 && rune <= 0x7E) ||
      (rune >= 0x80 && rune <= 0x9F && !_naoDefinidos.contains(rune)) ||
      (rune >= 0xA0 && rune <= 0xFF);

  /// Devolve o texto pronto para gravar no banco local WIN1252.
  ///
  /// Texto que já é representável volta idêntico — acentos (á, ç, ã), travessão
  /// (—), aspas curvas (“ ”) e bullets (•) são preservados.
  static String sanitizar(String texto) {
    if (texto.isEmpty) return texto;

    var resultado = texto;
    for (final par in _substituicoes.entries) {
      if (resultado.contains(par.key)) {
        resultado = resultado.replaceAll(par.key, par.value);
      }
    }

    if (_tudoRepresentavel(resultado)) return resultado;

    final buffer = StringBuffer();
    for (final rune in resultado.runes) {
      buffer.write(representavel(rune) ? String.fromCharCode(rune) : '?');
    }
    return buffer.toString();
  }

  static bool _tudoRepresentavel(String texto) {
    for (final rune in texto.runes) {
      if (!representavel(rune)) return false;
    }
    return true;
  }

  /// Trabalha sobre um valor já convertido para parâmetro: só texto é ajustado;
  /// número, data e binário passam como estão.
  static Object? sanitizarValor(Object? valor) =>
      valor is String ? sanitizar(valor) : valor;
}

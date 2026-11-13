import '../models/produto.dart';

/// Busca de produtos tolerante à digitação — usada pelo PDV e pela loja.
///
/// Regras:
/// - ignora maiúsculas, acentos e pontuação ("ração" = "racao");
/// - combina as palavras em QUALQUER ordem: "premier filhos" acha
///   "PREMIER RACAS PEQUENAS FILHOTES";
/// - aceita pedaço de palavra: "premier rac", "premier pequenas";
/// - tolera até 2 erros de digitação em palavras com 4+ letras:
///   "primer racas pequeas" também acha "PREMIER RACAS PEQUENAS FILHOTES".
class BuscaProdutos {
  BuscaProdutos._();

  static const Map<String, String> _acentos = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
  };

  static String semAcentos(String texto) {
    final buffer = StringBuffer();
    for (final letra in texto.split('')) {
      buffer.write(_acentos[letra] ?? letra);
    }
    return buffer.toString();
  }

  /// Minúsculo, sem acento e com pontuação trocada por espaço.
  static String normalizar(String texto) => semAcentos(texto.toLowerCase())
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static List<String> palavras(String texto) => normalizar(texto)
      .split(' ')
      .where((palavra) => palavra.isNotEmpty)
      .toList(growable: false);

  /// Palavras que entram na busca: descarta artigos de 1 letra, mas mantém
  /// números (código do produto pode ter 1 dígito).
  static List<String> termos(String consulta) => palavras(consulta)
      .where(
        (palavra) =>
            palavra.length >= 2 || RegExp(r'^[0-9]+$').hasMatch(palavra),
      )
      .toList(growable: false);

  /// O que foi digitado ([alvo]) casa com a palavra do produto?
  static bool palavraCombina(String alvo, String disponivel) {
    if (disponivel.startsWith(alvo) || disponivel.contains(alvo)) return true;
    // Erro de digitação: só vale a pena calcular quando as duas primeiras
    // letras batem — isso barra quase todas as comparações e mantém a busca
    // rápida mesmo com milhares de produtos.
    if (alvo.length >= 4 &&
        disponivel.length >= 4 &&
        alvo[0] == disponivel[0] &&
        alvo[1] == disponivel[1]) {
      return _ateDoisErros(alvo, disponivel);
    }
    return false;
  }

  /// Levenshtein com corte: interessa saber só se a distância chega a 2.
  static bool _ateDoisErros(String a, String b) {
    if ((a.length - b.length).abs() > 2) return false;
    var anterior = List<int>.generate(b.length + 1, (indice) => indice);
    for (var i = 1; i <= a.length; i++) {
      final atual = List<int>.filled(b.length + 1, 0);
      atual[0] = i;
      var menorDaLinha = i;
      for (var j = 1; j <= b.length; j++) {
        final custo = a[i - 1] == b[j - 1] ? 0 : 1;
        atual[j] = [
          atual[j - 1] + 1,
          anterior[j] + 1,
          anterior[j - 1] + custo,
        ].reduce((x, y) => x < y ? x : y);
        if (atual[j] < menorDaLinha) menorDaLinha = atual[j];
      }
      if (menorDaLinha > 2) return false;
      anterior = atual;
    }
    return anterior[b.length] <= 2;
  }

  static String _extrasDoProduto(Produto produto) => normalizar([
    produto.codigo ?? '',
    produto.codigoBarras ?? '',
    produto.grupo,
    produto.descricao ?? '',
    produto.descricaoLoja ?? '',
    ...produto.todosCodigosBarras,
  ].join(' '));

  /// Nota do produto para a consulta. 0 = não serve.
  ///
  /// Todas as palavras digitadas precisam aparecer (no nome ou em código,
  /// grupo e descrição). Quanto melhor o encaixe, maior a nota.
  static int pontuar(
    Produto produto,
    List<String> termosBusca,
    String consultaNormalizada,
  ) {
    if (termosBusca.isEmpty) return 0;
    final nome = normalizar(produto.nome);
    final nomePalavras = nome.split(' ');
    String? extras;
    var nota = 0;

    for (final termo in termosBusca) {
      final int pontos;
      if (nomePalavras.any((palavra) => palavra.startsWith(termo))) {
        pontos = 40; // começo de uma palavra do nome
      } else if (nome.contains(termo)) {
        pontos = 24; // pedaço de palavra no meio do nome
      } else if (nomePalavras.any(
        (palavra) => palavraCombina(termo, palavra),
      )) {
        pontos = 16; // nome com erro de digitação
      } else {
        extras ??= _extrasDoProduto(produto);
        final extrasPalavras = extras.split(' ');
        if (extrasPalavras.any((palavra) => palavra.startsWith(termo))) {
          pontos = 9; // código, grupo ou descrição
        } else if (extras.contains(termo)) {
          pontos = 6;
        } else if (extrasPalavras.any(
          (palavra) => palavraCombina(termo, palavra),
        )) {
          pontos = 4;
        } else {
          return 0;
        }
      }
      nota += pontos;
    }

    // Frase digitada inteira igual/início/meio do nome vale muito mais.
    if (consultaNormalizada.isNotEmpty) {
      if (nome == consultaNormalizada) {
        nota += 1000;
      } else if (nome.startsWith(consultaNormalizada)) {
        nota += 300;
      } else if (nome.contains(consultaNormalizada)) {
        nota += 150;
      }
    }
    return nota;
  }

  /// Um texto (nome de serviço, por exemplo) serve para a consulta?
  static bool textoCorresponde(String texto, List<String> termosBusca) {
    if (termosBusca.isEmpty) return false;
    final normalizado = normalizar(texto);
    final palavrasTexto = normalizado.split(' ');
    return termosBusca.every(
      (termo) =>
          normalizado.contains(termo) ||
          palavrasTexto.any((palavra) => palavraCombina(termo, palavra)),
    );
  }

  /// Produtos que atendem a consulta, do mais parecido para o menos parecido.
  static List<Produto> filtrar(Iterable<Produto> produtos, String consulta) {
    final termosBusca = termos(consulta);
    if (termosBusca.isEmpty) return <Produto>[];
    final consultaNormalizada = normalizar(consulta);
    final achados = <MapEntry<Produto, int>>[];
    for (final produto in produtos) {
      final nota = pontuar(produto, termosBusca, consultaNormalizada);
      if (nota > 0) achados.add(MapEntry<Produto, int>(produto, nota));
    }
    achados.sort((a, b) {
      final porNota = b.value.compareTo(a.value);
      if (porNota != 0) return porNota;
      return a.key.nome.toLowerCase().compareTo(b.key.nome.toLowerCase());
    });
    return achados.map((entrada) => entrada.key).toList(growable: false);
  }
}

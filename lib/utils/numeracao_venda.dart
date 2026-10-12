/// Regras de numeração de venda e pedido — um só lugar para o formato.
///
/// O formato é `<PREFIXO>-<0000>`:
///
///   * `PED-0001` — pedido tradicional (encomenda, mesa, delivery);
///   * `CX1-0001` — venda do PDV, onde `CX1` é o nome DESTE caixa/computador;
///   * `VND-0001` — venda do PDV em máquina que ainda não foi nomeada.
///
/// Por que o nome do caixa virou prefixo: dois computadores sem internet não têm
/// como combinar o número da venda. Sem nome, os dois geram "o maior que eu
/// tenho + 1" e chegam os dois em `VND-0003`. Com um nome por máquina, cada uma
/// tem a própria sequência e o número nunca colide — sem depender da nuvem.
///
/// Quem separa "venda do PDV" de "pedido tradicional" é o prefixo: tudo o que
/// **não** começa com `PED-` é venda de PDV (era essa a regra do antigo
/// `startsWith('VND-')`; conferido no banco: em `pedidos` só existem números
/// `PED-` e `VND-`, então a equivalência é exata para todo o histórico).
library;

class NumeracaoVenda {
  NumeracaoVenda._();

  static const String prefixoPedido = 'PED';
  static const String prefixoLegado = 'VND';

  /// Prefixo + dígitos. O prefixo é curto e alfanumérico (CX1, CX10, LOJA2...).
  static final RegExp _padrao = RegExp(r'^([A-Z][A-Z0-9]{0,7})-(\d{1,12})$');

  /// Aceita tudo o que o app usa como número; devolve null quando não segue o
  /// formato (vazio, texto solto, número corrompido).
  static (String, int)? separar(String? numero) {
    final texto = (numero ?? '').trim().toUpperCase();
    if (texto.isEmpty) return null;
    final m = _padrao.firstMatch(texto);
    if (m == null) return null;
    final valor = int.tryParse(m.group(2)!);
    if (valor == null) return null;
    return (m.group(1)!, valor);
  }

  static String? prefixoDe(String? numero) => separar(numero)?.$1;

  static int? valorDe(String? numero) => separar(numero)?.$2;

  static String formatar(String prefixo, int numero) =>
      '${prefixo.trim().toUpperCase()}-${numero.toString().padLeft(4, '0')}';

  /// Limpa o nome digitado do caixa: 'cx 1' → 'CX1'.
  ///
  /// Devolve null quando não sobra nada utilizável ou quando o nome colide com
  /// um prefixo reservado (`PED` é de pedido tradicional, `VND` é o das máquinas
  /// sem nome — usar qualquer um dos dois recriaria a colisão entre caixas).
  static String? normalizarCaixa(String? bruto) {
    final limpo = (bruto ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (limpo.isEmpty || limpo.length > 8) return null;
    if (!RegExp(r'^[A-Z]').hasMatch(limpo)) return null;
    if (limpo == prefixoPedido || limpo == prefixoLegado) return null;
    return limpo;
  }

  /// Pedido tradicional: 'PED-...' ou sem número nenhum (pedido antigo).
  static bool ehPedidoTradicional(String? numero) {
    final texto = (numero ?? '').trim().toUpperCase();
    return texto.isEmpty || texto.startsWith('$prefixoPedido-');
  }

  /// Venda do PDV (balcão): qualquer número que não seja pedido tradicional.
  static bool ehVendaPdv(String? numero) =>
      (numero ?? '').trim().isNotEmpty && !ehPedidoTradicional(numero);

  /// Maior número já usado com este prefixo (0 se não houver nenhum).
  ///
  /// Só conta números do MESMO prefixo: a sequência de `CX1` e a de `CX2` são
  /// independentes de propósito.
  static int maiorDoPrefixo(Iterable<String?> numeros, String prefixo) {
    final alvo = prefixo.trim().toUpperCase();
    var maior = 0;
    for (final numero in numeros) {
      final separado = separar(numero);
      if (separado == null || separado.$1 != alvo) continue;
      if (separado.$2 > maior) maior = separado.$2;
    }
    return maior;
  }

  /// Extrai o número de venda de um texto livre — a observação do histórico de
  /// estoque é escrita como `Venda VND-0168 ...` / `Venda CX1-0003 ...`.
  ///
  /// O prefixo é genérico de propósito: a linha pode ter vindo de OUTRO caixa
  /// ('CX2-0007'), cujo nome esta máquina não conhece.
  static String? numeroNaObservacao(String? texto) {
    final bruto = (texto ?? '').trim();
    if (bruto.isEmpty) return null;
    final m = RegExp(r'\b[A-Za-z][A-Za-z0-9]{1,7}-\d+\b').firstMatch(bruto);
    final achado = m?.group(0);
    return achado == null ? null : achado.toUpperCase();
  }

  static Set<int> usadosDoPrefixo(Iterable<String?> numeros, String prefixo) {
    final alvo = prefixo.trim().toUpperCase();
    final usados = <int>{};
    for (final numero in numeros) {
      final separado = separar(numero);
      if (separado != null && separado.$1 == alvo) usados.add(separado.$2);
    }
    return usados;
  }

  /// Próximo número livre do prefixo.
  ///
  /// [piso] é o menor número que pode ser entregue — vem do maior número já
  /// visto no passado (`exodo_min_numero_...`). Ele existe porque a lista em
  /// memória pode estar vazia (app abrindo, troca de empresa): sem o piso o
  /// contador voltaria ao 1 e repetiria uma venda que já existe.
  static int proximoNumeroLivre({
    required Iterable<String?> numeros,
    required String prefixo,
    int piso = 0,
  }) {
    final usados = usadosDoPrefixo(numeros, prefixo);
    final maior = usados.isEmpty ? 0 : usados.reduce((a, b) => a > b ? a : b);
    var proximo = (maior > piso ? maior : piso) + 1;
    if (proximo < 1) proximo = 1;
    while (usados.contains(proximo)) {
      proximo++;
    }
    return proximo;
  }
}

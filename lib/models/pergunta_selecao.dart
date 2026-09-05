/// Modelo que representa uma opção de resposta para uma pergunta de seleção
class OpcaoPerguntaSelecao {
  final String id;
  final String produtoId; // ID do produto associado que terá estoque baixado
  final String nome; // Nome de exibição da opção
  final double precoAdicional; // Valor que soma ao preço do combo se selecionado
  final double quantidadeBaixa; // Quantidade de baixa no estoque (ex: 1.0 ou 0.5)

  OpcaoPerguntaSelecao({
    required this.id,
    required this.produtoId,
    required this.nome,
    this.precoAdicional = 0.0,
    this.quantidadeBaixa = 1.0,
  });

  factory OpcaoPerguntaSelecao.fromMap(Map<String, dynamic> map) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return OpcaoPerguntaSelecao(
      id: map['id']?.toString() ?? '',
      produtoId: map['produto_id']?.toString() ?? map['produtoId']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      precoAdicional: parseDouble(map['preco_adicional'] ?? map['precoAdicional']),
      quantidadeBaixa: parseDouble(map['quantidade_baixa'] ?? map['quantidadeBaixa'] ?? 1.0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'nome': nome,
      'preco_adicional': precoAdicional,
      'quantidade_baixa': quantidadeBaixa,
    };
  }
}

/// Modelo que representa uma pergunta de seleção dinâmica (Combo Interativo)
class PerguntaSelecao {
  final String id;
  final String titulo; // Ex: "Escolha a Bebida"
  final bool obrigatorio; // Se o cliente é obrigado a escolher
  final int minimo; // Quantidade mínima de seleção (geralmente 1)
  final int maximo; // Quantidade máxima de seleção (ex: 1 ou 2)
  final List<OpcaoPerguntaSelecao> opcoes;

  PerguntaSelecao({
    required this.id,
    required this.titulo,
    this.obrigatorio = true,
    this.minimo = 1,
    this.maximo = 1,
    required this.opcoes,
  });

  factory PerguntaSelecao.fromMap(Map<String, dynamic> map) {
    final rawOpcoes = map['opcoes'] ?? [];
    List<OpcaoPerguntaSelecao> opcoesList = [];
    if (rawOpcoes is List) {
      opcoesList = rawOpcoes.map((o) => OpcaoPerguntaSelecao.fromMap(Map<String, dynamic>.from(o))).toList();
    }

    return PerguntaSelecao(
      id: map['id']?.toString() ?? '',
      titulo: map['titulo']?.toString() ?? '',
      obrigatorio: map['obrigatorio'] == true || map['obrigatorio'] == 'true',
      minimo: int.tryParse(map['minimo']?.toString() ?? '1') ?? 1,
      maximo: int.tryParse(map['maximo']?.toString() ?? '1') ?? 1,
      opcoes: opcoesList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titulo': titulo,
      'obrigatorio': obrigatorio,
      'minimo': minimo,
      'maximo': maximo,
      'opcoes': opcoes.map((o) => o.toMap()).toList(),
    };
  }
}

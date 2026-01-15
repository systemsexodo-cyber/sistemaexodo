class Produto {
  final String id;
  final String? codigo; // Pode ser null para produtos antigos
  final String? codigoBarras; // Código de barras (EAN, UPC, etc)
  final String nome;
  final String? descricao;
  final String unidade;
  final String grupo; // Novo: Grupo/Categoria do produto
  final double preco;
  final double? precoCusto; // Preço de custo do produto
  final int estoque;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Campos de promoção
  final double? precoPromocional;
  final DateTime? promocaoInicio;
  final DateTime? promocaoFim;

  Produto({
    required this.id,
    this.codigo,
    this.codigoBarras,
    required this.nome,
    this.descricao,
    required this.unidade,
    required this.grupo,
    required this.preco,
    this.precoCusto,
    required this.estoque,
    required this.createdAt,
    required this.updatedAt,
    this.precoPromocional,
    this.promocaoInicio,
    this.promocaoFim,
  });

  // Verifica se a promoção está ativa agora
  bool get promocaoAtiva {
    if (precoPromocional == null ||
        promocaoInicio == null ||
        promocaoFim == null) {
      return false;
    }
    final agora = DateTime.now();
    return agora.isAfter(promocaoInicio!) && agora.isBefore(promocaoFim!);
  }

  // Retorna o preço atual (promocional se ativo, normal caso contrário)
  double get precoAtual => promocaoAtiva ? precoPromocional! : preco;

  // Calcula o percentual de desconto
  double get percentualDesconto {
    if (!promocaoAtiva || precoPromocional == null) return 0;
    return ((preco - precoPromocional!) / preco * 100);
  }

  // Calcula a margem de lucro em percentual
  double get margemLucroPercentual {
    if (precoCusto == null || precoCusto == 0) return 0;
    final lucro = preco - precoCusto!;
    return (lucro / precoCusto!) * 100;
  }

  // Calcula o lucro em valor (preço - custo)
  double get lucroValor {
    if (precoCusto == null) return 0;
    return preco - precoCusto!;
  }

  // Verifica se há lucro
  bool get temLucro {
    if (precoCusto == null) return true; // Se não tem custo, assume que tem lucro
    return preco > precoCusto!;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'codigoBarras': codigoBarras,
      'nome': nome,
      'descricao': descricao,
      'unidade': unidade,
      'grupo': grupo,
      'preco': preco,
      'precoCusto': precoCusto,
      'estoque': estoque,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'precoPromocional': precoPromocional,
      'promocaoInicio': promocaoInicio?.toIso8601String(),
      'promocaoFim': promocaoFim?.toIso8601String(),
    };
  }

  factory Produto.fromMap(Map<String, dynamic> map) {
    return Produto(
      id: map['id'] as String,
      codigo: map['codigo'] as String?,
      codigoBarras: map['codigoBarras'] as String?,
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      unidade: map['unidade'] as String? ?? '',
      grupo: map['grupo'] as String? ?? 'Sem Grupo',
      preco: (map['preco'] as num).toDouble(),
      precoCusto: map['precoCusto'] != null
          ? (map['precoCusto'] as num).toDouble()
          : null,
      estoque: map['estoque'] as int,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      precoPromocional: map['precoPromocional'] != null
          ? (map['precoPromocional'] as num).toDouble()
          : null,
      promocaoInicio: map['promocaoInicio'] != null
          ? DateTime.parse(map['promocaoInicio'] as String)
          : null,
      promocaoFim: map['promocaoFim'] != null
          ? DateTime.parse(map['promocaoFim'] as String)
          : null,
    );
  }

  /// Cria uma cópia do produto com campos atualizados
  Produto copyWith({
    String? id,
    String? codigo,
    String? codigoBarras,
    String? nome,
    String? descricao,
    String? unidade,
    String? grupo,
    double? preco,
    double? precoCusto,
    int? estoque,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? precoPromocional,
    DateTime? promocaoInicio,
    DateTime? promocaoFim,
  }) {
    return Produto(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      unidade: unidade ?? this.unidade,
      grupo: grupo ?? this.grupo,
      preco: preco ?? this.preco,
      precoCusto: precoCusto ?? this.precoCusto,
      estoque: estoque ?? this.estoque,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      precoPromocional: precoPromocional ?? this.precoPromocional,
      promocaoInicio: promocaoInicio ?? this.promocaoInicio,
      promocaoFim: promocaoFim ?? this.promocaoFim,
    );
  }
}

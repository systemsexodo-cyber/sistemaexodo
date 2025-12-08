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
  
  // Códigos do fornecedor - mapeamento entre código do fornecedor e código interno
  final List<String> codigosFornecedor; // Lista de códigos que o fornecedor usa para este produto

  // Campos de impostos e tributação
  final String? ncm; // Nomenclatura Comum do Mercosul (8 dígitos)
  final double? icmsAliquota; // Alíquota ICMS (%)
  final String? icmsCst; // Código de Situação Tributária ICMS
  final double? ipiAliquota; // Alíquota IPI (%)
  final String? ipiCst; // Código de Situação Tributária IPI
  final double? pisAliquota; // Alíquota PIS (%)
  final String? pisCst; // Código de Situação Tributária PIS
  final double? cofinsAliquota; // Alíquota COFINS (%)
  final String? cofinsCst; // Código de Situação Tributária COFINS
  final double? issAliquota; // Alíquota ISS (%) - para serviços
  final String? origem; // Origem da mercadoria (0-Nacional, 1-Estrangeira, etc)
  final String? cfop; // Código Fiscal de Operações e Prestações
  final String? cest; // Código Especificador da Substituição Tributária (quando aplicável)
  
  // Campos do Simples Nacional
  final String? csosn; // Código de Situação da Operação - Simples Nacional
  final double? simplesNacionalAliquota; // Alíquota do Simples Nacional (%)

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
    List<String>? codigosFornecedor,
    this.ncm,
    this.icmsAliquota,
    this.icmsCst,
    this.ipiAliquota,
    this.ipiCst,
    this.pisAliquota,
    this.pisCst,
    this.cofinsAliquota,
    this.cofinsCst,
    this.issAliquota,
    this.origem,
    this.cfop,
    this.cest,
    this.csosn,
    this.simplesNacionalAliquota,
  }) : codigosFornecedor = codigosFornecedor ?? [];

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
      'codigosFornecedor': codigosFornecedor,
      'ncm': ncm,
      'icmsAliquota': icmsAliquota,
      'icmsCst': icmsCst,
      'ipiAliquota': ipiAliquota,
      'ipiCst': ipiCst,
      'pisAliquota': pisAliquota,
      'pisCst': pisCst,
      'cofinsAliquota': cofinsAliquota,
      'cofinsCst': cofinsCst,
      'issAliquota': issAliquota,
      'origem': origem,
      'cfop': cfop,
      'cest': cest,
      'csosn': csosn,
      'simplesNacionalAliquota': simplesNacionalAliquota,
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
      codigosFornecedor: map['codigosFornecedor'] != null
          ? List<String>.from(map['codigosFornecedor'] as List)
          : [],
      ncm: map['ncm'] as String?,
      icmsAliquota: map['icmsAliquota'] != null
          ? (map['icmsAliquota'] as num).toDouble()
          : null,
      icmsCst: map['icmsCst'] as String?,
      ipiAliquota: map['ipiAliquota'] != null
          ? (map['ipiAliquota'] as num).toDouble()
          : null,
      ipiCst: map['ipiCst'] as String?,
      pisAliquota: map['pisAliquota'] != null
          ? (map['pisAliquota'] as num).toDouble()
          : null,
      pisCst: map['pisCst'] as String?,
      cofinsAliquota: map['cofinsAliquota'] != null
          ? (map['cofinsAliquota'] as num).toDouble()
          : null,
      cofinsCst: map['cofinsCst'] as String?,
      issAliquota: map['issAliquota'] != null
          ? (map['issAliquota'] as num).toDouble()
          : null,
      origem: map['origem'] as String?,
      cfop: map['cfop'] as String?,
      cest: map['cest'] as String?,
      csosn: map['csosn'] as String?,
      simplesNacionalAliquota: map['simplesNacionalAliquota'] != null
          ? (map['simplesNacionalAliquota'] as num).toDouble()
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
    List<String>? codigosFornecedor,
    String? ncm,
    double? icmsAliquota,
    String? icmsCst,
    double? ipiAliquota,
    String? ipiCst,
    double? pisAliquota,
    String? pisCst,
    double? cofinsAliquota,
    String? cofinsCst,
    double? issAliquota,
    String? origem,
    String? cfop,
    String? cest,
    String? csosn,
    double? simplesNacionalAliquota,
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
      codigosFornecedor: codigosFornecedor ?? this.codigosFornecedor,
      ncm: ncm ?? this.ncm,
      icmsAliquota: icmsAliquota ?? this.icmsAliquota,
      icmsCst: icmsCst ?? this.icmsCst,
      ipiAliquota: ipiAliquota ?? this.ipiAliquota,
      ipiCst: ipiCst ?? this.ipiCst,
      pisAliquota: pisAliquota ?? this.pisAliquota,
      pisCst: pisCst ?? this.pisCst,
      cofinsAliquota: cofinsAliquota ?? this.cofinsAliquota,
      cofinsCst: cofinsCst ?? this.cofinsCst,
      issAliquota: issAliquota ?? this.issAliquota,
      origem: origem ?? this.origem,
      cfop: cfop ?? this.cfop,
      cest: cest ?? this.cest,
      csosn: csosn ?? this.csosn,
      simplesNacionalAliquota: simplesNacionalAliquota ?? this.simplesNacionalAliquota,
    );
  }
  
  /// Verifica se um código do fornecedor corresponde a este produto
  bool temCodigoFornecedor(String codigoFornecedor) {
    return codigosFornecedor.contains(codigoFornecedor);
  }
  
  /// Adiciona um código do fornecedor (sem duplicatas)
  Produto adicionarCodigoFornecedor(String codigoFornecedor) {
    if (codigosFornecedor.contains(codigoFornecedor)) {
      return this; // Já existe, retorna o mesmo produto
    }
    return copyWith(
      codigosFornecedor: [...codigosFornecedor, codigoFornecedor],
      updatedAt: DateTime.now(),
    );
  }
}

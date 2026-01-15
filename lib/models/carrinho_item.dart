import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';

class CarrinhoItem {
  final String id;
  final String tipo; // 'produto' ou 'servico'
  final String itemId; // ID do produto ou serviço
  final String nome;
  final String? descricao;
  final double preco;
  final int quantidade;
  final DateTime adicionadoEm;

  // Campos específicos de produto
  final String? unidade;
  final int? estoqueDisponivel;

  // Campos específicos de serviço
  final double? valorAdicional;
  final String? descricaoAdicional;
  
  // Variações selecionadas do produto (tamanho, cor, sabor, etc)
  final List<VariacaoProduto>? variacoesSelecionadas;
  
  // Peso do produto em gramas
  final int? pesoGramas;

  CarrinhoItem({
    required this.id,
    required this.tipo,
    required this.itemId,
    required this.nome,
    this.descricao,
    required this.preco,
    this.quantidade = 1,
    DateTime? adicionadoEm,
    this.unidade,
    this.estoqueDisponivel,
    this.valorAdicional,
    this.descricaoAdicional,
    this.variacoesSelecionadas,
    this.pesoGramas,
  }) : adicionadoEm = adicionadoEm ?? DateTime.now();

  // Cria um item do carrinho a partir de um produto
  factory CarrinhoItem.fromProduto(
    Produto produto, {
    int quantidade = 1,
    List<VariacaoProduto>? variacoesSelecionadas,
  }) {
    // Calcula o preço considerando as variações
    double precoFinal = produto.precoComVariacao(variacoesSelecionadas);
    
    // Calcula o estoque considerando as variações
    int? estoqueFinal = produto.estoqueVariacao(variacoesSelecionadas);
    
    // Monta o nome com as variações
    String nomeCompleto = produto.nome;
    if (variacoesSelecionadas != null && variacoesSelecionadas.isNotEmpty) {
      final variacoesStr = variacoesSelecionadas
          .map((v) => v.descricao)
          .join(', ');
      nomeCompleto = '$nomeCompleto ($variacoesStr)';
    }
    
    return CarrinhoItem(
      id: 'produto_${produto.id}_${variacoesSelecionadas?.map((v) => v.id).join('_') ?? ''}_${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'produto',
      itemId: produto.id,
      nome: nomeCompleto,
      descricao: produto.descricao,
      preco: precoFinal,
      quantidade: quantidade,
      unidade: produto.unidade,
      estoqueDisponivel: estoqueFinal,
      variacoesSelecionadas: variacoesSelecionadas,
      pesoGramas: produto.pesoGramas,
    );
  }

  // Cria um item do carrinho a partir de um serviço
  factory CarrinhoItem.fromServico(Servico servico) {
    return CarrinhoItem(
      id: 'servico_${servico.id}_${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'servico',
      itemId: servico.id,
      nome: servico.nome,
      descricao: servico.descricao,
      preco: servico.precoTotal,
      quantidade: 1, // Serviços geralmente são 1
      valorAdicional: servico.valorAdicional,
      descricaoAdicional: servico.descricaoAdicional,
    );
  }

  // Calcula o subtotal do item
  double get subtotal => preco * quantidade;

  // Verifica se é um produto
  bool get isProduto => tipo == 'produto';

  // Verifica se é um serviço
  bool get isServico => tipo == 'servico';

  // Verifica se tem estoque disponível (apenas para produtos)
  bool get temEstoque {
    if (isProduto && estoqueDisponivel != null) {
      return estoqueDisponivel! >= quantidade;
    }
    return true; // Serviços sempre têm "estoque"
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'itemId': itemId,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
      'quantidade': quantidade,
      'adicionadoEm': adicionadoEm.toIso8601String(),
      'unidade': unidade,
      'estoqueDisponivel': estoqueDisponivel,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'variacoesSelecionadas': variacoesSelecionadas?.map((v) => v.toMap()).toList(),
      'pesoGramas': pesoGramas,
    };
  }

  factory CarrinhoItem.fromMap(Map<String, dynamic> map) {
    return CarrinhoItem(
      id: map['id'] as String,
      tipo: map['tipo'] as String,
      itemId: map['itemId'] as String,
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      preco: (map['preco'] ?? 0.0).toDouble(),
      quantidade: map['quantidade'] ?? 1,
      adicionadoEm: map['adicionadoEm'] != null
          ? DateTime.parse(map['adicionadoEm'] as String)
          : DateTime.now(),
      unidade: map['unidade'] as String?,
      estoqueDisponivel: map['estoqueDisponivel'] as int?,
      valorAdicional: map['valorAdicional'] != null
          ? (map['valorAdicional'] as num).toDouble()
          : null,
      descricaoAdicional: map['descricaoAdicional'] as String?,
      variacoesSelecionadas: map['variacoesSelecionadas'] != null
          ? (map['variacoesSelecionadas'] as List)
              .map((v) => VariacaoProduto.fromMap(v as Map<String, dynamic>))
              .toList()
          : null,
      pesoGramas: map['pesoGramas'] as int?,
    );
  }

  CarrinhoItem copyWith({
    String? id,
    String? tipo,
    String? itemId,
    String? nome,
    String? descricao,
    double? preco,
    int? quantidade,
    DateTime? adicionadoEm,
    String? unidade,
    int? estoqueDisponivel,
    double? valorAdicional,
    String? descricaoAdicional,
    List<VariacaoProduto>? variacoesSelecionadas,
    int? pesoGramas,
  }) {
    return CarrinhoItem(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      itemId: itemId ?? this.itemId,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      quantidade: quantidade ?? this.quantidade,
      adicionadoEm: adicionadoEm ?? this.adicionadoEm,
      unidade: unidade ?? this.unidade,
      estoqueDisponivel: estoqueDisponivel ?? this.estoqueDisponivel,
      valorAdicional: valorAdicional ?? this.valorAdicional,
      descricaoAdicional: descricaoAdicional ?? this.descricaoAdicional,
      variacoesSelecionadas: variacoesSelecionadas ?? this.variacoesSelecionadas,
      pesoGramas: pesoGramas ?? this.pesoGramas,
    );
  }
}







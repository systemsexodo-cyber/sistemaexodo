import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

/// Item de uma venda de balcão
class ItemVendaBalcao {
  final String id;
  final String nome;
  final double precoUnitario;
  final double quantidade;
  final bool isServico;
  final double quantidadeDevolvida; // Quantidade que foi devolvida
  final double quantidadeTrocada; // Quantidade que foi trocada por outro produto
  final String? trocadoPor; // ID do produto que substituiu este em uma troca
  final String? fornecedorNome; // Fornecedor do produto no momento da venda
  final String? observacao;
  final double? precoOriginal; // Preço de tabela/cadastro antes de qualquer alteração no PDV
  final double? precoSemPromocao; // Preço base ANTES das promoções (para exibir o desconto no cupom)
  final double? precoTabela; // Preço de tabela SEM o desconto do perfil de preços (para exibir o desconto no cupom/NFC-e)
  final List<AdicionalProduto> adicionais;
  final List<OpcaoPerguntaSelecao> opcoesCombo;
  final bool baixaProporcional; // true = baixa pela conversão do saco; false = baixa a quantidade inteira no ingrediente
  // Forma de venda escolhida no PDV (unidade/caixa/pacote/saco) e sua baixa
  final String? unidadeVenda;
  final double? quantidadeBaixa;

  ItemVendaBalcao({
    required this.id,
    required this.nome,
    required this.precoUnitario,
    required this.quantidade,
    this.isServico = false,
    this.quantidadeDevolvida = 0,
    this.quantidadeTrocada = 0,
    this.trocadoPor,
    this.fornecedorNome,
    this.observacao,
    this.precoOriginal,
    this.precoSemPromocao,
    this.precoTabela,
    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
    this.baixaProporcional = true,
    this.unidadeVenda,
    this.quantidadeBaixa,
  }) : adicionais = adicionais ?? [],
       opcoesCombo = opcoesCombo ?? [];

  /// Verifica se o preço do item foi alterado no momento da venda
  bool get tevePrecoAlterado => precoOriginal != null && (precoUnitario - precoOriginal!).abs() > 0.001;
  
  /// Verifica se foi vendido por um valor menor que o cadastrado
  bool get foiVendidoMenor => tevePrecoAlterado && precoUnitario < precoOriginal!;
  
  /// Verifica se foi vendido por um valor maior que o cadastrado
  bool get foiVendidoMaior => tevePrecoAlterado && precoUnitario > precoOriginal!;
  
  /// Diferença de valor em R$ (positivo = acréscimo, negativo = desconto)
  double get diferencaPreco => precoOriginal != null ? (precoUnitario - precoOriginal!) : 0.0;

  /// Desconto (R\$) do perfil de preços por unidade (preço de tabela − preço
  /// vendido, excluindo a parcela promocional já exibida separadamente).
  /// Só é considerado desconto quando o preço vendido é MENOR que o de tabela.
  double get descontoTabelaUnitario {
    final baseComparada = precoSemPromocao ?? precoUnitario;
    if (precoTabela == null || precoTabela! <= baseComparada + 0.001) return 0.0;
    return precoTabela! - baseComparada;
  }

  /// Percentual do desconto promocional aplicado no item (null se não houver).
  double? get descontoPromocionalPercent {
    if (precoSemPromocao == null || precoSemPromocao! <= precoUnitario + 0.001) {
      return null;
    }
    return (precoSemPromocao! - precoUnitario) / precoSemPromocao! * 100;
  }

  /// Valor (R\$) do desconto promocional aplicado no item (null se não houver).
  double? get descontoPromocionalValor {
    final pct = descontoPromocionalPercent;
    return pct == null ? null : precoSemPromocao! - precoUnitario;
  }

  /// Quantidade efetiva (descontando devoluções e trocas)
  double get quantidadeEfetiva =>
      quantidade - quantidadeDevolvida - quantidadeTrocada;

  /// Verifica se o item foi parcialmente devolvido/trocado
  bool get foiParcialmenteDevolvido =>
      quantidadeDevolvida > 0 || quantidadeTrocada > 0;

  /// Verifica se o item foi totalmente devolvido/trocado
  bool get foiTotalmenteDevolvido => quantidadeEfetiva <= 0;

  double get subtotal {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (precoUnitario + totalAdicionais + totalCombo) * quantidade;
  }

  /// Subtotal efetivo (descontando devoluções)
  double get subtotalEfetivo {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (precoUnitario + totalAdicionais + totalCombo) * quantidadeEfetiva;
  }

  factory ItemVendaBalcao.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }
    
    final get = (String c, String s) => map[c] ?? map[s];
    
    return ItemVendaBalcao(
      id: map['id']?.toString() ?? '',
      nome: map['nome'] ?? '',
      precoUnitario: parseDouble(get('precoUnitario', 'preco_unitario')) ?? 0.0,
      quantidade: parseDouble(get('quantidade', 'quantidade')) ?? 1.0,
      isServico: get('isServico', 'is_servico') ?? false,
      quantidadeDevolvida: parseDouble(get('quantidadeDevolvida', 'quantidade_devolvida')) ?? 0.0,
      quantidadeTrocada: parseDouble(get('quantidadeTrocada', 'quantidade_trocada')) ?? 0.0,
      trocadoPor: get('trocadoPor', 'trocado_por'),
      fornecedorNome: get('fornecedorNome', 'fornecedor_nome'),
      observacao: map['observacao'],
      precoOriginal: parseDouble(get('precoOriginal', 'preco_original')),
      precoSemPromocao: parseDouble(get('precoSemPromocao', 'preco_sem_promocao')),
      precoTabela: parseDouble(get('precoTabela', 'preco_tabela')),
      adicionais: (getList('adicionais', 'adicionais', map) as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      opcoesCombo: (getList('opcoesCombo', 'opcoes_combo', map) as List<dynamic>?)
          ?.map((o) => OpcaoPerguntaSelecao.fromMap(o as Map<String, dynamic>))
          .toList() ?? [],
      baixaProporcional: (get('baixaProporcional', 'baixa_proporcional') ?? true) == true,
      unidadeVenda: get('unidadeVenda', 'unidade_venda'),
      quantidadeBaixa: parseDouble(get('quantidadeBaixa', 'quantidade_baixa')),
    );
  }

  static dynamic getList(String c, String s, Map map) => map[c] ?? map[s];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'preco_unitario': precoUnitario,
      'quantidade': quantidade,
      'is_servico': isServico,
      'quantidade_devolvida': quantidadeDevolvida,
      'quantidade_trocada': quantidadeTrocada,
      'trocado_por': trocadoPor,
      'fornecedor_nome': fornecedorNome,
      'observacao': observacao,
      'preco_original': precoOriginal,
      'preco_sem_promocao': precoSemPromocao,
      'preco_tabela': precoTabela,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'opcoes_combo': opcoesCombo.map((o) => o.toMap()).toList(),
      'baixa_proporcional': baixaProporcional,
      'unidade_venda': unidadeVenda,
      'quantidade_baixa': quantidadeBaixa,
    };
  }

  /// Cria uma cópia do item com campos atualizados
  ItemVendaBalcao copyWith({
    String? id,
    String? nome,
    double? precoUnitario,
    double? quantidade,
    bool? isServico,
    double? quantidadeDevolvida,
    double? quantidadeTrocada,
    String? trocadoPor,
    String? fornecedorNome,
    String? observacao,
    double? precoOriginal,
    double? precoSemPromocao,
    double? precoTabela,
    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
  }) {
    return ItemVendaBalcao(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      precoUnitario: precoUnitario ?? this.precoUnitario,
      quantidade: quantidade ?? this.quantidade,
      isServico: isServico ?? this.isServico,
      quantidadeDevolvida: quantidadeDevolvida ?? this.quantidadeDevolvida,
      quantidadeTrocada: quantidadeTrocada ?? this.quantidadeTrocada,
      trocadoPor: trocadoPor ?? this.trocadoPor,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      observacao: observacao ?? this.observacao,
      precoOriginal: precoOriginal ?? this.precoOriginal,
      precoSemPromocao: precoSemPromocao ?? this.precoSemPromocao,
      precoTabela: precoTabela ?? this.precoTabela,
      adicionais: adicionais ?? this.adicionais,
      opcoesCombo: opcoesCombo ?? this.opcoesCombo,
    );
  }
}

/// Venda realizada no balcão (PDV)
class VendaBalcao {
  final String id;
  final String numero; // Número sequencial da venda (VND-0001, VND-0002, etc.)
  final DateTime dataVenda;
  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? clienteCpfCnpj;
  final List<ItemVendaBalcao> itens;
  final TipoPagamento tipoPagamento; // Forma principal (primeira) — mantida por compatibilidade
  final List<PagamentoPedido> pagamentos; // Todas as formas de pagamento (split/parcial)
  final double valorTotal;
  final double? valorRecebido;
  final double? troco;
  final String? operador; // Nome do operador
  final String? vendedorId; // ID do vendedor para comissão
  final String? vendedorNome; // Nome do vendedor para comissão
  final String? origem; // Origem detalhada (Mesa/Comanda, Venda Direta, etc)
  final String? observacoes;
  final bool cancelado; // Indica se a venda foi cancelada
  final DeliveryInfo? deliveryInfo; // Informações de entrega
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senha; // Senha de atendimento/fila do pedido

  VendaBalcao({
    required this.id,
    required this.numero,
    required this.dataVenda,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    this.clienteCpfCnpj,
    required this.itens,
    required this.tipoPagamento,
    List<PagamentoPedido>? pagamentos,
    required this.valorTotal,
    this.valorRecebido,
    this.troco,
    this.operador,
    this.vendedorId,
    this.vendedorNome,
    this.origem,
    this.observacoes,
    this.cancelado = false,
    this.deliveryInfo,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.senha,
  })  : pagamentos = pagamentos ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  // Quantidade total de itens
  double get quantidadeItens =>
      itens.fold(0.0, (sum, item) => sum + item.quantidade);

  // Verifica se a venda está cancelada
  bool get isCancelada => cancelado;

  factory VendaBalcao.fromMap(Map<String, dynamic> map) {
    // Helpers para suportar camelCase (localStorage) e snake_case (Supabase)
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }
    String? getStr(String camel, String snake) => get<String>(camel, snake);
    bool? getBool(String camel, String snake) => get<bool>(camel, snake);
    num? getNum(String camel, String snake) {
      final val = get<dynamic>(camel, snake);
      if (val == null) return null;
      if (val is num) return val;
      if (val is String) return num.tryParse(val);
      return null;
    }
    List? getList(String camel, String snake) => get<List>(camel, snake);
    Map? getMap(String camel, String snake) => get<Map>(camel, snake);

    final tipoPagamentoStr = getStr('tipoPagamento', 'tipo_pagamento') ?? 'dinheiro';

    final createdDate = DateParser.parse(map['created_at'] ?? map['createdAt']);
    final updatedDateRaw = map['updated_at'] ?? map['updatedAt'];

    return VendaBalcao(
      id: map['id']?.toString() ?? '',
      numero: map['numero'] ?? '',
      dataVenda: DateParser.parse(map['data_venda'] ?? map['dataVenda']),
      clienteId: getStr('clienteId', 'cliente_id'),
      clienteNome: getStr('clienteNome', 'cliente_nome'),
      clienteTelefone: getStr('clienteTelefone', 'cliente_telefone'),
      clienteCpfCnpj: getStr('clienteCpfCnpj', 'cliente_cpf_cnpj'),
      itens: (getList('itens', 'itens') ?? [])
          .map((i) => ItemVendaBalcao.fromMap(i as Map<String, dynamic>))
          .toList(),
      tipoPagamento: TipoPagamento.values.firstWhere(
        (t) => t.name == tipoPagamentoStr,
        orElse: () => TipoPagamento.dinheiro,
      ),
      pagamentos: (getList('pagamentos', 'pagamentos') ?? [])
          .map((p) => PagamentoPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      valorTotal: (getNum('valorTotal', 'valor_total') ?? 0).toDouble(),
      valorRecebido: getNum('valorRecebido', 'valor_recebido')?.toDouble(),
      troco: getNum('troco', 'troco')?.toDouble(),
      operador: getStr('operador', 'operador'),
      vendedorId: getStr('vendedorId', 'vendedor_id'),
      vendedorNome: getStr('vendedorNome', 'vendedor_nome'),
      origem: getStr('origem', 'origem'),
      observacoes: getStr('observacoes', 'observacoes'),
      cancelado: getBool('cancelado', 'cancelado') ?? false,
      deliveryInfo: getMap('deliveryInfo', 'delivery_info') != null
          ? DeliveryInfo.fromMap(getMap('deliveryInfo', 'delivery_info')! as Map<String, dynamic>)
          : null,
      createdAt: createdDate,
      updatedAt: updatedDateRaw != null ? DateParser.parse(updatedDateRaw) : createdDate,
      senha: getStr('senha', 'senha'),
    );
  }

  Map<String, dynamic> toMap() {
    // Serializar datas em UTC (sufixo Z) para evitar ambiguidade: o Postgres
    // interpreta string sem fuso como UTC e o DateParser como hora LOCAL,
    // deslocando vendas/caixas em -3h. Com Z, ambos usam o mesmo instante.
    String iso(DateTime d) => d.toUtc().toIso8601String();
    return {
      'id': id,
      'numero': numero,
      'data_venda': iso(dataVenda),
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'cliente_telefone': clienteTelefone,
      'cliente_cpf_cnpj': clienteCpfCnpj,
      'itens': itens.map((i) => i.toMap()).toList(),
      'tipo_pagamento': tipoPagamento.name,
      'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
      'valor_total': valorTotal,
      'valor_recebido': valorRecebido,
      'troco': troco,
      'operador': operador,
      'vendedor_id': vendedorId,
      'vendedor_nome': vendedorNome,
      'origem': origem,
      'observacoes': observacoes,
      'cancelado': cancelado,
      'delivery_info': deliveryInfo?.toMap(),
      'created_at': iso(createdAt),
      'updated_at': iso(updatedAt),
      'senha': senha,
    };
  }

  /// Cria uma cópia da venda com campos atualizados
  VendaBalcao copyWith({
    String? id,
    String? numero,
    DateTime? dataVenda,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteCpfCnpj,
    List<ItemVendaBalcao>? itens,
    TipoPagamento? tipoPagamento,
    List<PagamentoPedido>? pagamentos,
    double? valorTotal,
    double? valorRecebido,
    double? troco,
    String? operador,
    String? vendedorId,
    String? vendedorNome,
    String? origem,
    String? observacoes,
    bool? cancelado,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? senha,
  }) {
    return VendaBalcao(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      dataVenda: dataVenda ?? this.dataVenda,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteCpfCnpj: clienteCpfCnpj ?? this.clienteCpfCnpj,
      itens: itens ?? this.itens,
      tipoPagamento: tipoPagamento ?? this.tipoPagamento,
      pagamentos: pagamentos ?? this.pagamentos,
      valorTotal: valorTotal ?? this.valorTotal,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      troco: troco ?? this.troco,
      operador: operador ?? this.operador,
      vendedorId: vendedorId ?? this.vendedorId,
      vendedorNome: vendedorNome ?? this.vendedorNome,
      origem: origem ?? this.origem,
      observacoes: observacoes ?? this.observacoes,
      cancelado: cancelado ?? this.cancelado,
      deliveryInfo: deliveryInfo ?? this.deliveryInfo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      senha: senha ?? this.senha,
    );
  }
}

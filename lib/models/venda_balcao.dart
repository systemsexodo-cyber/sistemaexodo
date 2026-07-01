import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
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
  final List<AdicionalProduto> adicionais;

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
    List<AdicionalProduto>? adicionais,
  }) : adicionais = adicionais ?? [];

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
    return (precoUnitario + totalAdicionais) * quantidade;
  }

  /// Subtotal efetivo (descontando devoluções)
  double get subtotalEfetivo {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return (precoUnitario + totalAdicionais) * quantidadeEfetiva;
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
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      precoUnitario: parseDouble(get('precoUnitario', 'preco_unitario')) ?? 0.0,
      quantidade: parseDouble(get('quantidade', 'quantidade')) ?? 1.0,
      isServico: get('isServico', 'is_servico') ?? false,
      quantidadeDevolvida: parseDouble(get('quantidadeDevolvida', 'quantidade_devolvida')) ?? 0.0,
      quantidadeTrocada: parseDouble(get('quantidadeTrocada', 'quantidade_trocada')) ?? 0.0,
      trocadoPor: get('trocadoPor', 'trocado_por'),
      fornecedorNome: get('fornecedorNome', 'fornecedor_nome'),
      observacao: map['observacao'],
      adicionais: (getList('adicionais', 'adicionais', map) as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
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
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
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
    List<AdicionalProduto>? adicionais,
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
      adicionais: adicionais ?? this.adicionais,
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
  final TipoPagamento tipoPagamento;
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
  }) : createdAt = createdAt ?? DateTime.now();

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

    return VendaBalcao(
      id: map['id'] ?? '',
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
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'data_venda': dataVenda.toIso8601String(),
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'cliente_telefone': clienteTelefone,
      'cliente_cpf_cnpj': clienteCpfCnpj,
      'itens': itens.map((i) => i.toMap()).toList(),
      'tipo_pagamento': tipoPagamento.name,
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
      'created_at': createdAt.toIso8601String(),
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
    );
  }
}

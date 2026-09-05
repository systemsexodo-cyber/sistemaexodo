import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/item_material.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

class Pedido {
  final String id;
  final String numero; // Número sequencial do pedido (PED-0001, PED-0002, etc.)
  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? clienteEndereco;
  final String? clienteCpfCnpj;
  final String? vendedorId; // ID do vendedor (funcionário)
  final String? vendedorNome; // Nome do vendedor
  final String? operador; // Responsável pela venda (quem atendeu no PDV/caixa)
  final String? linkVendedorId; // ID do link usado
  final String? linkVendedorCodigo; // Código do link (ex: ABC123)
  final bool origemEcommerce; // Indica se o pedido veio do e-commerce (loja pública)
  final String? origem; // Origem detalhada do pedido (Mesa/Comanda, Venda Direta, etc)
  final DateTime dataPedido;
  final String status; // Pendente, Em Andamento, Concluído, Cancelado
  final double total;
  final double descontoTotal;
  final double acrescimoTotal;
  final String? observacoes;
  final List<ItemPedido> produtos;
  final List<ItemServico> servicos;
  final List<PagamentoPedido> pagamentos; // Formas de pagamento do pedido
  final List<ItemMaterial> materiaisConsumidos; // Materiais consumidos nos serviços (histórico)
  final DeliveryInfo? deliveryInfo; // Informações de entrega
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senha; // Senha de atendimento/fila do pedido

  Pedido({
    required this.id,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    this.clienteEndereco,
    this.clienteCpfCnpj,
    this.vendedorId,
    this.vendedorNome,
    this.operador,
    this.linkVendedorId,
    this.linkVendedorCodigo,
    this.origemEcommerce = false, // Por padrão, não é do e-commerce
    this.origem,
    DateTime? dataPedido,
    this.status = 'Pendente',
    this.total = 0.0,
    this.descontoTotal = 0.0,
    this.acrescimoTotal = 0.0,
    this.observacoes,
    required this.produtos,
    required this.servicos,
    List<PagamentoPedido>? pagamentos,
    List<ItemMaterial>? materiaisConsumidos,
    this.deliveryInfo,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.senha,
  }) : dataPedido = dataPedido ?? DateTime.now(),
       pagamentos = pagamentos ?? [],
       materiaisConsumidos = materiaisConsumidos ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Calcula o total dos produtos
  double get totalProdutos =>
      produtos.fold(0.0, (sum, item) => sum + (item.preco * item.quantidade));

  // Calcula o total dos serviços (incluindo taxa taxi dog separada)
  double get totalServicos {
    double total = servicos.fold(0.0, (sum, item) => sum + item.valor + item.valorAdicional);
    // Adicionar taxas de taxi dog separadamente
    for (final servico in servicos) {
      if (servico.tipoEntrega == 'Taxi Dog' && servico.valorTaxiDog != null && servico.valorTaxiDog! > 0) {
        total += servico.valorTaxiDog!;
      }
    }
    return total;
  }

  // Calcula o total geral
  double get totalGeral {
    final subtotal = totalProdutos + totalServicos + (deliveryInfo?.taxaEntrega ?? 0.0);
    
    // Sum discounts and additions from payments
    double descontoPagamentos = pagamentos.fold(0.0, (sum, pag) => sum + (pag.desconto ?? 0.0));
    double acrescimoPagamentos = pagamentos.fold(0.0, (sum, pag) => sum + (pag.acrescimo ?? 0.0));
    
    final totalComDesconto = subtotal - descontoTotal + acrescimoTotal - descontoPagamentos + acrescimoPagamentos;

    // Se não há itens mas o total foi definido manualmente (ex: vindo de venda balcão compacta), usar o total.
    // Isso evita que vendas salvas sejam marcadas como "pagas" no PDV por terem total geral calculado como 0.
    if (subtotal < 0.01 && total > 0.01) {
      return total - descontoTotal + acrescimoTotal - descontoPagamentos + acrescimoPagamentos;
    }
    return totalComDesconto;
  }

  // Quantidade total de itens
  double get quantidadeItens =>
      produtos.fold(0.0, (sum, item) => sum + item.quantidade) + servicos.length;

  // Total de pagamentos já lançados
  double get totalPagamentos =>
      pagamentos.fold(0.0, (sum, pag) => sum + pag.valor);

  // Total recebido (confirmado no PDV)
  double get totalRecebido => pagamentos
      .where((p) => p.recebido)
      .fold(0.0, (sum, pag) => sum + pag.valor);

  // Valor pendente (ainda não recebido)
  double get valorPendente => totalPagamentos - totalRecebido;

  // Valor restante a lançar
  double get valorRestante => totalGeral - totalPagamentos;

  // Verifica se o pedido está totalmente pago (pagamentos lançados)
  bool get pagamentoCompleto => valorRestante <= 0;

  // Verifica se todos os pagamentos foram recebidos
  bool get totalmenteRecebido => totalRecebido >= totalGeral;

  // Quantidade de parcelas pendentes
  int get parcelasPendentes => pagamentos.where((p) => !p.recebido).length;

  // Quantidade de parcelas pagas
  int get parcelasPagas => pagamentos.where((p) => p.recebido).length;

  // Total de parcelas
  int get totalParcelas => pagamentos.length;

  // Verifica se tem parcelamento
  bool get temParcelamento => pagamentos.any((p) => p.isParcela);

  // Próxima parcela a vencer (não paga)
  PagamentoPedido? get proximaParcela {
    final pendentes = pagamentos
        .where((p) => !p.recebido && p.dataVencimento != null)
        .toList();
    if (pendentes.isEmpty) return null;
    pendentes.sort((a, b) => a.dataVencimento!.compareTo(b.dataVencimento!));
    return pendentes.first;
  }

  // Parcelas vencidas
  List<PagamentoPedido> get parcelasVencidas =>
      pagamentos.where((p) => p.isVencida).toList();

  // Tem parcelas vencidas?
  bool get temParcelasVencidas => parcelasVencidas.isNotEmpty;

  // Status do parcelamento
  String get statusParcelamento {
    if (pagamentos.isEmpty) return 'Sem pagamento';
    if (totalmenteRecebido) return 'Quitado';
    if (temParcelasVencidas) return 'Em atraso';
    if (parcelasPagas > 0) return 'Parcialmente pago';
    return 'Aguardando';
  }

  factory Pedido.fromMap(Map<String, dynamic> map) {
    // Helpers para suportar camelCase (localStorage) e snake_case (Supabase)
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }
    String? getStr(String camel, String snake) => get<String>(camel, snake);
    bool? getBool(String camel, String snake) => get<bool>(camel, snake);
    List? getList(String camel, String snake) => get<List>(camel, snake);
    Map? getMap(String camel, String snake) => get<Map>(camel, snake);

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    DateTime getDate(String camel, String snake, DateTime fallback) {
      final val = map[camel] ?? map[snake];
      if (val == null) return fallback;
      return DateParser.parse(val, defaultValue: fallback);
    }

    return Pedido(
      id: map['id']?.toString() ?? '',
      numero: map['numero'] ?? '',
      clienteId: getStr('clienteId', 'cliente_id'),
      clienteNome: getStr('clienteNome', 'cliente_nome'),
      clienteTelefone: getStr('clienteTelefone', 'cliente_telefone'),
      clienteEndereco: getStr('clienteEndereco', 'cliente_endereco'),
      clienteCpfCnpj: getStr('clienteCpfCnpj', 'cliente_cpf_cnpj'),
      vendedorId: getStr('vendedorId', 'vendedor_id'),
      vendedorNome: getStr('vendedorNome', 'vendedor_nome'),
      operador: getStr('operador', 'operador'),
      linkVendedorId: getStr('linkVendedorId', 'link_vendedor_id'),
      linkVendedorCodigo: getStr('linkVendedorCodigo', 'link_vendedor_codigo'),
      origemEcommerce: getBool('origemEcommerce', 'origem_ecommerce') ?? false, 
      origem: map['origem'],
      dataPedido: getDate('dataPedido', 'data_pedido', DateTime.now()),
      status: map['status'] ?? 'Pendente',
      total: parseDouble(map['total']) ?? 0.0,
      descontoTotal: parseDouble(map['descontoTotal']) ?? 0.0,
      acrescimoTotal: parseDouble(map['acrescimoTotal']) ?? 0.0,
      observacoes: map['observacoes'],
      produtos: (getList('produtos', 'produtos') ?? [])
          .map((p) => ItemPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      servicos: (getList('servicos', 'servicos') ?? [])
          .map((s) => ItemServico.fromMap(s as Map<String, dynamic>))
          .toList(),
      pagamentos: (getList('pagamentos', 'pagamentos') ?? [])
          .map((p) => PagamentoPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      materiaisConsumidos: (getList('materiaisConsumidos', 'materiais_consumidos') ?? [])
          .map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>))
          .toList(),
      deliveryInfo: getMap('deliveryInfo', 'delivery_info') != null
          ? DeliveryInfo.fromMap(getMap('deliveryInfo', 'delivery_info')! as Map<String, dynamic>)
          : null,
      createdAt: getDate('createdAt', 'created_at', DateTime.now()),
      updatedAt: getDate('updatedAt', 'updated_at', DateTime.now()),
      senha: getStr('senha', 'senha'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'cliente_telefone': clienteTelefone,
      'cliente_endereco': clienteEndereco,
      'cliente_cpf_cnpj': clienteCpfCnpj,
      'vendedor_id': vendedorId,
      'vendedor_nome': vendedorNome,
      'operador': operador,
      'link_vendedor_id': linkVendedorId,
      'link_vendedor_codigo': linkVendedorCodigo,
      'origem_ecommerce': origemEcommerce,
      'origem': origem,
      'data_pedido': dataPedido.toIso8601String(),
      'status': status,
      'total': total,
      'descontoTotal': descontoTotal,
      'acrescimoTotal': acrescimoTotal,
      'observacoes': observacoes,
      'produtos': produtos.map((p) => p.toMap()).toList(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
      'materiais_consumidos': materiaisConsumidos.map((m) => m.toMap()).toList(),
      'delivery_info': deliveryInfo?.toMap(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'senha': senha,
    };
  }

  // Cria uma cópia do pedido com novos valores
  Pedido copyWith({
    String? id,
    String? numero,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteEndereco,
    String? clienteCpfCnpj,
    String? vendedorId,
    String? vendedorNome,
    String? operador,
    String? linkVendedorId,
    String? linkVendedorCodigo,
    bool? origemEcommerce,
    String? origem,
    DateTime? dataPedido,
    String? status,
    double? total,
    double? descontoTotal,
    double? acrescimoTotal,
    String? observacoes,
    List<ItemPedido>? produtos,
    List<ItemServico>? servicos,
    List<PagamentoPedido>? pagamentos,
    List<ItemMaterial>? materiaisConsumidos,
    DeliveryInfo? deliveryInfo,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? senha,
  }) {
    return Pedido(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteEndereco: clienteEndereco ?? this.clienteEndereco,
      clienteCpfCnpj: clienteCpfCnpj ?? this.clienteCpfCnpj,
      vendedorId: vendedorId ?? this.vendedorId,
      vendedorNome: vendedorNome ?? this.vendedorNome,
      operador: operador ?? this.operador,
      linkVendedorId: linkVendedorId ?? this.linkVendedorId,
      linkVendedorCodigo: linkVendedorCodigo ?? this.linkVendedorCodigo,
      origemEcommerce: origemEcommerce ?? this.origemEcommerce,
      origem: origem ?? this.origem,
      dataPedido: dataPedido ?? this.dataPedido,
      status: status ?? this.status,
      total: total ?? this.total,
      descontoTotal: descontoTotal ?? this.descontoTotal,
      acrescimoTotal: acrescimoTotal ?? this.acrescimoTotal,
      observacoes: observacoes ?? this.observacoes,
      produtos: produtos ?? this.produtos,
      servicos: servicos ?? this.servicos,
      pagamentos: pagamentos ?? this.pagamentos,
      materiaisConsumidos: materiaisConsumidos ?? this.materiaisConsumidos,
      deliveryInfo: deliveryInfo ?? this.deliveryInfo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      senha: senha ?? this.senha,
    );
  }
}

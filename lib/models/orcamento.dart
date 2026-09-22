import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

/// ORÇAMENTO de pedido — entidade própria (série `ORC-`), feita na tela de
/// Pedidos central.
///
/// Não é um Pedido: não aparece no PDV, não entra nos recebíveis, nos relatórios
/// de venda, no dashboard, na NFC-e nem no portal do contador. É uma **proposta**
/// com validade. Quando o cliente aprova, o orçamento gera um Pedido de verdade
/// (série PED-) e guarda o vínculo (`pedidoGeradoId`/`pedidoGeradoNumero`).
class Orcamento {
  static const String statusOrcamento = 'Orçamento';
  static const String statusAprovado = 'Aprovado';
  static const String statusRecusado = 'Recusado';
  static const String statusCancelado = 'Cancelado';

  static const List<String> statusDisponiveis = [
    statusOrcamento,
    statusAprovado,
    statusRecusado,
    statusCancelado,
  ];

  final String id;

  /// Número próprio da série de orçamentos (ORC-0001, ORC-0002, ...).
  final String numero;

  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? clienteEndereco;
  final String? clienteCpfCnpj;

  /// Quem montou o orçamento.
  final String? operador;

  final DateTime dataOrcamento;
  final DateTime? validadeOrcamento;
  final String status;
  final double total;
  final double descontoTotal;
  final double acrescimoTotal;
  final String? observacoes;
  final List<ItemPedido> itens;
  final List<ItemServico> servicos;
  final DeliveryInfo? deliveryInfo;

  /// Pedido gerado na aprovação.
  final String? pedidoGeradoId;
  final String? pedidoGeradoNumero;
  final DateTime? dataAprovacao;

  final DateTime createdAt;
  final DateTime updatedAt;

  Orcamento({
    required this.id,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    this.clienteEndereco,
    this.clienteCpfCnpj,
    this.operador,
    DateTime? dataOrcamento,
    this.validadeOrcamento,
    this.status = statusOrcamento,
    this.total = 0.0,
    this.descontoTotal = 0.0,
    this.acrescimoTotal = 0.0,
    this.observacoes,
    List<ItemPedido>? itens,
    List<ItemServico>? servicos,
    this.deliveryInfo,
    this.pedidoGeradoId,
    this.pedidoGeradoNumero,
    this.dataAprovacao,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : dataOrcamento = dataOrcamento ?? DateTime.now(),
       itens = itens ?? [],
       servicos = servicos ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get aprovado => status == statusAprovado;
  bool get recusado => status == statusRecusado;
  bool get cancelado => status == statusCancelado;

  /// Ainda é proposta válida: pode ser aprovada/recusada.
  bool get aberto => status == statusOrcamento;

  /// Já gerou um pedido?
  bool get temPedidoGerado =>
      pedidoGeradoId != null && pedidoGeradoId!.isNotEmpty;

  /// Aprovado e ainda sem pedido: é o momento de "Gerar pedido".
  bool get podeGerarPedido => aprovado && !temPedidoGerado && !cancelado;

  bool get orcamentoVencido {
    if (!aberto || validadeOrcamento == null) return false;
    final fimDoDia = DateTime(
      validadeOrcamento!.year,
      validadeOrcamento!.month,
      validadeOrcamento!.day,
      23,
      59,
      59,
    );
    return fimDoDia.isBefore(DateTime.now());
  }

  double get totalProdutos => itens.fold(
      0.0, (soma, item) => soma + (item.preco * item.quantidade));

  double get totalServicos =>
      servicos.fold(0.0, (soma, item) => soma + item.valor + item.valorAdicional);

  /// Total da proposta (usa o total gravado quando não há itens, mesma regra do
  /// [Pedido.totalGeral]).
  double get totalGeral {
    final subtotal = totalProdutos + totalServicos;
    if (subtotal < 0.01 && total > 0.01) {
      return total - descontoTotal + acrescimoTotal;
    }
    return subtotal - descontoTotal + acrescimoTotal;
  }

  double get quantidadeItens =>
      itens.fold(0.0, (soma, item) => soma + item.quantidade) + servicos.length;

  String get statusExibicao {
    if (aprovado) return 'APROVADO';
    if (recusado) return 'RECUSADO';
    if (cancelado) return 'CANCELADO';
    return orcamentoVencido ? 'ORÇAMENTO VENCIDO' : 'ORÇAMENTO';
  }

  Orcamento copyWith({
    String? id,
    String? numero,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteEndereco,
    String? clienteCpfCnpj,
    String? operador,
    DateTime? dataOrcamento,
    DateTime? validadeOrcamento,
    bool limparValidade = false,
    String? status,
    double? total,
    double? descontoTotal,
    double? acrescimoTotal,
    String? observacoes,
    List<ItemPedido>? itens,
    List<ItemServico>? servicos,
    DeliveryInfo? deliveryInfo,
    bool limparDelivery = false,
    String? pedidoGeradoId,
    String? pedidoGeradoNumero,
    DateTime? dataAprovacao,
    bool limparAprovacao = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Orcamento(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteEndereco: clienteEndereco ?? this.clienteEndereco,
      clienteCpfCnpj: clienteCpfCnpj ?? this.clienteCpfCnpj,
      operador: operador ?? this.operador,
      dataOrcamento: dataOrcamento ?? this.dataOrcamento,
      validadeOrcamento:
          limparValidade ? null : (validadeOrcamento ?? this.validadeOrcamento),
      status: status ?? this.status,
      total: total ?? this.total,
      descontoTotal: descontoTotal ?? this.descontoTotal,
      acrescimoTotal: acrescimoTotal ?? this.acrescimoTotal,
      observacoes: observacoes ?? this.observacoes,
      itens: itens ?? this.itens,
      servicos: servicos ?? this.servicos,
      deliveryInfo: limparDelivery ? null : (deliveryInfo ?? this.deliveryInfo),
      pedidoGeradoId: pedidoGeradoId ?? this.pedidoGeradoId,
      pedidoGeradoNumero: pedidoGeradoNumero ?? this.pedidoGeradoNumero,
      dataAprovacao:
          limparAprovacao ? null : (dataAprovacao ?? this.dataAprovacao),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      'operador': operador,
      // UTC explícito (Z): evita o Supabase deslocar o horário.
      'data_orcamento': dataOrcamento.toUtc().toIso8601String(),
      'validade_orcamento': validadeOrcamento?.toUtc().toIso8601String(),
      'status': status,
      'total': total,
      'descontoTotal': descontoTotal,
      'acrescimoTotal': acrescimoTotal,
      'observacoes': observacoes,
      'itens': itens.map((i) => i.toMap()).toList(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'delivery_info': deliveryInfo?.toMap(),
      'pedido_gerado_id': pedidoGeradoId,
      'pedido_gerado_numero': pedidoGeradoNumero,
      'data_aprovacao': dataAprovacao?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Orcamento.fromMap(Map<String, dynamic> map) {
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }

    String? getStr(String camel, String snake) => get<String>(camel, snake);
    List? getList(String camel, String snake) => get<List>(camel, snake);

    double parseDouble(dynamic valor) {
      if (valor == null) return 0.0;
      if (valor is num) return valor.toDouble();
      if (valor is String) return double.tryParse(valor) ?? 0.0;
      return 0.0;
    }

    DateTime? parseData(dynamic valor) {
      if (valor == null) return null;
      if (valor is String && valor.isEmpty) return null;
      return DateParser.parse(valor);
    }

    final deliveryMap = map['deliveryInfo'] ?? map['delivery_info'];

    return Orcamento(
      id: map['id']?.toString() ?? '',
      numero: map['numero']?.toString() ?? '',
      clienteId: getStr('clienteId', 'cliente_id'),
      clienteNome: getStr('clienteNome', 'cliente_nome'),
      clienteTelefone: getStr('clienteTelefone', 'cliente_telefone'),
      clienteEndereco: getStr('clienteEndereco', 'cliente_endereco'),
      clienteCpfCnpj: getStr('clienteCpfCnpj', 'cliente_cpf_cnpj'),
      operador: getStr('operador', 'operador'),
      dataOrcamento:
          DateParser.parse(map['dataOrcamento'] ?? map['data_orcamento']),
      validadeOrcamento:
          parseData(map['validadeOrcamento'] ?? map['validade_orcamento']),
      status: map['status']?.toString() ?? statusOrcamento,
      total: parseDouble(map['total']),
      descontoTotal: parseDouble(map['descontoTotal'] ?? map['desconto_total']),
      acrescimoTotal:
          parseDouble(map['acrescimoTotal'] ?? map['acrescimo_total']),
      observacoes: map['observacoes']?.toString(),
      itens: (getList('itens', 'itens') ?? [])
          .map((i) => ItemPedido.fromMap(i as Map<String, dynamic>))
          .toList(),
      servicos: (getList('servicos', 'servicos') ?? [])
          .map((s) => ItemServico.fromMap(s as Map<String, dynamic>))
          .toList(),
      deliveryInfo: deliveryMap is Map
          ? DeliveryInfo.fromMap(Map<String, dynamic>.from(deliveryMap))
          : null,
      pedidoGeradoId: getStr('pedidoGeradoId', 'pedido_gerado_id'),
      pedidoGeradoNumero:
          getStr('pedidoGeradoNumero', 'pedido_gerado_numero'),
      dataAprovacao: parseData(map['dataAprovacao'] ?? map['data_aprovacao']),
      createdAt: DateParser.parse(map['createdAt'] ?? map['created_at']),
      updatedAt: DateParser.parse(map['updatedAt'] ?? map['updated_at']),
    );
  }

  /// Adaptador para reaproveitar impressão e a tela de detalhes de Pedido
  /// (sem duplicar a lógica de PDF).
  Pedido toPedido() {
    return Pedido(
      id: id,
      numero: numero,
      clienteId: clienteId,
      clienteNome: clienteNome,
      clienteTelefone: clienteTelefone,
      clienteEndereco: clienteEndereco,
      clienteCpfCnpj: clienteCpfCnpj,
      operador: operador,
      dataPedido: dataOrcamento,
      status: status == statusAprovado ? 'Concluído' : 'Pendente',
      total: total,
      descontoTotal: descontoTotal,
      acrescimoTotal: acrescimoTotal,
      observacoes: observacoes,
      produtos: itens,
      servicos: servicos,
      pagamentos: const [],
      deliveryInfo: deliveryInfo,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

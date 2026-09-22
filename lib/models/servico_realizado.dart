import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/item_material.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

/// Serviço REALIZADO — entidade própria, separada de [Pedido].
///
/// Por que existe: um serviço não é uma venda de produto. Ele tem numeração
/// própria (SRV-0001), nasce como **Orçamento** (proposta, sem recebível),
/// vira **Em Aberto** quando o cliente aprova e **Recebido** quando o
/// pagamento é quitado. Fica fora do PDV e fora dos recebíveis de pedido.
class ServicoRealizado {
  /// Proposta enviada ao cliente — não gera recebível nem entra no caixa.
  static const String statusOrcamento = 'Orçamento';

  /// Aprovado/executado e ainda com valor a receber.
  static const String statusEmAberto = 'Em Aberto';

  /// Totalmente recebido.
  static const String statusRecebido = 'Recebido';

  /// Cancelado (nem orçamento válido, nem recebível).
  static const String statusCancelado = 'Cancelado';

  /// Situações que a tela de Serviços mostra em ordem.
  static const List<String> statusDisponiveis = [
    statusOrcamento,
    statusEmAberto,
    statusRecebido,
    statusCancelado,
  ];

  final String id;

  /// Número próprio da série de serviços (SRV-0001, SRV-0002, ...).
  final String numero;

  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? clienteEndereco;
  final String? petId;
  final String? petNome;

  /// Funcionário/atendente responsável pelo lançamento.
  final String? operador;

  /// Data do serviço (ou do orçamento).
  final DateTime dataServico;

  /// Conclusão da execução do serviço.
  final DateTime? dataConclusao;

  /// Data em que o orçamento foi enviado ao cliente.
  final DateTime? dataOrcamento;

  /// Validade do orçamento (proposta sem validade continua valendo).
  final DateTime? validadeOrcamento;

  final String status;
  final double total;
  final double descontoTotal;
  final double acrescimoTotal;
  final String? observacoes;
  final List<ItemServico> servicos;
  final List<PagamentoPedido> pagamentos;
  final List<ItemMaterial> materiaisConsumidos;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServicoRealizado({
    required this.id,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    this.clienteEndereco,
    this.petId,
    this.petNome,
    this.operador,
    DateTime? dataServico,
    this.dataConclusao,
    this.dataOrcamento,
    this.validadeOrcamento,
    this.status = statusEmAberto,
    this.total = 0.0,
    this.descontoTotal = 0.0,
    this.acrescimoTotal = 0.0,
    this.observacoes,
    List<ItemServico>? servicos,
    List<PagamentoPedido>? pagamentos,
    List<ItemMaterial>? materiaisConsumidos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : dataServico = dataServico ?? DateTime.now(),
       servicos = servicos ?? [],
       pagamentos = pagamentos ?? [],
       materiaisConsumidos = materiaisConsumidos ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get ehOrcamento => status == statusOrcamento;
  bool get cancelado => status == statusCancelado;

  /// Taxas de Taxi Dog somadas (a taxa não entra no valor do item).
  double get totalTaxiDog => servicos.fold(0.0, (sum, item) {
    if (item.tipoEntrega == 'Taxi Dog' &&
        item.valorTaxiDog != null &&
        item.valorTaxiDog! > 0) {
      return sum + item.valorTaxiDog!;
    }
    return sum;
  });

  /// Valor dos serviços (base + adicional + taxa de entrega).
  double get totalServicos =>
      servicos.fold(0.0, (sum, item) => sum + item.valor + item.valorAdicional) +
      totalTaxiDog;

  /// Total a pagar, já com descontos/acréscimos lançados no serviço e nos
  /// pagamentos (mesma regra usada em [Pedido.totalGeral]).
  double get totalGeral {
    final subtotal = totalServicos;
    final descontoPagamentos =
        pagamentos.fold(0.0, (sum, pag) => sum + (pag.desconto ?? 0.0));
    final acrescimoPagamentos =
        pagamentos.fold(0.0, (sum, pag) => sum + (pag.acrescimo ?? 0.0));

    final calculado = subtotal -
        descontoTotal +
        acrescimoTotal -
        descontoPagamentos +
        acrescimoPagamentos;

    if (subtotal < 0.01 && total > 0.01) {
      return total - descontoTotal + acrescimoTotal - descontoPagamentos + acrescimoPagamentos;
    }
    return calculado;
  }

  double get totalPagamentos =>
      pagamentos.fold(0.0, (sum, pag) => sum + pag.valor);

  double get totalRecebido =>
      pagamentos.where((p) => p.recebido).fold(0.0, (sum, pag) => sum + pag.valor);

  double get valorPendente => totalGeral - totalRecebido;

  bool get totalmenteRecebido =>
      !ehOrcamento && !cancelado && valorPendente <= 0.009;

  /// Em aberto = aprovado/executado, ainda com valor a receber.
  bool get emAberto =>
      !ehOrcamento && !cancelado && !totalmenteRecebido;

  bool get orcamentoVencido {
    if (!ehOrcamento || validadeOrcamento == null) return false;
    final hoje = DateTime.now();
    final fimDoDia = DateTime(
      validadeOrcamento!.year,
      validadeOrcamento!.month,
      validadeOrcamento!.day,
      23,
      59,
      59,
    );
    return fimDoDia.isBefore(hoje);
  }

  int get parcelasPendentes => pagamentos.where((p) => !p.recebido).length;
  int get parcelasPagas => pagamentos.where((p) => p.recebido).length;
  int get totalParcelas => pagamentos.length;

  List<PagamentoPedido> get parcelasVencidas =>
      pagamentos.where((p) => p.isVencida).toList();

  bool get temParcelasVencidas => parcelasVencidas.isNotEmpty;

  PagamentoPedido? get proximaParcela {
    final pendentes =
        pagamentos.where((p) => !p.recebido && p.dataVencimento != null).toList();
    if (pendentes.isEmpty) return null;
    pendentes.sort((a, b) => a.dataVencimento!.compareTo(b.dataVencimento!));
    return pendentes.first;
  }

  String get statusParcelamento {
    if (pagamentos.isEmpty) return ehOrcamento ? 'Orçamento' : 'Sem pagamento';
    if (totalmenteRecebido) return 'Quitado';
    if (temParcelasVencidas) return 'Em atraso';
    if (parcelasPagas > 0) return 'Parcialmente pago';
    return 'Aguardando';
  }

  /// Entrega (Taxi Dog) do serviço — usada para o romaneio/impressão.
  ItemServico? get servicoComEntrega {
    for (final item in servicos) {
      if (item.tipoEntrega == 'Taxi Dog') return item;
    }
    return null;
  }

  bool get temTaxiDog => servicoComEntrega != null;

  String get statusExibicao {
    if (ehOrcamento) return 'ORÇAMENTO';
    if (cancelado) return 'CANCELADO';
    if (totalmenteRecebido) return 'RECEBIDO';
    return 'EM ABERTO';
  }

  ServicoRealizado copyWith({
    String? id,
    String? numero,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteEndereco,
    String? petId,
    String? petNome,
    String? operador,
    DateTime? dataServico,
    DateTime? dataConclusao,
    DateTime? dataOrcamento,
    DateTime? validadeOrcamento,
    String? status,
    double? total,
    double? descontoTotal,
    double? acrescimoTotal,
    String? observacoes,
    List<ItemServico>? servicos,
    List<PagamentoPedido>? pagamentos,
    List<ItemMaterial>? materiaisConsumidos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServicoRealizado(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteEndereco: clienteEndereco ?? this.clienteEndereco,
      petId: petId ?? this.petId,
      petNome: petNome ?? this.petNome,
      operador: operador ?? this.operador,
      dataServico: dataServico ?? this.dataServico,
      dataConclusao: dataConclusao ?? this.dataConclusao,
      dataOrcamento: dataOrcamento ?? this.dataOrcamento,
      validadeOrcamento: validadeOrcamento ?? this.validadeOrcamento,
      status: status ?? this.status,
      total: total ?? this.total,
      descontoTotal: descontoTotal ?? this.descontoTotal,
      acrescimoTotal: acrescimoTotal ?? this.acrescimoTotal,
      observacoes: observacoes ?? this.observacoes,
      servicos: servicos ?? this.servicos,
      pagamentos: pagamentos ?? this.pagamentos,
      materiaisConsumidos: materiaisConsumidos ?? this.materiaisConsumidos,
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
      'pet_id': petId,
      'pet_nome': petNome,
      'operador': operador,
      // UTC explícito (Z) para o Supabase não deslocar o horário (mesma regra
      // usada em VendaBalcao.toMap).
      'data_servico': dataServico.toUtc().toIso8601String(),
      'data_conclusao': dataConclusao?.toUtc().toIso8601String(),
      'data_orcamento': dataOrcamento?.toUtc().toIso8601String(),
      'validade_orcamento': validadeOrcamento?.toUtc().toIso8601String(),
      'status': status,
      'total': total,
      'descontoTotal': descontoTotal,
      'acrescimoTotal': acrescimoTotal,
      'observacoes': observacoes,
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
      'materiaisConsumidos': materiaisConsumidos.map((m) => m.toMap()).toList(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ServicoRealizado.fromMap(Map<String, dynamic> map) {
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }

    String? getStr(String camel, String snake) => get<String>(camel, snake);
    List? getList(String camel, String snake) => get<List>(camel, snake);

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Datas opcionais: nulas continuam nulas; quando vêm preenchidas são
    // convertidas para o horário local (mesma regra do DateParser).
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is String && value.isEmpty) return null;
      return DateParser.parse(value);
    }

    return ServicoRealizado(
      id: map['id']?.toString() ?? '',
      numero: map['numero']?.toString() ?? '',
      clienteId: getStr('clienteId', 'cliente_id'),
      clienteNome: getStr('clienteNome', 'cliente_nome'),
      clienteTelefone: getStr('clienteTelefone', 'cliente_telefone'),
      clienteEndereco: getStr('clienteEndereco', 'cliente_endereco'),
      petId: getStr('petId', 'pet_id'),
      petNome: getStr('petNome', 'pet_nome'),
      operador: getStr('operador', 'operador'),
      dataServico: DateParser.parse(
        map['dataServico'] ?? map['data_servico'],
      ),
      dataConclusao:
          parseDate(map['dataConclusao'] ?? map['data_conclusao']),
      dataOrcamento: parseDate(map['dataOrcamento'] ?? map['data_orcamento']),
      validadeOrcamento:
          parseDate(map['validadeOrcamento'] ?? map['validade_orcamento']),
      status: map['status']?.toString() ?? statusEmAberto,
      total: parseDouble(map['total']),
      descontoTotal: parseDouble(map['descontoTotal'] ?? map['desconto_total']),
      acrescimoTotal:
          parseDouble(map['acrescimoTotal'] ?? map['acrescimo_total']),
      observacoes: map['observacoes']?.toString(),
      servicos: (getList('servicos', 'servicos') ?? [])
          .map((s) => ItemServico.fromMap(s as Map<String, dynamic>))
          .toList(),
      pagamentos: (getList('pagamentos', 'pagamentos') ?? [])
          .map((p) => PagamentoPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      materiaisConsumidos:
          (getList('materiaisConsumidos', 'materiais_consumidos') ?? [])
              .map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>))
              .toList(),
      createdAt: DateParser.parse(map['createdAt'] ?? map['created_at']),
      updatedAt: DateParser.parse(map['updatedAt'] ?? map['updated_at']),
    );
  }

  /// Adaptador para reaproveitar impressão (térmico/A4/romaneio) e a tela de
  /// detalhes que já existem para [Pedido], sem duplicar 3 mil linhas de PDF.
  Pedido toPedido({String? numero}) {
    return Pedido(
      id: id,
      numero: numero ?? this.numero,
      clienteId: clienteId,
      clienteNome: clienteNome,
      clienteTelefone: clienteTelefone,
      clienteEndereco: clienteEndereco,
      operador: operador,
      dataPedido: dataServico,
      status: status == statusRecebido ? 'Concluído' : status,
      total: total,
      descontoTotal: descontoTotal,
      acrescimoTotal: acrescimoTotal,
      observacoes: observacoes,
      produtos: const [],
      servicos: servicos,
      pagamentos: pagamentos,
      materiaisConsumidos: materiaisConsumidos,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

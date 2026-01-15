library mesa_comanda;

import 'conta_pagar.dart';

/// Status de um item em uma mesa/comanda
enum StatusItem {
  pendente, // Aguardando preparo
  emPreparo, // Sendo preparado
  pronto, // Pronto para servir
  entregue, // Já foi entregue
  cancelado, // Item cancelado
}

/// Tipo de controle (Mesa ou Comanda)
enum TipoControle {
  mesa,
  comanda,
}

/// Item de pedido com status de preparo
class ItemMesaComanda {
  final String id;
  final String itemId; // ID do produto ou serviço
  final String nome;
  final int quantidade;
  final double preco;
  final bool isServico;
  final bool? paraCozinha; // Mantido para compatibilidade
  final bool? paraBar; // Mantido para compatibilidade
  final String? local; // Local customizado (ex: "Cozinha", "Bar", "Sobremesas", etc.)
  final StatusItem status;
  final DateTime dataHora;
  final DateTime? dataHoraPronto;
  final String? observacao;
  // Campos de auditoria/rastreamento
  final String? usuarioCriou; // Nome do usuário que criou o item
  final String? usuarioModificou; // Nome do usuário que modificou o item pela última vez
  final DateTime? dataModificacao; // Data da última modificação
  final String? acaoRealizada; // Ação realizada (ex: "Criado", "Cancelado", "Status alterado")

  ItemMesaComanda({
    required this.id,
    required this.itemId,
    required this.nome,
    required this.quantidade,
    required this.preco,
    this.isServico = false,
    this.paraCozinha,
    this.paraBar,
    this.local,
    this.status = StatusItem.pendente,
    DateTime? dataHora,
    this.dataHoraPronto,
    this.observacao,
    this.usuarioCriou,
    this.usuarioModificou,
    this.dataModificacao,
    this.acaoRealizada,
  }) : dataHora = dataHora ?? DateTime.now();

  ItemMesaComanda copyWith({
    String? id,
    String? itemId,
    String? nome,
    int? quantidade,
    double? preco,
    bool? isServico,
    bool? paraCozinha,
    bool? paraBar,
    String? local,
    StatusItem? status,
    DateTime? dataHora,
    DateTime? dataHoraPronto,
    String? observacao,
    String? usuarioCriou,
    String? usuarioModificou,
    DateTime? dataModificacao,
    String? acaoRealizada,
  }) {
    return ItemMesaComanda(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      nome: nome ?? this.nome,
      quantidade: quantidade ?? this.quantidade,
      preco: preco ?? this.preco,
      isServico: isServico ?? this.isServico,
      paraCozinha: paraCozinha ?? this.paraCozinha,
      paraBar: paraBar ?? this.paraBar,
      local: local ?? this.local,
      status: status ?? this.status,
      dataHora: dataHora ?? this.dataHora,
      dataHoraPronto: dataHoraPronto ?? this.dataHoraPronto,
      observacao: observacao ?? this.observacao,
      usuarioCriou: usuarioCriou ?? this.usuarioCriou,
      usuarioModificou: usuarioModificou ?? this.usuarioModificou,
      dataModificacao: dataModificacao ?? this.dataModificacao,
      acaoRealizada: acaoRealizada ?? this.acaoRealizada,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemId': itemId,
      'nome': nome,
      'quantidade': quantidade,
      'preco': preco,
      'isServico': isServico,
      'paraCozinha': paraCozinha,
      'paraBar': paraBar,
      'local': local,
      'status': status.toString().split('.').last,
      'dataHora': dataHora.toIso8601String(),
      'dataHoraPronto': dataHoraPronto?.toIso8601String(),
      'observacao': observacao,
      'usuarioCriou': usuarioCriou,
      'usuarioModificou': usuarioModificou,
      'dataModificacao': dataModificacao?.toIso8601String(),
      'acaoRealizada': acaoRealizada,
    };
  }

  factory ItemMesaComanda.fromMap(Map<String, dynamic> map) {
    return ItemMesaComanda(
      id: map['id'] as String,
      itemId: map['itemId'] as String,
      nome: map['nome'] as String,
      quantidade: map['quantidade'] as int,
      preco: (map['preco'] as num).toDouble(),
      isServico: map['isServico'] as bool? ?? false,
      paraCozinha: map['paraCozinha'] as bool?,
      paraBar: map['paraBar'] as bool?,
      local: map['local'] as String?,
      status: StatusItem.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => StatusItem.pendente,
      ),
      dataHora: DateTime.parse(map['dataHora'] as String),
      dataHoraPronto: map['dataHoraPronto'] != null
          ? DateTime.parse(map['dataHoraPronto'] as String)
          : null,
      observacao: map['observacao'] as String?,
      usuarioCriou: map['usuarioCriou'] as String?,
      usuarioModificou: map['usuarioModificou'] as String?,
      dataModificacao: map['dataModificacao'] != null
          ? DateTime.parse(map['dataModificacao'] as String)
          : null,
      acaoRealizada: map['acaoRealizada'] as String?,
    );
  }
}

/// Modelo para Mesa ou Comanda
class MesaComanda {
  final String id;
  final TipoControle tipo; // Mesa ou Comanda
  final String numero; // Número da mesa ou comanda (ex: "MESA-01", "CMD-001")
  final String? clienteId;
  final String? clienteNome;
  final String? mesaId; // ID da mesa (se esta comanda está vinculada a uma mesa)
  final List<ItemMesaComanda> itens;
  final DateTime dataAbertura;
  final DateTime? dataFechamento;
  final String status; // Aberta, Fechada, Cancelada
  final String? observacao;
  final double total;
  final List<RegistroPagamento> historicoPagamentos; // Histórico de pagamentos
  final List<String> itensPagos; // IDs dos itens que já foram pagos
  final double couvertPago; // Valor do couvert já pago (permite pagamento parcial)
  final DateTime createdAt;
  final DateTime updatedAt;
  // Campos de auditoria/rastreamento
  final String? usuarioCriou; // Nome do usuário que criou a mesa/comanda
  final String? usuarioModificou; // Nome do usuário que modificou pela última vez
  // Campos de garçom e couvert
  final double? valorCouvert; // Valor do couvert artístico (calculado: quantidadePessoasCouvert * valorCouvertPorPessoa)
  final int? quantidadePessoasCouvert; // Número de pessoas para o couvert
  final double? valorCouvertPorPessoa; // Valor do couvert por pessoa
  final double? valorGarcom; // Valor do garçom (10% do total)
  final bool garcomRetirado; // Se o garçom já foi retirado

  MesaComanda({
    required this.id,
    required this.tipo,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.mesaId,
    List<ItemMesaComanda>? itens,
    DateTime? dataAbertura,
    this.dataFechamento,
    this.status = 'Aberta',
    this.observacao,
    double? total,
    List<RegistroPagamento>? historicoPagamentos,
    List<String>? itensPagos,
    double? couvertPago,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.usuarioCriou,
    this.usuarioModificou,
    this.valorCouvert,
    this.quantidadePessoasCouvert,
    this.valorCouvertPorPessoa,
    this.valorGarcom,
    bool? garcomRetirado,
  }) : itens = itens ?? [],
        dataAbertura = dataAbertura ?? DateTime.now(),
        total = total ?? 0.0,
        historicoPagamentos = historicoPagamentos ?? [],
        itensPagos = itensPagos ?? [],
       couvertPago = couvertPago ?? 0.0,
        createdAt = createdAt ?? DateTime.now(),
        garcomRetirado = garcomRetirado ?? false,
        updatedAt = updatedAt ?? DateTime.now();

  // Calcula o valor do couvert (quantidade de pessoas * valor por pessoa)
  double get valorCouvertCalculado {
    if (quantidadePessoasCouvert != null && valorCouvertPorPessoa != null) {
      return quantidadePessoasCouvert! * valorCouvertPorPessoa!;
    }
    // Fallback para valorCouvert antigo (compatibilidade)
    return valorCouvert ?? 0.0;
  }

  // Calcula o total dos itens (excluindo itens cancelados)
  double get totalCalculado {
    final totalItens = itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + (item.preco * item.quantidade));
    
    // Adicionar couvert se houver
    final totalComCouvert = totalItens + valorCouvertCalculado;
    
    // Adicionar garçom se não foi retirado (10% apenas dos itens, sem couvert)
    if (!garcomRetirado && valorGarcom != null) {
      return totalComCouvert + valorGarcom!;
    }
    
    return totalComCouvert;
  }
  
  // Calcula o valor do garçom (10% apenas dos itens, SEM couvert)
  double get valorGarcomCalculado {
    final totalItens = itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + (item.preco * item.quantidade));
    return totalItens * 0.10; // 10% apenas dos itens (sem couvert)
  }

  // Itens pendentes
  List<ItemMesaComanda> get itensPendentes {
    return itens.where((i) => i.status == StatusItem.pendente).toList();
  }

  // Itens em preparo
  List<ItemMesaComanda> get itensEmPreparo {
    return itens.where((i) => i.status == StatusItem.emPreparo).toList();
  }

  // Itens prontos
  List<ItemMesaComanda> get itensProntos {
    return itens.where((i) => i.status == StatusItem.pronto).toList();
  }

  // Itens cancelados
  List<ItemMesaComanda> get itensCancelados {
    return itens.where((i) => i.status == StatusItem.cancelado).toList();
  }

  // Itens para cozinha
  List<ItemMesaComanda> get itensCozinha {
    return itens.where((i) => i.paraCozinha == true).toList();
  }

  // Itens para bar
  List<ItemMesaComanda> get itensBar {
    return itens.where((i) => i.paraBar == true).toList();
  }

  // Verifica se tem itens pendentes
  bool get temItensPendentes => itensPendentes.isNotEmpty;

  // Verifica se tem itens em preparo
  bool get temItensEmPreparo => itensEmPreparo.isNotEmpty;

  // Verifica se tem itens prontos
  bool get temItensProntos => itensProntos.isNotEmpty;

  // Valor do couvert pendente (não pago)
  double get couvertPendente {
    final couvertTotal = valorCouvertCalculado;
    return (couvertTotal - couvertPago).clamp(0.0, couvertTotal);
  }

  // Verifica se o couvert está totalmente pago
  bool get couvertTotalmentePago {
    final couvertTotal = valorCouvertCalculado;
    if (couvertTotal <= 0) return true; // Sem couvert = considerado pago
    return couvertPago >= couvertTotal - 0.01; // Tolerância para arredondamento
  }

  // Total já pago (itens + couvert)
  double get totalPago {
    final pagamentosItens = historicoPagamentos.fold(0.0, (sum, p) => sum + p.valor);
    return pagamentosItens + couvertPago;
  }

  // Total pendente (total - pago)
  // IMPORTANTE: Não permitir saldo negativo quando não há itens
  double get totalPendente {
    final pendente = totalCalculado - totalPago;
    // Se não há itens e não há couvert, o pendente deve ser 0 (não negativo)
    if (itens.isEmpty && valorCouvertCalculado <= 0) {
      return 0.0;
    }
    return pendente < 0 ? 0.0 : pendente;
  }

  // Verifica se está totalmente pago
  bool get estaTotalmentePago {
    return totalPendente <= 0.01; // Tolerância para arredondamento
  }

  // Itens não pagos
  List<ItemMesaComanda> get itensNaoPagos {
    return itens
        .where((item) => item.status != StatusItem.cancelado && !itensPagos.contains(item.id))
        .toList();
  }

  // Itens pagos
  List<ItemMesaComanda> get itensPagosLista {
    return itens.where((item) => itensPagos.contains(item.id)).toList();
  }

  MesaComanda copyWith({
    String? id,
    TipoControle? tipo,
    String? numero,
    String? clienteId,
    String? clienteNome,
    String? mesaId,
    List<ItemMesaComanda>? itens,
    DateTime? dataAbertura,
    DateTime? dataFechamento,
    String? status,
    String? observacao,
    double? total,
    List<RegistroPagamento>? historicoPagamentos,
    List<String>? itensPagos,
    double? couvertPago,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? usuarioCriou,
    String? usuarioModificou,
    double? valorCouvert,
    int? quantidadePessoasCouvert,
    double? valorCouvertPorPessoa,
    double? valorGarcom,
    bool? garcomRetirado,
  }) {
    return MesaComanda(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      numero: numero ?? this.numero,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      mesaId: mesaId ?? this.mesaId,
      itens: itens ?? this.itens,
      dataAbertura: dataAbertura ?? this.dataAbertura,
      dataFechamento: dataFechamento ?? this.dataFechamento,
      status: status ?? this.status,
      observacao: observacao ?? this.observacao,
      total: total ?? this.total,
      historicoPagamentos: historicoPagamentos ?? this.historicoPagamentos,
      itensPagos: itensPagos ?? this.itensPagos,
      couvertPago: couvertPago ?? this.couvertPago,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      usuarioCriou: usuarioCriou ?? this.usuarioCriou,
      usuarioModificou: usuarioModificou ?? this.usuarioModificou,
      valorCouvert: valorCouvert ?? this.valorCouvert,
      quantidadePessoasCouvert: quantidadePessoasCouvert ?? this.quantidadePessoasCouvert,
      valorCouvertPorPessoa: valorCouvertPorPessoa ?? this.valorCouvertPorPessoa,
      valorGarcom: valorGarcom ?? this.valorGarcom,
      garcomRetirado: garcomRetirado ?? this.garcomRetirado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo.toString().split('.').last,
      'numero': numero,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'mesaId': mesaId,
      'itens': itens.map((i) => i.toMap()).toList(),
      'dataAbertura': dataAbertura.toIso8601String(),
      'dataFechamento': dataFechamento?.toIso8601String(),
      'status': status,
      'observacao': observacao,
      'total': total,
      'historicoPagamentos': historicoPagamentos.map((p) => p.toMap()).toList(),
      'itensPagos': itensPagos,
      'couvertPago': couvertPago,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'usuarioCriou': usuarioCriou,
      'usuarioModificou': usuarioModificou,
      'valorCouvert': valorCouvert,
      'quantidadePessoasCouvert': quantidadePessoasCouvert,
      'valorCouvertPorPessoa': valorCouvertPorPessoa,
      'valorGarcom': valorGarcom,
      'garcomRetirado': garcomRetirado,
    };
  }

  factory MesaComanda.fromMap(Map<String, dynamic> map) {
    return MesaComanda(
      id: map['id'] as String,
      tipo: TipoControle.values.firstWhere(
        (e) => e.toString().split('.').last == map['tipo'],
        orElse: () => TipoControle.mesa,
      ),
      numero: map['numero'] as String,
      clienteId: map['clienteId'] as String?,
      clienteNome: map['clienteNome'] as String?,
      mesaId: map['mesaId'] as String?,
      itens: (map['itens'] as List<dynamic>?)
              ?.map((i) => ItemMesaComanda.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      dataAbertura: DateTime.parse(map['dataAbertura'] as String),
      dataFechamento: map['dataFechamento'] != null
          ? DateTime.parse(map['dataFechamento'] as String)
          : null,
      status: map['status'] as String? ?? 'Aberta',
      observacao: map['observacao'] as String?,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      historicoPagamentos: (map['historicoPagamentos'] as List<dynamic>?)
              ?.map((p) => RegistroPagamento.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      itensPagos: (map['itensPagos'] as List<dynamic>?)
              ?.map((i) => i as String)
              .toList() ??
          [],
      couvertPago: (map['couvertPago'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      usuarioCriou: map['usuarioCriou'] as String?,
      usuarioModificou: map['usuarioModificou'] as String?,
      valorCouvert: (map['valorCouvert'] as num?)?.toDouble(),
      quantidadePessoasCouvert: map['quantidadePessoasCouvert'] != null 
          ? (map['quantidadePessoasCouvert'] as num).toInt()
          : null,
      valorCouvertPorPessoa: (map['valorCouvertPorPessoa'] as num?)?.toDouble(),
      valorGarcom: (map['valorGarcom'] as num?)?.toDouble(),
      garcomRetirado: map['garcomRetirado'] as bool? ?? false,
    );
  }
}


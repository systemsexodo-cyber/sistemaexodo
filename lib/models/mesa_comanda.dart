library mesa_comanda;

import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

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
  final double quantidade;
  final double preco;
  final bool isServico;
  final bool? paraCozinha; // Mantido para compatibilidade
  final bool? paraBar; // Mantido para compatibilidade
  final String? local; // Local customizado (ex: "Cozinha", "Bar", "Sobremesas", etc.)
  final StatusItem status;
  final DateTime dataHora;
  final DateTime? dataHoraPronto;
  final String? observacao;
  final List<AdicionalProduto> adicionais; // Adicionais selecionados para este item
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
    List<AdicionalProduto>? adicionais,
  }) : dataHora = dataHora ?? DateTime.now(),
       adicionais = adicionais ?? [];

  ItemMesaComanda copyWith({
    String? id,
    String? itemId,
    String? nome,
    double? quantidade,
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
      adicionais: adicionais ?? this.adicionais,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'nome': nome,
      'quantidade': quantidade,
      'preco': preco,
      'is_servico': isServico,
      'para_cozinha': paraCozinha,
      'para_bar': paraBar,
      'local': local,
      'status': status.toString().split('.').last,
      'data_hora': dataHora.toIso8601String(),
      'data_hora_pronto': dataHoraPronto?.toIso8601String(),
      'observacao': observacao,
      'usuario_criou': usuarioCriou,
      'usuario_modificou': usuarioModificou,
      'data_modificacao': dataModificacao?.toIso8601String(),
      'acao_realizada': acaoRealizada,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
    };
  }

  factory ItemMesaComanda.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return ItemMesaComanda(
      id: map['id'] as String,
      itemId: (map['item_id'] ?? map['itemId']) as String,
      nome: map['nome'] as String,
      quantidade: parseDouble(map['quantidade']) ?? 0.0,
      preco: parseDouble(map['preco']) ?? 0.0,
      isServico: (map['is_servico'] ?? map['isServico']) as bool? ?? false,
      paraCozinha: (map['para_cozinha'] ?? map['paraCozinha']) as bool?,
      paraBar: (map['para_bar'] ?? map['paraBar']) as bool?,
      local: map['local'] as String?,
      status: StatusItem.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => StatusItem.pendente,
      ),
      dataHora: DateParser.parse(map['data_hora'] ?? map['dataHora']),
      dataHoraPronto: (map['data_hora_pronto'] ?? map['dataHoraPronto']) != null
          ? DateParser.parse(map['data_hora_pronto'] ?? map['dataHoraPronto'])
          : null,
      observacao: map['observacao'] as String?,
      usuarioCriou: (map['usuario_criou'] ?? map['usuarioCriou']) as String?,
      usuarioModificou: (map['usuario_modificou'] ?? map['usuarioModificou']) as String?,
      dataModificacao: (map['data_modificacao'] ?? map['dataModificacao']) != null
          ? DateParser.parse(map['data_modificacao'] ?? map['dataModificacao'])
          : null,
      acaoRealizada: (map['acao_realizada'] ?? map['acaoRealizada']) as String?,
      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Calcula o preço unitário total (base + adicionais)
  double get precoUnitarioComAdicionais {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return preco + totalAdicionais;
  }

  /// Calcula o subtotal (preço unitário total * quantidade)
  double get subtotal => precoUnitarioComAdicionais * quantidade;
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
  final String? nomeQuemPagouCouvert; // Nome de quem pagou o couvert
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
    this.nomeQuemPagouCouvert,
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
    final totalItensFiltered = itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + item.subtotal);
    
    // Adicionar couvert se houver (considerar se tem pessoas)
    final temConsumoCouvert = (quantidadePessoasCouvert ?? 0) > 0 && (valorCouvertPorPessoa ?? 0) > 0;
    final totalComCouvert = totalItensFiltered + (temConsumoCouvert ? valorCouvertCalculado : 0.0);
    
    // Se não há itens nem couvert, o total deve ser 0 (ignorar taxas residuais)
    if (totalItensFiltered <= 0.01 && !temConsumoCouvert) {
      return 0.0;
    }
    
    // Adicionar garçom se não foi retirado (10% apenas dos itens, sem couvert)
    if (!garcomRetirado) {
      final vGarcom = valorGarcom ?? valorGarcomCalculado;
      if (vGarcom > 0.01) {
        return totalComCouvert + vGarcom;
      }
    }
    
    return totalComCouvert;
  }
  
  // Calcula o valor do garçom (10% apenas dos itens, SEM couvert)
  double get valorGarcomCalculado {
    final totalItens = itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + item.subtotal);
    return totalItens * 0.10; // 10% apenas dos itens (sem couvert)
  }

  // Alias para valor do garçom (taxa de serviço) para uso em relatórios e histórico
  double get valorTaxaServicoCalculado {
    if (garcomRetirado) return 0.0;
    
    // Se não há itens, a taxa de serviço deve ser 0
    final totalItensFiltered = itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + item.subtotal);
    
    if (totalItensFiltered <= 0.01) return 0.0;
    
    return valorGarcom ?? valorGarcomCalculado;
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
    
    // Se não há itens e nem couvert (considerando se tem pessoas), o pendente deve ser 0 (não negativo)
    final temConsumoCouvert = (quantidadePessoasCouvert ?? 0) > 0 && (valorCouvertPorPessoa ?? 0) > 0;
    if (itens.isEmpty && !temConsumoCouvert) {
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

  static const Object _sentinel = Object();

  MesaComanda copyWith({
    String? id,
    TipoControle? tipo,
    String? numero,
    Object? clienteId = _sentinel,
    Object? clienteNome = _sentinel,
    Object? mesaId = _sentinel,
    List<ItemMesaComanda>? itens,
    DateTime? dataAbertura,
    Object? dataFechamento = _sentinel,
    String? status,
    Object? observacao = _sentinel,
    double? total,
    List<RegistroPagamento>? historicoPagamentos,
    List<String>? itensPagos,
    double? couvertPago,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? usuarioCriou,
    String? usuarioModificou,
    Object? valorCouvert = _sentinel,
    Object? quantidadePessoasCouvert = _sentinel,
    Object? valorCouvertPorPessoa = _sentinel,
    Object? nomeQuemPagouCouvert = _sentinel,
    Object? valorGarcom = _sentinel,
    bool? garcomRetirado,
  }) {
    return MesaComanda(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      numero: numero ?? this.numero,
      clienteId: (clienteId == _sentinel) ? this.clienteId : (clienteId as String?),
      clienteNome: (clienteNome == _sentinel) ? this.clienteNome : (clienteNome as String?),
      mesaId: (mesaId == _sentinel) ? this.mesaId : (mesaId as String?),
      itens: itens ?? this.itens,
      dataAbertura: dataAbertura ?? this.dataAbertura,
      dataFechamento: (dataFechamento == _sentinel) ? this.dataFechamento : (dataFechamento as DateTime?),
      status: status ?? this.status,
      observacao: (observacao == _sentinel) ? this.observacao : (observacao as String?),
      total: total ?? this.total,
      historicoPagamentos: historicoPagamentos ?? this.historicoPagamentos,
      itensPagos: itensPagos ?? this.itensPagos,
      couvertPago: couvertPago ?? this.couvertPago,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      usuarioCriou: usuarioCriou ?? this.usuarioCriou,
      usuarioModificou: usuarioModificou ?? this.usuarioModificou,
      valorCouvert: (valorCouvert == _sentinel) ? this.valorCouvert : (valorCouvert as double?),
      quantidadePessoasCouvert: (quantidadePessoasCouvert == _sentinel) ? this.quantidadePessoasCouvert : (quantidadePessoasCouvert as int?),
      valorCouvertPorPessoa: (valorCouvertPorPessoa == _sentinel) ? this.valorCouvertPorPessoa : (valorCouvertPorPessoa as double?),
      nomeQuemPagouCouvert: (nomeQuemPagouCouvert == _sentinel) ? this.nomeQuemPagouCouvert : (nomeQuemPagouCouvert as String?),
      valorGarcom: (valorGarcom == _sentinel) ? this.valorGarcom : (valorGarcom as double?),
      garcomRetirado: garcomRetirado ?? this.garcomRetirado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo.toString().split('.').last,
      'numero': numero,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'mesa_id': mesaId,
      'itens': itens.map((i) => i.toMap()).toList(),
      'data_abertura': dataAbertura.toIso8601String(),
      'data_fechamento': dataFechamento?.toIso8601String(),
      'status': status,
      'observacao': observacao,
      'total': total,
      'historico_pagamentos': historicoPagamentos.map((p) => p.toMap()).toList(),
      'itens_pagos': itensPagos,
      'couvert_pago': couvertPago,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'usuario_criou': usuarioCriou,
      'usuario_modificou': usuarioModificou,
      'valor_couvert': valorCouvert,
      'quantidade_pessoas_couvert': quantidadePessoasCouvert,
      'valor_couvert_por_pessoa': valorCouvertPorPessoa,
      'nome_quem_pagou_couvert': nomeQuemPagouCouvert,
      'valor_garcom': valorGarcom,
      'garcom_retirado': garcomRetirado,
    };
  }

  factory MesaComanda.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return MesaComanda(
      id: map['id'] as String,
      tipo: TipoControle.values.firstWhere(
        (e) => e.toString().split('.').last == map['tipo'],
        orElse: () => TipoControle.mesa,
      ),
      numero: map['numero'] as String,
      clienteId: (map['cliente_id'] ?? map['clienteId']) as String?,
      clienteNome: (map['cliente_nome'] ?? map['clienteNome']) as String?,
      mesaId: (map['mesa_id'] ?? map['mesaId']) as String?,
      itens: (map['itens'] as List<dynamic>?)
              ?.map((i) => ItemMesaComanda.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      dataAbertura: DateParser.parse(map['data_abertura'] ?? map['dataAbertura']),
      dataFechamento: (map['data_fechamento'] ?? map['dataFechamento']) != null
          ? DateParser.parse(map['data_fechamento'] ?? map['dataFechamento'])
          : null,
      status: map['status'] as String? ?? 'Aberta',
      observacao: map['observacao'] as String?,
      total: parseDouble(map['total']) ?? 0.0,
      historicoPagamentos: ((map['historico_pagamentos'] ?? map['historicoPagamentos']) != null && (map['historico_pagamentos'] ?? map['historicoPagamentos']) is List)
              ? ((map['historico_pagamentos'] ?? map['historicoPagamentos']) as List<dynamic>)
                  .map((p) => RegistroPagamento.fromMap(p as Map<String, dynamic>))
                  .toList()
              : [],
      itensPagos: ((map['itens_pagos'] ?? map['itensPagos']) != null && (map['itens_pagos'] ?? map['itensPagos']) is List)
              ? ((map['itens_pagos'] ?? map['itensPagos']) as List<dynamic>)
                  .map((i) => i as String)
                  .toList()
              : [],
      couvertPago: parseDouble(map['couvert_pago'] ?? map['couvertPago']) ?? 0.0,
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
      usuarioCriou: (map['usuario_criou'] ?? map['usuarioCriou']) as String?,
      usuarioModificou: (map['usuario_modificou'] ?? map['usuarioModificou']) as String?,
      valorCouvert: parseDouble(map['valor_couvert'] ?? map['valorCouvert']),
      quantidadePessoasCouvert: (map['quantidade_pessoas_couvert'] ?? map['quantidadePessoasCouvert']) != null 
          ? ((map['quantidade_pessoas_couvert'] ?? map['quantidadePessoasCouvert']) as num).toInt()
          : null,
      valorCouvertPorPessoa: parseDouble(map['valor_couvert_por_pessoa'] ?? map['valorCouvertPorPessoa']),
      nomeQuemPagouCouvert: (map['nome_quem_pagou_couvert'] ?? map['nomeQuemPagouCouvert']) as String?,
      valorGarcom: parseDouble(map['valor_garcom'] ?? map['valorGarcom']),
      garcomRetirado: (map['garcom_retirado'] ?? map['garcomRetirado']) as bool? ?? false,
    );
  }
}


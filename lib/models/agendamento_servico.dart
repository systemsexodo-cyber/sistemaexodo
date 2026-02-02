import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/models/item_material.dart';

/// Modelo para representar um agendamento de serviço
class AgendamentoServico {
  final String id;
  final String numero; // Número sequencial do agendamento (AGD-0001, AGD-0002, etc.)
  final String? servicoId; // ID do serviço (opcional - pode ser null)
  final Servico? servico; // Referência ao serviço (pode ser null se serviço foi deletado ou não selecionado)
  final String? clienteId;
  final Cliente? cliente; // Referência ao cliente
  final String? petId; // ID do pet
  final Pet? pet; // Referência ao pet
  final DateTime dataAgendamento; // Data e hora do agendamento
  final int duracaoMinutos; // Duração estimada do serviço em minutos
  final String? observacoes;
  final String status; // 'Agendado', 'Em Andamento', 'Concluído', 'Cancelado', 'Aguardando Confirmação'
  // Controle de entrega do animal
  final String? tipoEntrega; // 'Taxi Dog' ou 'Cliente busca' ou null
  final double? valorTaxiDog; // Valor cobrado pelo taxi dog
  final String? bairroEntrega; // Bairro para cálculo da taxa
  final String? pedidoId; // ID do pedido relacionado (se criado a partir de um pedido)
  final String? numeroPedido; // Número do pedido (SRV-0001, etc.) para exibição
  final bool recebido; // Se o serviço já foi recebido/pago
  final DateTime? dataRecebimento; // Data/hora do recebimento
  final List<ItemMaterial> materiais; // Materiais/vacinas do agendamento
  final String? clienteNome; // Nome do cliente (para agendamentos online/convidados)
  final String? clienteTelefone; // Telefone do cliente (para consulta online)
  final String? petNome; // Nome do pet (para agendamentos online/convidados)
  final String? endereco; // Rua/Logradouro para Taxi Dog
  final String? numeroEndereco; // Número para Taxi Dog
  final String? complemento; // Complemento para Taxi Dog
  final String? pontoReferencia; // Ponto de referência para Taxi Dog
  final DateTime createdAt;
  final DateTime updatedAt;

  AgendamentoServico({
    required this.id,
    required this.numero,
    this.servicoId,
    this.servico,
    this.clienteId,
    this.cliente,
    this.petId,
    this.pet,
    required this.dataAgendamento,
    this.duracaoMinutos = 60, // Padrão: 1 hora
    this.observacoes,
    this.status = 'Agendado',
    this.tipoEntrega,
    this.valorTaxiDog,
    this.bairroEntrega,
    this.pedidoId,
    this.numeroPedido,
    this.recebido = false,
    this.dataRecebimento,
    this.clienteNome,
    this.clienteTelefone,
    this.petNome,
    this.endereco,
    this.numeroEndereco,
    this.complemento,
    this.pontoReferencia,
    List<ItemMaterial>? materiais,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : materiais = materiais ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Data/hora de término estimado
  DateTime get dataTermino => dataAgendamento.add(Duration(minutes: duracaoMinutos));

  /// Obtém o nome do serviço (do objeto servico ou nome direto se disponível)
  String? get servicoNome => servico?.nome;

  /// Verifica se o agendamento está ativo (não cancelado ou aguardando confirmação)
  bool get isAtivo => status != 'Cancelado' && status != 'Aguardando Confirmação';

  /// Verifica se o agendamento está aguardando confirmação
  bool get isAguardandoConfirmacao => status == 'Aguardando Confirmação';

  /// Verifica se o agendamento está em andamento
  bool get isEmAndamento => status == 'Em Andamento';

  /// Verifica se o agendamento está concluído
  bool get isConcluido => status == 'Concluído';

  /// Verifica se o agendamento está cancelado
  bool get isCancelado => status == 'Cancelado';

  /// Verifica se há conflito de horário com outro agendamento
  bool temConflito(AgendamentoServico outro) {
    if (id == outro.id) return false; // Mesmo agendamento
    if (!isAtivo || !outro.isAtivo) return false; // Um deles está cancelado
    
    // Verificar se os horários se sobrepõem (incluindo casos de borda)
    final outroTermino = outro.dataTermino;
    
    // Conflito ocorre se:
    // - O início deste agendamento está dentro do horário do outro
    // - O término deste agendamento está dentro do horário do outro
    // - Este agendamento engloba completamente o outro
    
    final inicioDentro = (dataAgendamento.isAfter(outro.dataAgendamento) || dataAgendamento.isAtSameMomentAs(outro.dataAgendamento)) &&
                        dataAgendamento.isBefore(outroTermino);
    
    final terminoDentro = dataTermino.isAfter(outro.dataAgendamento) &&
                         (dataTermino.isBefore(outroTermino) || dataTermino.isAtSameMomentAs(outroTermino));
    
    final englobaCompleto = dataAgendamento.isBefore(outro.dataAgendamento) && dataTermino.isAfter(outroTermino);
    
    return inicioDentro || terminoDentro || englobaCompleto;
  }

  AgendamentoServico copyWith({
    String? id,
    String? numero,
    String? servicoId,
    Servico? servico,
    String? clienteId,
    Cliente? cliente,
    String? petId,
    Pet? pet,
    DateTime? dataAgendamento,
    int? duracaoMinutos,
    String? observacoes,
    String? status,
    String? tipoEntrega,
    double? valorTaxiDog,
    String? bairroEntrega,
    String? pedidoId,
    String? numeroPedido,
    bool? recebido,
    DateTime? dataRecebimento,
    List<ItemMaterial>? materiais,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clienteNome,
    String? clienteTelefone,
    String? petNome,
    String? endereco,
    String? numeroEndereco,
    String? complemento,
    String? pontoReferencia,
  }) {
    return AgendamentoServico(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      servicoId: servicoId ?? this.servicoId,
      servico: servico ?? this.servico,
      clienteId: clienteId ?? this.clienteId,
      cliente: cliente ?? this.cliente,
      petId: petId ?? this.petId,
      pet: pet ?? this.pet,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      observacoes: observacoes ?? this.observacoes,
      status: status ?? this.status,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      valorTaxiDog: valorTaxiDog ?? this.valorTaxiDog,
      bairroEntrega: bairroEntrega ?? this.bairroEntrega,
      pedidoId: pedidoId ?? this.pedidoId,
      numeroPedido: numeroPedido ?? this.numeroPedido,
      recebido: recebido ?? this.recebido,
      dataRecebimento: dataRecebimento ?? this.dataRecebimento,
      materiais: materiais ?? this.materiais,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      petNome: petNome ?? this.petNome,
      endereco: endereco ?? this.endereco,
      numeroEndereco: numeroEndereco ?? this.numeroEndereco,
      complemento: complemento ?? this.complemento,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'servicoId': servicoId,
      'clienteId': clienteId,
      'petId': petId,
      'dataAgendamento': dataAgendamento.toIso8601String(),
      'duracaoMinutos': duracaoMinutos,
      'observacoes': observacoes,
      'status': status,
      'tipoEntrega': tipoEntrega,
      'valorTaxiDog': valorTaxiDog,
      'bairroEntrega': bairroEntrega,
      'pedidoId': pedidoId,
      'numeroPedido': numeroPedido,
      'recebido': recebido,
      'dataRecebimento': dataRecebimento?.toIso8601String(),
      'clienteNome': clienteNome,
      'clienteTelefone': clienteTelefone,
      'petNome': petNome,
      'endereco': endereco,
      'numeroEndereco': numeroEndereco,
      'complemento': complemento,
      'pontoReferencia': pontoReferencia,
      'pet': pet?.toMap(), // Incluir objeto pet para evitar perda de dados online
      'materiais': materiais.map((m) => m.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }



  factory AgendamentoServico.fromMap(Map<String, dynamic> map) {
    return AgendamentoServico(
      id: map['id']?.toString() ?? '',
      numero: map['numero']?.toString() ?? 'AGD-0000',
      servicoId: map['servicoId']?.toString(),
      clienteId: map['clienteId']?.toString(),
      petId: map['petId']?.toString(),
      dataAgendamento: DateParser.parse(map['dataAgendamento']),
      duracaoMinutos: map['duracaoMinutos'] ?? 60,
      observacoes: map['observacoes']?.toString(),
      status: map['status']?.toString() ?? 'Agendado',
      tipoEntrega: map['tipoEntrega']?.toString(),
      valorTaxiDog: (map['valorTaxiDog'] as num?)?.toDouble(),
      bairroEntrega: map['bairroEntrega']?.toString(),
      pedidoId: map['pedidoId']?.toString(),
      numeroPedido: map['numeroPedido']?.toString(),
      recebido: (map['recebido'] as bool?) ?? false,
      dataRecebimento: map['dataRecebimento'] != null 
          ? DateParser.parse(map['dataRecebimento']) 
          : null,
      materiais: map['materiais'] != null && map['materiais'] is List
          ? (map['materiais'] as List).map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : <ItemMaterial>[],
      createdAt: DateParser.parse(map['createdAt']),
      updatedAt: DateParser.parse(map['updatedAt']),
      clienteNome: map['clienteNome']?.toString(),
      clienteTelefone: map['clienteTelefone']?.toString(),
      petNome: map['petNome']?.toString(),
      endereco: map['endereco']?.toString(),
      numeroEndereco: map['numeroEndereco']?.toString(),
      complemento: map['complemento']?.toString(),
      pontoReferencia: map['pontoReferencia']?.toString(),
      pet: map['pet'] != null ? Pet.fromMap(Map<String, dynamic>.from(map['pet'])) : null,
    );
  }
}


import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/servico.dart';

/// Modelo para representar um agendamento de serviço
class AgendamentoServico {
  final String id;
  final String servicoId;
  final Servico? servico; // Referência ao serviço (pode ser null se serviço foi deletado)
  final String? clienteId;
  final Cliente? cliente; // Referência ao cliente
  final DateTime dataAgendamento; // Data e hora do agendamento
  final int duracaoMinutos; // Duração estimada do serviço em minutos
  final String? observacoes;
  final String status; // 'Agendado', 'Em Andamento', 'Concluído', 'Cancelado'
  final DateTime createdAt;
  final DateTime updatedAt;

  AgendamentoServico({
    required this.id,
    required this.servicoId,
    this.servico,
    this.clienteId,
    this.cliente,
    required this.dataAgendamento,
    this.duracaoMinutos = 60, // Padrão: 1 hora
    this.observacoes,
    this.status = 'Agendado',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Data/hora de término estimado
  DateTime get dataTermino => dataAgendamento.add(Duration(minutes: duracaoMinutos));

  /// Verifica se o agendamento está ativo (não cancelado)
  bool get isAtivo => status != 'Cancelado';

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
    
    // Verificar se os horários se sobrepõem
    return (dataAgendamento.isBefore(outro.dataTermino) && 
            dataTermino.isAfter(outro.dataAgendamento));
  }

  AgendamentoServico copyWith({
    String? id,
    String? servicoId,
    Servico? servico,
    String? clienteId,
    Cliente? cliente,
    DateTime? dataAgendamento,
    int? duracaoMinutos,
    String? observacoes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgendamentoServico(
      id: id ?? this.id,
      servicoId: servicoId ?? this.servicoId,
      servico: servico ?? this.servico,
      clienteId: clienteId ?? this.clienteId,
      cliente: cliente ?? this.cliente,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      observacoes: observacoes ?? this.observacoes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'servicoId': servicoId,
      'clienteId': clienteId,
      'dataAgendamento': dataAgendamento.toIso8601String(),
      'duracaoMinutos': duracaoMinutos,
      'observacoes': observacoes,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AgendamentoServico.fromMap(Map<String, dynamic> map) {
    return AgendamentoServico(
      id: map['id'] ?? '',
      servicoId: map['servicoId'] ?? '',
      clienteId: map['clienteId'],
      dataAgendamento: DateTime.parse(map['dataAgendamento']),
      duracaoMinutos: map['duracaoMinutos'] ?? 60,
      observacoes: map['observacoes'],
      status: map['status'] ?? 'Agendado',
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt']) 
          : DateTime.now(),
    );
  }
}



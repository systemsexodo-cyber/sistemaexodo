import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/servico.dart';

class OrdemServico {
  final String id;
  final Cliente cliente;
  final List<Servico> servicos;
  final DateTime dataInicio;
  final DateTime dataAgendamento;
  final double valorTotal;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrdemServico({
    required this.id,
    required this.cliente,
    required this.servicos,
    required this.dataInicio,
    required this.dataAgendamento,
    required this.valorTotal,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente': cliente.toMap(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'dataInicio': dataInicio.toIso8601String(),
      'dataAgendamento': dataAgendamento.toIso8601String(),
      'valorTotal': valorTotal,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory OrdemServico.fromMap(Map<String, dynamic> map) {
    return OrdemServico(
      id: map['id'] ?? '',
      cliente: Cliente.fromMap(map['cliente']),
      servicos: (map['servicos'] as List).map((s) => Servico.fromMap(s)).toList(),
      dataInicio: DateTime.parse(map['dataInicio']),
      dataAgendamento: DateTime.parse(map['dataAgendamento']),
      valorTotal: (map['valorTotal'] ?? 0.0).toDouble(),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  OrdemServico copyWith({
    String? id,
    Cliente? cliente,
    List<Servico>? servicos,
    DateTime? dataInicio,
    DateTime? dataAgendamento,
    double? valorTotal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrdemServico(
      id: id ?? this.id,
      cliente: cliente ?? this.cliente,
      servicos: servicos ?? this.servicos,
      dataInicio: dataInicio ?? this.dataInicio,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      valorTotal: valorTotal ?? this.valorTotal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

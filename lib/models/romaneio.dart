import 'package:sistema_exodo_novo/models/entrega.dart';

enum StatusRomaneio {
  emPreparacao, // Criando o romaneio
  emEntrega,    // Motorista saiu com a carga
  concluido,    // Todas as entregas finalizadas
  cancelado     // Romaneio cancelado
}

class Romaneio {
  final String id;
  final String numero; // ROM-0001
  final DateTime dataCriacao;
  final DateTime? dataSaida;
  final DateTime? dataRetorno;
  
  final String? motoristaId;
  final String? motoristaNome;
  final String? veiculoId;
  final String? veiculoPlaca;
  
  final StatusRomaneio status;
  final List<String> entregaIds; // IDs das entregas (ou pedidos) incluídos
  final List<String> pedidosEntregues; // IDs dos pedidos que já foram marcados como entregues
  final String? observacoes;
  
  final double pesoTotal;
  final double valorTotal;

  Romaneio({
    required this.id,
    required this.numero,
    required this.dataCriacao,
    this.dataSaida,
    this.dataRetorno,
    this.motoristaId,
    this.motoristaNome,
    this.veiculoId,
    this.veiculoPlaca,
    this.status = StatusRomaneio.emPreparacao,
    required this.entregaIds,
    this.pedidosEntregues = const [],
    this.observacoes,
    this.pesoTotal = 0,
    this.valorTotal = 0,
  });

  factory Romaneio.fromMap(Map<String, dynamic> map) {
    return Romaneio(
      id: map['id']?.toString() ?? '',
      numero: map['numero'] ?? '',
      dataCriacao: DateTime.parse(map['dataCriacao']?.toString() ?? DateTime.now().toIso8601String()),
      dataSaida: map['dataSaida'] != null ? (map['dataSaida'] is DateTime ? map['dataSaida'] : DateTime.parse(map['dataSaida'].toString())) : null,
      dataRetorno: map['dataRetorno'] != null ? (map['dataRetorno'] is DateTime ? map['dataRetorno'] : DateTime.parse(map['dataRetorno'].toString())) : null,
      motoristaId: map['motoristaId'],
      motoristaNome: map['motoristaNome'],
      veiculoId: map['veiculoId'],
      veiculoPlaca: map['veiculoPlaca'],
      status: StatusRomaneio.values.firstWhere(
        (s) => s.name == (map['status'] ?? 'emPreparacao'),
        orElse: () => StatusRomaneio.emPreparacao,
      ),
      entregaIds: List<String>.from(map['entregaIds'] ?? []),
      pedidosEntregues: List<String>.from(map['pedidosEntregues'] ?? []),
      observacoes: map['observacoes'],
      pesoTotal: double.tryParse(map['pesoTotal']?.toString() ?? '') ?? 0.0,
      valorTotal: double.tryParse(map['valorTotal']?.toString() ?? '') ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'dataCriacao': dataCriacao.toIso8601String(),
      'dataSaida': dataSaida?.toIso8601String(),
      'dataRetorno': dataRetorno?.toIso8601String(),
      'motoristaId': motoristaId,
      'motoristaNome': motoristaNome,
      'veiculoId': veiculoId,
      'veiculoPlaca': veiculoPlaca,
      'status': status.name,
      'entregaIds': entregaIds,
      'pedidosEntregues': pedidosEntregues,
      'observacoes': observacoes,
      'pesoTotal': pesoTotal,
      'valorTotal': valorTotal,
    };
  }

  Romaneio copyWith({
    String? id,
    String? numero,
    DateTime? dataCriacao,
    DateTime? dataSaida,
    DateTime? dataRetorno,
    String? motoristaId,
    String? motoristaNome,
    String? veiculoId,
    String? veiculoPlaca,
    StatusRomaneio? status,
    List<String>? entregaIds,
    List<String>? pedidosEntregues,
    String? observacoes,
    double? pesoTotal,
    double? valorTotal,
  }) {
    return Romaneio(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataSaida: dataSaida ?? this.dataSaida,
      dataRetorno: dataRetorno ?? this.dataRetorno,
      motoristaId: motoristaId ?? this.motoristaId,
      motoristaNome: motoristaNome ?? this.motoristaNome,
      veiculoId: veiculoId ?? this.veiculoId,
      veiculoPlaca: veiculoPlaca ?? this.veiculoPlaca,
      status: status ?? this.status,
      entregaIds: entregaIds ?? this.entregaIds,
      pedidosEntregues: pedidosEntregues ?? this.pedidosEntregues,
      observacoes: observacoes ?? this.observacoes,
      pesoTotal: pesoTotal ?? this.pesoTotal,
      valorTotal: valorTotal ?? this.valorTotal,
    );
  }
}

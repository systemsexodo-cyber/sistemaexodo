/// Informações de entrega do pedido
class DeliveryInfo {
  final String id;
  final String enderecoId; // ID do endereço do cliente selecionado
  final String logradouro;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String? cep;
  final double taxaEntrega;
  final double valorParaTroco; // Valor informado pelo cliente para troco
  final String status; // Pendente, Em Preparo, Em Transito, Entregue, Cancelado
  final String? motoristaId;
  final String? motoristaNome;
  final DateTime? dataSaida;
  final DateTime? dataEntrega;
  final DateTime? dataPedido;
  final String? observacoes;
  final String? previsaoEntrega; // Previsão de entrega informada (ex: "30-45 min" ou "18:30")

  DeliveryInfo({
    required this.id,
    required this.enderecoId,
    required this.logradouro,
    required this.numero,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.cep,
    this.taxaEntrega = 0.0,
    this.valorParaTroco = 0.0,
    this.status = 'Pendente',
    this.motoristaId,
    this.motoristaNome,
    this.dataSaida,
    this.dataEntrega,
    this.dataPedido,
    this.observacoes,
    this.previsaoEntrega,
  });

  String get enderecoCompleto => '$logradouro, $numero - $bairro, $cidade/$uf';

  factory DeliveryInfo.fromMap(Map<String, dynamic> map) {
    return DeliveryInfo(
      id: map['id']?.toString() ?? '',
      enderecoId: map['enderecoId']?.toString() ?? '',
      logradouro: map['logradouro']?.toString() ?? '',
      numero: map['numero']?.toString() ?? '',
      bairro: map['bairro']?.toString() ?? '',
      cidade: map['cidade']?.toString() ?? '',
      uf: map['uf']?.toString() ?? '',
      cep: map['cep']?.toString(),
      taxaEntrega: (map['taxaEntrega'] as num? ?? 0.0).toDouble(),
      valorParaTroco: (map['valorParaTroco'] as num? ?? 0.0).toDouble(),
      status: map['status']?.toString() ?? 'Pendente',
      motoristaId: map['motoristaId']?.toString(),
      motoristaNome: map['motoristaNome']?.toString() ?? map['entregadorNome']?.toString(), // Fallback
      dataSaida: map['dataSaida'] != null ? DateTime.parse(map['dataSaida']) : null,
      dataEntrega: map['dataEntrega'] != null ? DateTime.parse(map['dataEntrega']) : null,
      dataPedido: map['dataPedido'] != null ? DateTime.parse(map['dataPedido']) : null,
      observacoes: map['observacoes']?.toString(),
      previsaoEntrega: map['previsaoEntrega']?.toString() ?? map['previsao_entrega']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'enderecoId': enderecoId,
      'logradouro': logradouro,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'cep': cep,
      'taxaEntrega': taxaEntrega,
      'valorParaTroco': valorParaTroco,
      'status': status,
      'motoristaId': motoristaId,
      'motoristaNome': motoristaNome,
      'dataSaida': dataSaida?.toIso8601String(),
      'dataEntrega': dataEntrega?.toIso8601String(),
      'dataPedido': dataPedido?.toIso8601String(),
      'observacoes': observacoes,
      'previsaoEntrega': previsaoEntrega,
    };
  }

  DeliveryInfo copyWith({
    String? id,
    String? enderecoId,
    String? logradouro,
    String? numero,
    String? bairro,
    String? cidade,
    String? uf,
    String? cep,
    double? taxaEntrega,
    double? valorParaTroco,
    String? status,
    String? motoristaId,
    String? motoristaNome,
    DateTime? dataSaida,
    DateTime? dataEntrega,
    DateTime? dataPedido,
    String? observacoes,
    String? previsaoEntrega,
  }) {
    return DeliveryInfo(
      id: id ?? this.id,
      enderecoId: enderecoId ?? this.enderecoId,
      logradouro: logradouro ?? this.logradouro,
      numero: numero ?? this.numero,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      uf: uf ?? this.uf,
      cep: cep ?? this.cep,
      taxaEntrega: taxaEntrega ?? this.taxaEntrega,
      valorParaTroco: valorParaTroco ?? this.valorParaTroco,
      status: status ?? this.status,
      motoristaId: motoristaId ?? this.motoristaId,
      motoristaNome: motoristaNome ?? this.motoristaNome,
      dataSaida: dataSaida ?? this.dataSaida,
      dataEntrega: dataEntrega ?? this.dataEntrega,
      dataPedido: dataPedido ?? this.dataPedido,
      observacoes: observacoes ?? this.observacoes,
      previsaoEntrega: previsaoEntrega ?? this.previsaoEntrega,
    );
  }
}

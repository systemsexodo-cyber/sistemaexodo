class ItemServico {
  final String id;
  final String descricao;
  final double valor;
  final double valorAdicional;
  final String? descricaoAdicional;
  final DateTime? dataAgendamento;
  final int? duracaoMinutos;
  final String? funcionarioId; // ID do funcionário que irá fazer o serviço
  final double valorComissao; // Valor da comissão para o funcionário

  ItemServico({
    required this.id,
    required this.descricao,
    required this.valor,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
    this.dataAgendamento,
    this.duracaoMinutos,
    this.funcionarioId,
    this.valorComissao = 0.0,
  });

  bool get temAgendamento => dataAgendamento != null;

  factory ItemServico.fromMap(Map<String, dynamic> map) {
    return ItemServico(
      id: map['id'] ?? '',
      descricao: map['descricao'] ?? '',
      valor: (map['valor'] ?? 0).toDouble(),
      valorAdicional: (map['valorAdicional'] ?? 0.0).toDouble(),
      descricaoAdicional: map['descricaoAdicional'],
      dataAgendamento: map['dataAgendamento'] != null
          ? DateTime.parse(map['dataAgendamento'] as String)
          : null,
      duracaoMinutos: map['duracaoMinutos'] as int?,
      funcionarioId: map['funcionarioId'] as String?,
      valorComissao: (map['valorComissao'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descricao': descricao,
      'valor': valor,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'dataAgendamento': dataAgendamento?.toIso8601String(),
      'duracaoMinutos': duracaoMinutos,
      'funcionarioId': funcionarioId,
      'valorComissao': valorComissao,
    };
  }
}

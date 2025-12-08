import 'item_material.dart';

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
  final List<ItemMaterial> materiais; // Lista de materiais que serão consumidos

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
    List<ItemMaterial>? materiais,
  }) : materiais = materiais ?? [];

  bool get temAgendamento => dataAgendamento != null;
  bool get temMateriais => materiais.isNotEmpty;

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
      materiais: map['materiais'] != null
          ? (map['materiais'] as List).map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : [],
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
      'materiais': materiais.map((m) => m.toMap()).toList(),
    };
  }

  ItemServico copyWith({
    String? id,
    String? descricao,
    double? valor,
    double? valorAdicional,
    String? descricaoAdicional,
    DateTime? dataAgendamento,
    int? duracaoMinutos,
    String? funcionarioId,
    double? valorComissao,
    List<ItemMaterial>? materiais,
  }) {
    return ItemServico(
      id: id ?? this.id,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      valorAdicional: valorAdicional ?? this.valorAdicional,
      descricaoAdicional: descricaoAdicional ?? this.descricaoAdicional,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      funcionarioId: funcionarioId ?? this.funcionarioId,
      valorComissao: valorComissao ?? this.valorComissao,
      materiais: materiais ?? this.materiais,
    );
  }
}

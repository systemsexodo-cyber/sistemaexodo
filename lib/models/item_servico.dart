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
  final String tipoComissao; // 'Porcentagem' ou 'Fixo'
  final double porcentagemComissao; // Porcentagem se for o caso
  final double valorComissao; // Valor final da comissão para o funcionário
  final List<ItemMaterial> materiais; // Lista de materiais que serão consumidos
  final String? observacao;
  // Controle de entrega do animal
  final String? tipoEntrega; // 'Taxi Dog' ou 'Cliente busca' ou null
  final double? valorTaxiDog; // Valor cobrado pelo taxi dog
  final String? bairroEntrega; // Bairro para cálculo da taxa
  final String? endereco; // Rua/Logradouro para Taxi Dog
  final String? numeroEndereco; // Número para Taxi Dog
  final String? complemento; // Complemento para Taxi Dog
  final String? pontoReferencia; // Ponto de referência para Taxi Dog

  ItemServico({
    required this.id,
    required this.descricao,
    required this.valor,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
    this.observacao,
    this.dataAgendamento,
    this.duracaoMinutos,
    this.funcionarioId,
    this.tipoComissao = 'Fixo',
    this.porcentagemComissao = 0.0,
    this.valorComissao = 0.0,
    List<ItemMaterial>? materiais,
    this.tipoEntrega,
    this.valorTaxiDog,
    this.bairroEntrega,
    this.endereco,
    this.numeroEndereco,
    this.complemento,
    this.pontoReferencia,
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
      observacao: map['observacao'],
      dataAgendamento: map['dataAgendamento'] != null
          ? DateTime.parse(map['dataAgendamento'] as String)
          : null,
      duracaoMinutos: map['duracaoMinutos'] as int?,
      funcionarioId: map['funcionarioId'] as String?,
      tipoComissao: map['tipoComissao']?.toString() ?? 'Fixo',
      porcentagemComissao: (map['porcentagemComissao'] ?? 0.0).toDouble(),
      valorComissao: (map['valorComissao'] ?? 0.0).toDouble(),
      materiais: map['materiais'] != null
          ? (map['materiais'] as List).map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : [],
      tipoEntrega: map['tipoEntrega'] as String?,
      valorTaxiDog: map['valorTaxiDog']?.toDouble(),
      bairroEntrega: map['bairroEntrega'] as String?,
      endereco: map['endereco'] as String?,
      numeroEndereco: map['numeroEndereco'] as String?,
      complemento: map['complemento'] as String?,
      pontoReferencia: map['pontoReferencia'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descricao': descricao,
      'valor': valor,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'observacao': observacao,
      'dataAgendamento': dataAgendamento?.toIso8601String(),
      'duracaoMinutos': duracaoMinutos,
      'funcionarioId': funcionarioId,
      'tipoComissao': tipoComissao,
      'porcentagemComissao': porcentagemComissao,
      'valorComissao': valorComissao,
      'materiais': materiais.map((m) => m.toMap()).toList(),
      'tipoEntrega': tipoEntrega,
      'valorTaxiDog': valorTaxiDog,
      'bairroEntrega': bairroEntrega,
      'endereco': endereco,
      'numeroEndereco': numeroEndereco,
      'complemento': complemento,
      'pontoReferencia': pontoReferencia,
    };
  }

  ItemServico copyWith({
    String? id,
    String? descricao,
    double? valor,
    double? valorAdicional,
    String? descricaoAdicional,
    String? observacao,
    DateTime? dataAgendamento,
    int? duracaoMinutos,
    String? funcionarioId,
    String? tipoComissao,
    double? porcentagemComissao,
    double? valorComissao,
    List<ItemMaterial>? materiais,
    String? tipoEntrega,
    double? valorTaxiDog,
    String? bairroEntrega,
    String? endereco,
    String? numeroEndereco,
    String? complemento,
    String? pontoReferencia,
  }) {
    return ItemServico(
      id: id ?? this.id,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      valorAdicional: valorAdicional ?? this.valorAdicional,
      descricaoAdicional: descricaoAdicional ?? this.descricaoAdicional,
      observacao: observacao ?? this.observacao,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      funcionarioId: funcionarioId ?? this.funcionarioId,
      tipoComissao: tipoComissao ?? this.tipoComissao,
      porcentagemComissao: porcentagemComissao ?? this.porcentagemComissao,
      valorComissao: valorComissao ?? this.valorComissao,
      materiais: materiais ?? this.materiais,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      valorTaxiDog: valorTaxiDog ?? this.valorTaxiDog,
      bairroEntrega: bairroEntrega ?? this.bairroEntrega,
      endereco: endereco ?? this.endereco,
      numeroEndereco: numeroEndereco ?? this.numeroEndereco,
      complemento: complemento ?? this.complemento,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
    );
  }
}

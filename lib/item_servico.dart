class ItemServico {
  final String id;
  final String nome;
  final double preco;
  final double valorAdicional;
  final String? descricaoAdicional;
  final double desconto;
  final String? descricaoDesconto;
  final DateTime? dataInicio;
  final DateTime? dataFim;

  ItemServico({
    required this.id,
    required this.nome,
    required this.preco,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
    this.desconto = 0.0,
    this.descricaoDesconto,
    this.dataInicio,
    this.dataFim,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'desconto': desconto,
      'descricaoDesconto': descricaoDesconto,
      'dataInicio': dataInicio?.toIso8601String(),
      'dataFim': dataFim?.toIso8601String(),
    };
  }

  factory ItemServico.fromMap(Map<String, dynamic> map) {
    return ItemServico(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      preco: (map['preco'] ?? 0.0).toDouble(),
      valorAdicional: (map['valorAdicional'] ?? 0.0).toDouble(),
      descricaoAdicional: map['descricaoAdicional'],
      desconto: (map['desconto'] ?? 0.0).toDouble(),
      descricaoDesconto: map['descricaoDesconto'],
      dataInicio: map['dataInicio'] != null ? DateTime.parse(map['dataInicio']) : null,
      dataFim: map['dataFim'] != null ? DateTime.parse(map['dataFim']) : null,
    );
  }

  @override
  String toString() => 'ItemServico(nome: $nome, preco: $preco, adicional: $valorAdicional, dataInicio: $dataInicio, dataFim: $dataFim)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemServico && other.id == id);

  @override
  int get hashCode => id.hashCode;
}


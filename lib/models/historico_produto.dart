import 'package:uuid/uuid.dart';

class HistoricoProduto {
  final String id;
  final String produtoId;
  final String produtoNome;
  final String acao; // 'criacao', 'atualizacao', 'exclusao'
  final String campoAlterado; // 'preco', 'estoque', 'nome', ou 'varios'
  final String valorAntigo;
  final String valorNovo;
  final String usuario;
  final DateTime dataAlteracao;

  HistoricoProduto({
    String? id,
    required this.produtoId,
    required this.produtoNome,
    required this.acao,
    required this.campoAlterado,
    required this.valorAntigo,
    required this.valorNovo,
    required this.usuario,
    DateTime? dataAlteracao,
  })  : id = id ?? const Uuid().v4(),
        dataAlteracao = dataAlteracao ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'acao': acao,
      'campo_alterado': campoAlterado,
      'valor_antigo': valorAntigo,
      'valor_novo': valorNovo,
      'usuario': usuario,
      'data_alteracao': dataAlteracao.toIso8601String(),
    };
  }

  factory HistoricoProduto.fromMap(Map<String, dynamic> map) {
    return HistoricoProduto(
      id: map['id']?.toString() ?? '',
      produtoId: map['produto_id'] as String? ?? '',
      produtoNome: map['produto_nome'] as String? ?? 'Desconhecido',
      acao: map['acao'] as String? ?? 'atualizacao',
      campoAlterado: map['campo_alterado'] as String? ?? 'varios',
      valorAntigo: map['valor_antigo']?.toString() ?? '',
      valorNovo: map['valor_novo']?.toString() ?? '',
      usuario: map['usuario'] as String? ?? 'Sistema',
      dataAlteracao: map['data_alteracao'] != null 
          ? DateTime.parse(map['data_alteracao'] as String) 
          : DateTime.now(),
    );
  }
}

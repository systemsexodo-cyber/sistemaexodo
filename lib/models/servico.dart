import 'package:sistema_exodo_novo/utils/date_parser.dart';
import 'item_material.dart';


class Servico {
  final String id;
  final String nome;
  final String? descricao;
  final double preco;
  final double valorAdicional;
  final String? descricaoAdicional;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ItemMaterial> materiais; // Lista de materiais padrão do serviço
  final int? duracaoPadraoMinutos; // Duração estimada em minutos
  final int? intervaloMinutos; // Intervalo/Pausa após o serviço

  Servico({
    required this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
    required this.createdAt,
    required this.updatedAt,
    List<ItemMaterial>? materiais,
    this.duracaoPadraoMinutos,
    this.intervaloMinutos,
  }) : materiais = materiais ?? [];

  // Getter para o preço total (base + adicional)
  double get precoTotal => preco + valorAdicional;

  // Verifica se tem valor adicional
  bool get temAdicional => valorAdicional > 0;
  
  // Verifica se tem materiais
  bool get temMateriais => materiais.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'materiais': materiais.map((m) => m.toMap()).toList(),
      'duracaoPadraoMinutos': duracaoPadraoMinutos,
      'intervaloMinutos': intervaloMinutos,
    };
  }


  factory Servico.fromMap(Map<String, dynamic> map) {

    return Servico(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      descricao: map['descricao']?.toString(),
      preco: (map['preco'] as num? ?? 0).toDouble(),
      valorAdicional: (map['valorAdicional'] as num? ?? 0).toDouble(),
      descricaoAdicional: map['descricaoAdicional']?.toString(),
      createdAt: DateParser.parse(map['createdAt']),
      updatedAt: DateParser.parse(map['updatedAt']),
      materiais: map['materiais'] != null
          ? (map['materiais'] as List).map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : [],
      duracaoPadraoMinutos: map['duracaoPadraoMinutos'] as int?,
      intervaloMinutos: map['intervaloMinutos'] as int?,
    );
  }


  Servico copyWith({
    String? id,
    String? nome,
    String? descricao,
    double? preco,
    double? valorAdicional,
    String? descricaoAdicional,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ItemMaterial>? materiais,
    int? duracaoPadraoMinutos,
    int? intervaloMinutos,
  }) {
    return Servico(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      valorAdicional: valorAdicional ?? this.valorAdicional,
      descricaoAdicional: descricaoAdicional ?? this.descricaoAdicional,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      materiais: materiais ?? this.materiais,
      duracaoPadraoMinutos: duracaoPadraoMinutos ?? this.duracaoPadraoMinutos,
      intervaloMinutos: intervaloMinutos ?? this.intervaloMinutos,
    );
  }
}

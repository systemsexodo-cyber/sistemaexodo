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
  final String tipoComissao; // 'Porcentagem' ou 'Fixo'
  final double porcentagemComissao;
  final double valorComissao;

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
    this.tipoComissao = 'Porcentagem',
    this.porcentagemComissao = 0.0,
    this.valorComissao = 0.0,
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
      'valor_adicional': valorAdicional,
      'descricao_adicional': descricaoAdicional,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'materiais': materiais.map((m) => m.toMap()).toList(),
      'duracao_padrao_minutos': duracaoPadraoMinutos,
      'intervalo_minutos': intervaloMinutos,
      'tipo_comissao': tipoComissao,
      'porcentagem_comissao': porcentagemComissao,
      'valor_comissao': valorComissao,
    };
  }


  factory Servico.fromMap(Map<String, dynamic> map) {
    // Helpers para suportar camelCase (localStorage) e snake_case (Supabase)
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }
    String? getStr(String camel, String snake) => get<String>(camel, snake);
    num? getNum(String camel, String snake) {
      final val = get<dynamic>(camel, snake);
      if (val == null) return null;
      if (val is num) return val;
      if (val is String) return num.tryParse(val);
      return null;
    }
    List? getList(String camel, String snake) => get<List>(camel, snake);

    return Servico(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      descricao: map['descricao']?.toString(),
      preco: (getNum('preco', 'preco') ?? 0.0).toDouble(),
      valorAdicional: (getNum('valorAdicional', 'valor_adicional') ?? 0).toDouble(),
      descricaoAdicional: getStr('descricaoAdicional', 'descricao_adicional'),
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
      materiais: getList('materiais', 'materiais') != null
          ? getList('materiais', 'materiais')!.map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : [],
      duracaoPadraoMinutos: getNum('duracaoPadraoMinutos', 'duracao_padrao_minutos')?.toInt(),
      intervaloMinutos: getNum('intervaloMinutos', 'intervalo_minutos')?.toInt(),
      tipoComissao: getStr('tipoComissao', 'tipo_comissao') ?? 'Porcentagem',
      porcentagemComissao: getNum('porcentagemComissao', 'porcentagem_comissao')?.toDouble() ?? 0.0,
      valorComissao: getNum('valorComissao', 'valor_comissao')?.toDouble() ?? 0.0,
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
    String? tipoComissao,
    double? porcentagemComissao,
    double? valorComissao,
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
      tipoComissao: tipoComissao ?? this.tipoComissao,
      porcentagemComissao: porcentagemComissao ?? this.porcentagemComissao,
      valorComissao: valorComissao ?? this.valorComissao,
    );
  }
}

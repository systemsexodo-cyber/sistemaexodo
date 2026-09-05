/// Departamento (setor) de preparação — ex.: Bar, Cozinha, Sobremesas.
///
/// O departamento é a área da produção onde o item é preparado. Ele é
/// INDEPENDENTE da configuração de impressora: cada departamento PODE ter
/// sua própria impressora associada (ex.: a impressora da cozinha), mas isso
/// é uma configuração separada da escolha do departamento em si.
class Departamento {
  final String id;
  final String nome;
  final String? cor; // Cor para exibição na UI (hex, ex: '#FF5722')
  final String? icone; // Ícone opcional (ex: 'restaurant', 'local_bar')
  // Impressora física associada a ESTE departamento (configuração separada).
  final String? impressoraProducao;
  // Outras impressoras/setores onde também imprimir (multi-seleção).
  final List<String> impressoraProducaoExtra;
  final int ordem; // Ordem de exibição

  Departamento({
    required this.id,
    required this.nome,
    this.cor,
    this.icone,
    this.impressoraProducao,
    this.impressoraProducaoExtra = const [],
    this.ordem = 0,
  });

  factory Departamento.fromMap(Map<String, dynamic> map) {
    return Departamento(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      cor: map['cor'] as String?,
      icone: map['icone'] as String?,
      impressoraProducao: (map['impressoraProducao'] ?? map['impressora_producao']) as String?,
      impressoraProducaoExtra: ((map['impressoraProducaoExtra'] ?? map['impressora_producao_extra']) as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      ordem: (map['ordem'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'cor': cor,
      'icone': icone,
      'impressora_producao': impressoraProducao,
      'impressora_producao_extra': impressoraProducaoExtra,
      'ordem': ordem,
    };
  }

  Departamento copyWith({
    String? id,
    String? nome,
    String? cor,
    String? icone,
    String? impressoraProducao,
    List<String>? impressoraProducaoExtra,
    int? ordem,
  }) {
    return Departamento(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      cor: cor ?? this.cor,
      icone: icone ?? this.icone,
      impressoraProducao: impressoraProducao ?? this.impressoraProducao,
      impressoraProducaoExtra: impressoraProducaoExtra ?? this.impressoraProducaoExtra,
      ordem: ordem ?? this.ordem,
    );
  }
}

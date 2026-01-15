/// Modelo para representar um pet (animal de estimação)
class Pet {
  final String id;
  final String nome;
  final String? especie; // Ex: Cachorro, Gato, etc
  final String? raca;
  final DateTime? dataNascimento;
  final String? tamanho; // Ex: Pequeno, Médio, Grande
  final double? peso; // Peso em kg
  final String? cor;
  final String? sexo; // M ou F
  final String? observacoes;
  final String? fotoPath; // Caminho da foto do pet
  final DateTime createdAt;
  final DateTime updatedAt;

  Pet({
    required this.id,
    required this.nome,
    this.especie,
    this.raca,
    this.dataNascimento,
    this.tamanho,
    this.peso,
    this.cor,
    this.sexo,
    this.observacoes,
    this.fotoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Idade do pet em anos
  int? get idadeAnos {
    if (dataNascimento == null) return null;
    final hoje = DateTime.now();
    var idade = hoje.year - dataNascimento!.year;
    if (hoje.month < dataNascimento!.month ||
        (hoje.month == dataNascimento!.month && hoje.day < dataNascimento!.day)) {
      idade--;
    }
    return idade;
  }

  /// Idade formatada
  String get idadeFormatada {
    if (dataNascimento == null) return 'Não informado';
    final anos = idadeAnos;
    if (anos == null) return 'Não informado';
    if (anos == 0) {
      final meses = DateTime.now().month - dataNascimento!.month;
      return '$meses mês(es)';
    }
    return '$anos ano(s)';
  }

  factory Pet.fromMap(Map<String, dynamic> map) {
    return Pet(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      especie: map['especie'],
      raca: map['raca'],
      dataNascimento: map['dataNascimento'] != null
          ? DateTime.parse(map['dataNascimento'] as String)
          : null,
      tamanho: map['tamanho'],
      peso: map['peso']?.toDouble(),
      cor: map['cor'],
      sexo: map['sexo'],
      observacoes: map['observacoes'],
      fotoPath: map['fotoPath'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'especie': especie,
      'raca': raca,
      'dataNascimento': dataNascimento?.toIso8601String(),
      'tamanho': tamanho,
      'peso': peso,
      'cor': cor,
      'sexo': sexo,
      'observacoes': observacoes,
      'fotoPath': fotoPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Pet copyWith({
    String? id,
    String? nome,
    String? especie,
    String? raca,
    DateTime? dataNascimento,
    String? tamanho,
    double? peso,
    String? cor,
    String? sexo,
    String? observacoes,
    String? fotoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pet(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      especie: especie ?? this.especie,
      raca: raca ?? this.raca,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      tamanho: tamanho ?? this.tamanho,
      peso: peso ?? this.peso,
      cor: cor ?? this.cor,
      sexo: sexo ?? this.sexo,
      observacoes: observacoes ?? this.observacoes,
      fotoPath: fotoPath ?? this.fotoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}






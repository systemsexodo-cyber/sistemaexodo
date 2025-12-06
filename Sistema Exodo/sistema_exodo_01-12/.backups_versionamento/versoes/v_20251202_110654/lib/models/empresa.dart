/// Modelo para representar uma empresa
class Empresa {
  final String id;
  final String razaoSocial;
  final String? nomeFantasia;
  final String? cnpj;
  final String? inscricaoEstadual;
  final String? inscricaoMunicipal;
  
  // Contato
  final String? email;
  final String? telefone;
  final String? celular;
  final String? site;
  
  // Endereço
  final String? endereco;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final String? cep;
  
  // Configurações
  final String? logoUrl;
  final String? corPrimaria; // Cor principal da empresa (hex)
  final String? corSecundaria; // Cor secundária da empresa (hex)
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Configurações do sistema
  final Map<String, dynamic>? configuracoes; // Configurações específicas da empresa

  Empresa({
    required this.id,
    required this.razaoSocial,
    this.nomeFantasia,
    this.cnpj,
    this.inscricaoEstadual,
    this.inscricaoMunicipal,
    this.email,
    this.telefone,
    this.celular,
    this.site,
    this.endereco,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    this.cep,
    this.logoUrl,
    this.corPrimaria,
    this.corSecundaria,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
    this.configuracoes,
  });

  /// Retorna o nome de exibição (nome fantasia ou razão social)
  String get nomeExibicao => nomeFantasia ?? razaoSocial;

  /// Retorna o endereço completo formatado
  String get enderecoCompleto {
    final parts = <String>[];
    if (endereco != null && endereco!.isNotEmpty) {
      parts.add(endereco!);
      if (numero != null && numero!.isNotEmpty) {
        parts.add('nº $numero');
      }
      if (complemento != null && complemento!.isNotEmpty) {
        parts.add(complemento!);
      }
      if (bairro != null && bairro!.isNotEmpty) {
        parts.add(bairro!);
      }
      if (cidade != null && cidade!.isNotEmpty) {
        parts.add(cidade!);
      }
      if (estado != null && estado!.isNotEmpty) {
        parts.add(estado!);
      }
      if (cep != null && cep!.isNotEmpty) {
        parts.add('CEP: $cep');
      }
    }
    return parts.join(', ');
  }

  /// Cria uma cópia da empresa com campos atualizados
  Empresa copyWith({
    String? id,
    String? razaoSocial,
    String? nomeFantasia,
    String? cnpj,
    String? inscricaoEstadual,
    String? inscricaoMunicipal,
    String? email,
    String? telefone,
    String? celular,
    String? site,
    String? endereco,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? cep,
    String? logoUrl,
    String? corPrimaria,
    String? corSecundaria,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? configuracoes,
  }) {
    return Empresa(
      id: id ?? this.id,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      cnpj: cnpj ?? this.cnpj,
      inscricaoEstadual: inscricaoEstadual ?? this.inscricaoEstadual,
      inscricaoMunicipal: inscricaoMunicipal ?? this.inscricaoMunicipal,
      email: email ?? this.email,
      telefone: telefone ?? this.telefone,
      celular: celular ?? this.celular,
      site: site ?? this.site,
      endereco: endereco ?? this.endereco,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      cep: cep ?? this.cep,
      logoUrl: logoUrl ?? this.logoUrl,
      corPrimaria: corPrimaria ?? this.corPrimaria,
      corSecundaria: corSecundaria ?? this.corSecundaria,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      configuracoes: configuracoes ?? this.configuracoes,
    );
  }

  factory Empresa.fromMap(Map<String, dynamic> map) {
    return Empresa(
      id: map['id'] ?? '',
      razaoSocial: map['razaoSocial'] ?? '',
      nomeFantasia: map['nomeFantasia'],
      cnpj: map['cnpj'],
      inscricaoEstadual: map['inscricaoEstadual'],
      inscricaoMunicipal: map['inscricaoMunicipal'],
      email: map['email'],
      telefone: map['telefone'],
      celular: map['celular'],
      site: map['site'],
      endereco: map['endereco'],
      numero: map['numero'],
      complemento: map['complemento'],
      bairro: map['bairro'],
      cidade: map['cidade'],
      estado: map['estado'],
      cep: map['cep'],
      logoUrl: map['logoUrl'],
      corPrimaria: map['corPrimaria'],
      corSecundaria: map['corSecundaria'],
      ativo: map['ativo'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      configuracoes: map['configuracoes'] != null
          ? Map<String, dynamic>.from(map['configuracoes'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'razaoSocial': razaoSocial,
      'nomeFantasia': nomeFantasia,
      'cnpj': cnpj,
      'inscricaoEstadual': inscricaoEstadual,
      'inscricaoMunicipal': inscricaoMunicipal,
      'email': email,
      'telefone': telefone,
      'celular': celular,
      'site': site,
      'endereco': endereco,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'cep': cep,
      'logoUrl': logoUrl,
      'corPrimaria': corPrimaria,
      'corSecundaria': corSecundaria,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'configuracoes': configuracoes,
    };
  }
}



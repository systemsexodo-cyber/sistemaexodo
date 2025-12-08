/// Modelo para representar uma empresa
class Empresa {
  final String id;
  final String razaoSocial;
  final String? nomeFantasia;
  final String? cnpj;
  final String? inscricaoEstadual;
  final String? inscricaoMunicipal;
  final int? crt; // Código de Regime Tributário (CRT): 1=Simples Nacional, 2=Simples Nacional - Excesso de Sublimite, 3=Regime Normal
  
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
  final String? codigoIBGE; // Código IBGE do município (7 dígitos)
  
  // Configurações
  final String? logoUrl;
  final String? corPrimaria; // Cor principal da empresa (hex)
  final String? corSecundaria; // Cor secundária da empresa (hex)
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Configurações NFC-e
  final String? certificadoDigitalUrl; // URL ou path do certificado digital (.pfx)
  final String? certificadoDigitalBytes; // Bytes do certificado em base64 (para web/localStorage)
  final String? senhaCertificado; // Senha do certificado digital
  final String? csc; // Código de Segurança do Contribuinte (fornecido pela SEFAZ)
  final String? cscIdToken; // ID Token do CSC (fornecido pela SEFAZ)
  final String? serieNFCe; // Série da NFC-e (padrão: "1")
  final bool? ambienteHomologacao; // true = Homologação, false = Produção (padrão: true)
  
  // Configurações do sistema
  final Map<String, dynamic>? configuracoes; // Configurações específicas da empresa

  Empresa({
    required this.id,
    required this.razaoSocial,
    this.nomeFantasia,
    this.cnpj,
    this.inscricaoEstadual,
    this.inscricaoMunicipal,
    this.crt,
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
    this.codigoIBGE,
    this.logoUrl,
    this.corPrimaria,
    this.corSecundaria,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
    this.certificadoDigitalUrl,
    this.certificadoDigitalBytes,
    this.senhaCertificado,
    this.csc,
    this.cscIdToken,
    this.serieNFCe,
    this.ambienteHomologacao,
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
    int? crt,
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
    String? codigoIBGE,
    String? logoUrl,
    String? corPrimaria,
    String? corSecundaria,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? certificadoDigitalUrl,
    String? senhaCertificado,
    String? csc,
    String? cscIdToken,
    Map<String, dynamic>? configuracoes,
  }) {
    return Empresa(
      id: id ?? this.id,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      cnpj: cnpj ?? this.cnpj,
      inscricaoEstadual: inscricaoEstadual ?? this.inscricaoEstadual,
      inscricaoMunicipal: inscricaoMunicipal ?? this.inscricaoMunicipal,
      crt: crt ?? this.crt,
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
      codigoIBGE: codigoIBGE ?? this.codigoIBGE,
      logoUrl: logoUrl ?? this.logoUrl,
      corPrimaria: corPrimaria ?? this.corPrimaria,
      corSecundaria: corSecundaria ?? this.corSecundaria,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      certificadoDigitalUrl: certificadoDigitalUrl ?? this.certificadoDigitalUrl,
      certificadoDigitalBytes: certificadoDigitalBytes ?? this.certificadoDigitalBytes,
      senhaCertificado: senhaCertificado ?? this.senhaCertificado,
      csc: csc ?? this.csc,
      cscIdToken: cscIdToken ?? this.cscIdToken,
      serieNFCe: serieNFCe ?? this.serieNFCe,
      ambienteHomologacao: ambienteHomologacao ?? this.ambienteHomologacao,
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
      crt: map['crt'] != null 
          ? (map['crt'] is int ? map['crt'] as int : int.tryParse(map['crt'].toString()))
          : (map['regimeTributario'] != null 
              ? _converterRegimeTributarioParaCRT(map['regimeTributario'].toString())
              : null), // Compatibilidade com dados antigos
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
      codigoIBGE: map['codigoIBGE'],
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
      certificadoDigitalUrl: map['certificadoDigitalUrl'],
      certificadoDigitalBytes: map['certificadoDigitalBytes'],
      senhaCertificado: map['senhaCertificado'],
      csc: map['csc'],
      cscIdToken: map['cscIdToken'],
      serieNFCe: map['serieNFCe'],
      ambienteHomologacao: map['ambienteHomologacao'] ?? true, // Padrão: homologação
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
      'crt': crt,
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
      'codigoIBGE': codigoIBGE,
      'logoUrl': logoUrl,
      'corPrimaria': corPrimaria,
      'corSecundaria': corSecundaria,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'certificadoDigitalUrl': certificadoDigitalUrl,
      'certificadoDigitalBytes': certificadoDigitalBytes,
      'senhaCertificado': senhaCertificado,
      'csc': csc,
      'cscIdToken': cscIdToken,
      'serieNFCe': serieNFCe,
      'ambienteHomologacao': ambienteHomologacao,
      'configuracoes': configuracoes,
    };
  }

  /// Converte regime tributário antigo (String) para CRT (int) - compatibilidade
  static int? _converterRegimeTributarioParaCRT(String? regime) {
    if (regime == null || regime.isEmpty) return null;
    final regimeLower = regime.toLowerCase();
    if (regimeLower.contains('simples nacional') && regimeLower.contains('excesso')) {
      return 2;
    } else if (regimeLower.contains('simples nacional')) {
      return 1;
    } else if (regimeLower.contains('normal') || regimeLower.contains('presumido') || regimeLower.contains('real')) {
      return 3;
    }
    return null;
  }

  /// Retorna a descrição do CRT
  String? get crtDescricao {
    switch (crt) {
      case 1:
        return 'Simples Nacional';
      case 2:
        return 'Simples Nacional - Excesso de Sublimite';
      case 3:
        return 'Regime Normal';
      default:
        return null;
    }
  }
}



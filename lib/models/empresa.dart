import 'package:sistema_exodo_novo/models/adicional_produto.dart';
/// Modelo para representar uma empresa
class Empresa {
  final String id;
  final String razaoSocial;
  final String? nomeFantasia;
  final String? cnpj;
  final String? inscricaoEstadual;
  final String? inscricaoMunicipal;
  final int? crt; // Código de Regime Tributário (CRT): 1=Simples Nacional, 2=Simples Nacional - Excesso de Sublimite, 3=Regime Normal
  final String slug; // Link personalizado (friendly URL)
  
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
  final String? senhaCertificado; // Senha do certificado digital
  final String? csc; // Código de Segurança do Contribuinte (fornecido pela SEFAZ)
  final String? cscIdToken; // ID Token do CSC (fornecido pela SEFAZ)
  final String? serieNFCe; // Série da NFC-e (padrão: "1")
  final bool? ambienteHomologacao; // true = Homologação, false = Produção (padrão: true)
  final String? focusNFeToken; // Token da API Focus NFe (para emissão sem backend)
  
  // Configurações do sistema
  final Map<String, dynamic>? configuracoes; // Configurações específicas da empresa
  
  // Controle de acesso às telas
  final Set<String>? telasPermitidas; // Códigos das telas que podem ser acessadas (null = todas permitidas)

  // Configurações WhatsApp (Evolution API)
  final String? whatsappApiUrl;       // URL da Evolution API (ex: https://xxx.up.railway.app)
  final String? whatsappApiKey;       // API Key da Evolution API
  final String? whatsappInstanceName; // Nome da instância (ex: empresa_principal)
  final String? whatsappTipo;         // 'evolution' ou 'twilio'
  final bool whatsappAtivo;           // Se as notificações WhatsApp estão ativas
  final bool moduloPet;               // Se o módulo Pet Shop está ativo
  final List<AdicionalProduto> modelosAdicionais; // Modelos de adicionais reutilizáveis

  Empresa({
    required this.id,
    required this.razaoSocial,
    required this.slug,
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
    this.senhaCertificado,
    this.csc,
    this.cscIdToken,
    this.serieNFCe,
    this.ambienteHomologacao,
    this.focusNFeToken,
    this.configuracoes,
    this.telasPermitidas,
    this.whatsappApiUrl,
    this.whatsappApiKey,
    this.whatsappInstanceName,
    this.whatsappTipo = 'evolution',
    this.whatsappAtivo = false,
    this.moduloPet = false,
    this.modelosAdicionais = const [],
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
    String? slug,
    String? certificadoDigitalUrl,
    String? senhaCertificado,
    String? csc,
    String? cscIdToken,
    String? serieNFCe,
    bool? ambienteHomologacao,
    String? focusNFeToken,
    Map<String, dynamic>? configuracoes,
    Set<String>? telasPermitidas,
    String? whatsappApiUrl,
    String? whatsappApiKey,
    String? whatsappInstanceName,
    String? whatsappTipo,
    bool? whatsappAtivo,
    bool? moduloPet,
    List<AdicionalProduto>? modelosAdicionais,
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
      slug: slug ?? this.slug,
      certificadoDigitalUrl: certificadoDigitalUrl ?? this.certificadoDigitalUrl,
      senhaCertificado: senhaCertificado ?? this.senhaCertificado,
      csc: csc ?? this.csc,
      cscIdToken: cscIdToken ?? this.cscIdToken,
      serieNFCe: serieNFCe ?? this.serieNFCe,
      ambienteHomologacao: ambienteHomologacao ?? this.ambienteHomologacao,
      focusNFeToken: focusNFeToken ?? this.focusNFeToken,
      configuracoes: configuracoes != null 
          ? (this.configuracoes != null 
              ? (Map<String, dynamic>.from(this.configuracoes!)..addAll(configuracoes))
              : configuracoes)
          : this.configuracoes,
      telasPermitidas: telasPermitidas ?? this.telasPermitidas,
      whatsappApiUrl: whatsappApiUrl ?? this.whatsappApiUrl,
      whatsappApiKey: whatsappApiKey ?? this.whatsappApiKey,
      whatsappInstanceName: whatsappInstanceName ?? this.whatsappInstanceName,
      whatsappTipo: whatsappTipo ?? this.whatsappTipo,
      whatsappAtivo: whatsappAtivo ?? this.whatsappAtivo,
      moduloPet: moduloPet ?? this.moduloPet,
      modelosAdicionais: modelosAdicionais ?? this.modelosAdicionais,
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
      slug: (map['slug'] != null && map['slug'].toString().trim().isNotEmpty)
          ? map['slug'].toString()
          : gerarSlug(map['nomeFantasia'] ?? map['razaoSocial'] ?? ''),
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
      senhaCertificado: map['senhaCertificado'],
      csc: map['csc'],
      cscIdToken: map['cscIdToken'],
      serieNFCe: map['serieNFCe'],
      ambienteHomologacao: map['ambienteHomologacao'] ?? true, // Padrão: homologação
      focusNFeToken: map['focusNFeToken'],
      configuracoes: map['configuracoes'] != null
          ? Map<String, dynamic>.from(map['configuracoes'])
          : null,
      telasPermitidas: map['telasPermitidas'] != null
          ? Set<String>.from(map['telasPermitidas'])
          : null,
      whatsappApiUrl: map['whatsappApiUrl'],
      whatsappApiKey: map['whatsappApiKey'],
      whatsappInstanceName: map['whatsappInstanceName'],
      whatsappTipo: map['whatsappTipo'] ?? 'evolution',
      whatsappAtivo: map['whatsappAtivo'] ?? false,
      moduloPet: map['moduloPet'] ?? false,
      modelosAdicionais: (map['modelosAdicionais'] as List?)
          ?.map((e) => AdicionalProduto.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
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
      'slug': slug,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'certificadoDigitalUrl': certificadoDigitalUrl,
      'senhaCertificado': senhaCertificado,
      'csc': csc,
      'cscIdToken': cscIdToken,
      'serieNFCe': serieNFCe,
      'ambienteHomologacao': ambienteHomologacao,
      'focusNFeToken': focusNFeToken,
      'configuracoes': configuracoes,
      'telasPermitidas': telasPermitidas?.toList(),
      'whatsappApiUrl': whatsappApiUrl,
      'whatsappApiKey': whatsappApiKey,
      'whatsappInstanceName': whatsappInstanceName,
      'whatsappTipo': whatsappTipo,
      'whatsappAtivo': whatsappAtivo,
      'moduloPet': moduloPet,
      'modelosAdicionais': modelosAdicionais.map((e) => e.toMap()).toList(),
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
  
  /// Verifica se uma tela pode ser acessada
  /// Retorna true se telasPermitidas for null (todas permitidas) ou se a tela estiver na lista
  bool podeAcessarTela(String codigoTela) {
    if (telasPermitidas == null) {
      return true; // Se não especificado, todas as telas são permitidas
    }
    return telasPermitidas!.contains(codigoTela);
  }

  /// Gera um slug a partir de um texto (ex: "Exodo Systems" -> "exodo-systems")
  static String gerarSlug(String texto) {
    if (texto.isEmpty) return 'loja';
    
    // Converter para minúsculas
    String slug = texto.toLowerCase();
    
    // Remover acentos e caracteres especiais comuns no Brasil
    slug = slug
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n');
    
    // Remover qualquer outro caractere que não seja letra, número, espaço ou hífen
    slug = slug.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    
    // Substituir espaços e múltiplos hífens por um único hífen
    slug = slug.replaceAll(RegExp(r'[\s-]+'), '-');
    
    // Remover hífens no início e fim
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    
    // Se ficou vazio, usar "loja"
    if (slug.isEmpty) return 'loja';
    
    return slug.trim();
  }
}

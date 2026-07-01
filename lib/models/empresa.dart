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
  
  // Fiscal / Contabilidade
  final String? emailContabilidade;   // E-mail da contabilidade para envio de XMLs
  final bool envioFiscalAutomatico;    // Se deve enviar no dia 01 de cada mês automaticamente

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
    this.emailContabilidade,
    this.envioFiscalAutomatico = false,
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
    String? emailContabilidade,
    bool? envioFiscalAutomatico,
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
      emailContabilidade: emailContabilidade ?? this.emailContabilidade,
      envioFiscalAutomatico: envioFiscalAutomatico ?? this.envioFiscalAutomatico,
    );
  }

  factory Empresa.fromMap(Map<String, dynamic> map) {
    // Helper para suportar tanto camelCase (localStorage) quanto snake_case (PostgreSQL)
    String? getString(String camelCase, String snakeCase) {
      return map[camelCase] ?? map[snakeCase];
    }
    
    bool? getBool(String camelCase, String snakeCase, bool defaultValue) {
      final val = map[camelCase] ?? map[snakeCase];
      if (val == null) return defaultValue;
      if (val is bool) return val;
      return val.toString().toLowerCase() == 'true';
    }
    
    DateTime getDateTime(String camelCase, String snakeCase) {
      final val = map[camelCase] ?? map[snakeCase];
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.parse(val.toString());
    }
    
    return Empresa(
      id: map['id'] ?? '',
      razaoSocial: getString('razaoSocial', 'razao_social') ?? '',
      nomeFantasia: getString('nomeFantasia', 'nome_fantasia'),
      cnpj: getString('cnpj', 'cnpj'),
      inscricaoEstadual: getString('inscricaoEstadual', 'inscricao_estadual'),
      inscricaoMunicipal: getString('inscricaoMunicipal', 'inscricao_municipal'),
      crt: map['crt'] != null 
          ? (map['crt'] is int ? map['crt'] as int : int.tryParse(map['crt'].toString()))
          : (map['regime_tributario'] != null 
              ? _converterRegimeTributarioParaCRT(map['regime_tributario'].toString())
              : null),
      slug: (map['slug'] != null && map['slug'].toString().trim().isNotEmpty)
          ? map['slug'].toString()
          : gerarSlug(getString('nomeFantasia', 'nome_fantasia') ?? getString('razaoSocial', 'razao_social') ?? ''),
      email: getString('email', 'email'),
      telefone: getString('telefone', 'telefone'),
      celular: getString('celular', 'celular'),
      site: getString('site', 'site'),
      endereco: getString('endereco', 'endereco'),
      numero: getString('numero', 'numero'),
      complemento: getString('complemento', 'complemento'),
      bairro: getString('bairro', 'bairro'),
      cidade: getString('cidade', 'cidade'),
      estado: getString('estado', 'estado'),
      cep: getString('cep', 'cep'),
      codigoIBGE: getString('codigoIBGE', 'codigo_ibge'),
      logoUrl: getString('logoUrl', 'logo_url'),
      corPrimaria: getString('corPrimaria', 'cor_primaria'),
      corSecundaria: getString('corSecundaria', 'cor_secundaria'),
      ativo: getBool('ativo', 'ativo', true) ?? true,
      createdAt: getDateTime('createdAt', 'created_at'),
      updatedAt: getDateTime('updatedAt', 'updated_at'),
      certificadoDigitalUrl: getString('certificadoDigitalUrl', 'certificado_digital_url'),
      senhaCertificado: getString('senhaCertificado', 'senha_certificado'),
      csc: getString('csc', 'csc'),
      cscIdToken: getString('cscIdToken', 'csc_id_token'),
      serieNFCe: getString('serieNFCe', 'serie_nfce'),
      ambienteHomologacao: getBool('ambienteHomologacao', 'ambiente_homologacao', true) ?? true,
      focusNFeToken: getString('focusNFeToken', 'focus_nfe_token'),
      configuracoes: map['configuracoes'] != null
          ? Map<String, dynamic>.from(map['configuracoes'])
          : null,
      telasPermitidas: map['telasPermitidas'] != null
          ? Set<String>.from(map['telasPermitidas'])
          : null,
      whatsappApiUrl: getString('whatsappApiUrl', 'whatsapp_api_url'),
      whatsappApiKey: getString('whatsappApiKey', 'whatsapp_api_key'),
      whatsappInstanceName: getString('whatsappInstanceName', 'whatsapp_instance_name'),
      whatsappTipo: getString('whatsappTipo', 'whatsapp_tipo') ?? 'evolution',
      whatsappAtivo: getBool('whatsappAtivo', 'whatsapp_ativo', false) ?? false,
      moduloPet: getBool('moduloPet', 'modulo_pet', false) ?? false,
      modelosAdicionais: ((map['modelosAdicionais'] ?? map['modelos_adicionais']) as List?)
          ?.map((e) => AdicionalProduto.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      emailContabilidade: getString('emailContabilidade', 'email_contabilidade'),
      envioFiscalAutomatico: getBool('envioFiscalAutomatico', 'envio_fiscal_automatico', false) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'razao_social': razaoSocial,
      'nome_fantasia': nomeFantasia,
      'cnpj': cnpj,
      // 'inscricao_estadual': inscricaoEstadual, // Removido para evitar erro PGRST204 (coluna não existe no Supabase)
      // 'inscricao_municipal': inscricaoMunicipal, // Removido para evitar erro PGRST204 (coluna não existe no Supabase)
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
      // 'codigo_ibge': codigoIBGE, // Removido para evitar erro PGRST204 (coluna não existe no Supabase)
      // 'logo_url': logoUrl, // Removido para evitar erro PGRST204 (coluna não existe no Supabase)
      // 'cor_primaria': corPrimaria, // Removido para evitar erro PGRST204 (coluna não existe no Supabase)
      // 'cor_secundaria': corSecundaria, // Removido para evitar erro PGRST204
      'ativo': ativo,
      'slug': slug,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Configurações NFC-e removidas do toMap para evitar erro PGRST204 (não existem no Supabase)
      'configuracoes': configuracoes,
      'telas_permitidas': telasPermitidas?.toList(),
      // Campos removidos para evitar erro PGRST204 (não existem no Supabase)
      // 'whatsapp_api_url': whatsappApiUrl,
      // 'whatsapp_api_key': whatsappApiKey,
      // 'whatsapp_instance_name': whatsappInstanceName,
      // 'whatsapp_tipo': whatsappTipo,
      // 'whatsapp_ativo': whatsappAtivo,
      // 'modulo_pet': moduloPet,
      // 'modelos_adicionais': modelosAdicionais.map((e) => e.toMap()).toList(),
      // 'email_contabilidade': emailContabilidade,
      // 'envio_fiscal_automatico': envioFiscalAutomatico, // Removido para evitar erro PGRST204
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

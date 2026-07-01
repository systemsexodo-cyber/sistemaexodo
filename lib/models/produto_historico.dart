/// Modelo para histórico de alterações de produtos
/// Registra quem alterou, quando alterou, e quais campos foram modificados
class ProdutoHistorico {
  final String id;
  final String produtoId;
  final String produtoNome;
  final String? produtoCodigo;
  
  // Informações do usuário que fez a alteração
  final String usuarioId;
  final String usuarioNome;
  final String? usuarioEmail;
  
  // Tipo de operação: CREATE, UPDATE, DELETE
  final String tipoOperacao;
  
  // Campos alterados (para UPDATE)
  final List<String> camposAlterados;
  
  // Valores anteriores (JSON)
  final Map<String, dynamic>? valoresAnteriores;
  
  // Valores novos (JSON)
  final Map<String, dynamic>? valoresNovos;
  
  // Resumo das mudanças principais para exibição rápida
  final String? resumoMudancas;
  
  // Datas
  final DateTime dataAlteracao;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Empresa
  final String empresaId;

  ProdutoHistorico({
    required this.id,
    required this.produtoId,
    required this.produtoNome,
    this.produtoCodigo,
    required this.usuarioId,
    required this.usuarioNome,
    this.usuarioEmail,
    required this.tipoOperacao,
    this.camposAlterados = const [],
    this.valoresAnteriores,
    this.valoresNovos,
    this.resumoMudancas,
    required this.dataAlteracao,
    this.createdAt,
    this.updatedAt,
    required this.empresaId,
  });

  factory ProdutoHistorico.fromMap(Map<String, dynamic> map) {
    return ProdutoHistorico(
      id: map['id'] ?? '',
      produtoId: map['produto_id'] ?? map['produtoId'] ?? '',
      produtoNome: map['produto_nome'] ?? map['produtoNome'] ?? '',
      produtoCodigo: map['produto_codigo'] ?? map['produtoCodigo'],
      usuarioId: map['usuario_id'] ?? map['usuarioId'] ?? '',
      usuarioNome: map['usuario_nome'] ?? map['usuarioNome'] ?? 'Sistema',
      usuarioEmail: map['usuario_email'] ?? map['usuarioEmail'],
      tipoOperacao: map['tipo_operacao'] ?? map['tipoOperacao'] ?? 'UPDATE',
      camposAlterados: _parseCamposAlterados(map['campos_alterados'] ?? map['camposAlterados']),
      valoresAnteriores: map['valores_anteriores'] ?? map['valoresAnteriores'],
      valoresNovos: map['valores_novos'] ?? map['valoresNovos'],
      resumoMudancas: map['resumo_mudancas'] ?? map['resumoMudancas'],
      dataAlteracao: _parseDateTime(map['data_alteracao'] ?? map['dataAlteracao']) ?? DateTime.now(),
      createdAt: _parseDateTime(map['created_at'] ?? map['createdAt']),
      updatedAt: _parseDateTime(map['updated_at'] ?? map['updatedAt']),
      empresaId: map['empresa_id'] ?? map['empresaId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'produto_codigo': produtoCodigo,
      'usuario_id': usuarioId,
      'usuario_nome': usuarioNome,
      'usuario_email': usuarioEmail,
      'tipo_operacao': tipoOperacao,
      'campos_alterados': camposAlterados.join(','),
      'valores_anteriores': valoresAnteriores,
      'valores_novos': valoresNovos,
      'resumo_mudancas': resumoMudancas,
      'data_alteracao': dataAlteracao.toIso8601String(),
      'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'empresa_id': empresaId,
    };
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'produto_codigo': produtoCodigo,
      'usuario_id': usuarioId,
      'usuario_nome': usuarioNome,
      'usuario_email': usuarioEmail,
      'tipo_operacao': tipoOperacao,
      'campos_alterados': camposAlterados.join(','),
      'valores_anteriores': valoresAnteriores,
      'valores_novos': valoresNovos,
      'resumo_mudancas': resumoMudancas,
      'data_alteracao': dataAlteracao.toIso8601String(),
      'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updated_at': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'empresa_id': empresaId,
    };
  }

  static List<String> _parseCamposAlterados(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    if (value is String && value.isNotEmpty) return value.split(',');
    return [];
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Compara dois produtos e retorna a lista de campos alterados
  static List<String> compararProdutos(Map<String, dynamic> anterior, Map<String, dynamic> novo) {
    final camposAlterados = <String>[];
    
    final camposImportantes = [
      'preco',
      'preco_custo',
      'precoCusto',
      'estoque',
      'nome',
      'ncm',
      'icms_aliquota',
      'icmsAliquota',
      'icms_cst',
      'icmsCst',
      'ipi_aliquota',
      'ipiAliquota',
      'ipi_cst',
      'ipiCst',
      'pis_aliquota',
      'pisAliquota',
      'pis_cst',
      'pisCst',
      'cofins_aliquota',
      'cofinsAliquota',
      'cofins_cst',
      'cofinsCst',
      'iss_aliquota',
      'issAliquota',
      'csosn',
      'cfop',
      'cest',
      'origem',
      'grupo',
      'unidade',
      'codigo',
      'codigo_barras',
      'codigoBarras',
    ];

    for (final campo in camposImportantes) {
      final valorAnterior = anterior[campo];
      final valorNovo = novo[campo];
      
      if (valorAnterior != valorNovo) {
        camposAlterados.add(campo);
      }
    }

    return camposAlterados;
  }

  /// Gera um resumo legível das mudanças
  static String? gerarResumoMudancas(
    Map<String, dynamic>? valoresAnteriores,
    Map<String, dynamic>? valoresNovos,
    List<String> camposAlterados,
  ) {
    if (valoresAnteriores == null || valoresNovos == null) return null;
    if (camposAlterados.isEmpty) return null;

    final mudancas = <String>[];

    for (final campo in camposAlterados) {
      final anterior = valoresAnteriores[campo];
      final novo = valoresNovos[campo];
      
      // Tradução de nomes de campos
      final nomeCampo = _traduzirNomeCampo(campo);
      
      if (campo.toLowerCase().contains('preco') || campo.toLowerCase().contains('aliquota')) {
        // Formatar como moeda/percentual
        final antigoStr = anterior != null ? 'R\$ ${anterior.toString()}' : 'vazio';
        final novoStr = novo != null ? 'R\$ ${novo.toString()}' : 'vazio';
        mudancas.add('$nomeCampo: $antigoStr → $novoStr');
      } else if (campo == 'estoque') {
        mudancas.add('$nomeCampo: $anterior → $novo unidades');
      } else {
        mudancas.add('$nomeCampo: "${anterior ?? ''}" → "${novo ?? ''}"');
      }
    }

    return mudancas.join('; ');
  }

  static String _traduzirNomeCampo(String campo) {
    final traducoes = {
      'preco': 'Preço de Venda',
      'preco_custo': 'Preço de Custo',
      'precoCusto': 'Preço de Custo',
      'estoque': 'Estoque',
      'nome': 'Nome',
      'ncm': 'NCM',
      'icms_aliquota': 'Alíquota ICMS',
      'icmsAliquota': 'Alíquota ICMS',
      'icms_cst': 'CST ICMS',
      'icmsCst': 'CST ICMS',
      'ipi_aliquota': 'Alíquota IPI',
      'ipiAliquota': 'Alíquota IPI',
      'ipi_cst': 'CST IPI',
      'ipiCst': 'CST IPI',
      'pis_aliquota': 'Alíquota PIS',
      'pisAliquota': 'Alíquota PIS',
      'pis_cst': 'CST PIS',
      'pisCst': 'CST PIS',
      'cofins_aliquota': 'Alíquota COFINS',
      'cofinsAliquota': 'Alíquota COFINS',
      'cofins_cst': 'CST COFINS',
      'cofinsCst': 'CST COFINS',
      'iss_aliquota': 'Alíquota ISS',
      'issAliquota': 'Alíquota ISS',
      'csosn': 'CSOSN',
      'cfop': 'CFOP',
      'cest': 'CEST',
      'origem': 'Origem',
      'grupo': 'Grupo/Categoria',
      'unidade': 'Unidade',
      'codigo': 'Código',
      'codigo_barras': 'Código de Barras',
      'codigoBarras': 'Código de Barras',
    };

    return traducoes[campo] ?? campo;
  }
}

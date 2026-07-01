import 'package:sistema_exodo_novo/utils/date_parser.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/item_composicao.dart';

class Produto {
  final String id;
  final String? codigo; // Pode ser null para produtos antigos
  final String? codigoBarras; // Código de barras (EAN, UPC, etc)
  final String nome;
  final String? descricao;
  final String unidade;
  final String grupo; // Novo: Grupo/Categoria do produto
  final double preco;
  final double? precoCusto; // Preço de custo do produto
  final double estoque;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Campos de promoção
  final double? precoPromocional;
  final DateTime? promocaoInicio;
  final DateTime? promocaoFim;
  
  // Códigos do fornecedor - mapeamento entre código do fornecedor e código interno
  final List<String> codigosFornecedor; // Lista de códigos que o fornecedor usa para este produto

  // Campos de impostos e tributação
  final String? ncm; // Nomenclatura Comum do Mercosul (8 dígitos)
  final double? icmsAliquota; // Alíquota ICMS (%)
  final String? icmsCst; // Código de Situação Tributária ICMS
  final double? ipiAliquota; // Alíquota IPI (%)
  final String? ipiCst; // Código de Situação Tributária IPI
  final double? pisAliquota; // Alíquota PIS (%)
  final String? pisCst; // Código de Situação Tributária PIS
  final double? cofinsAliquota; // Alíquota COFINS (%)
  final String? cofinsCst; // Código de Situação Tributária COFINS
  final double? issAliquota; // Alíquota ISS (%) - para serviços
  final String? origem; // Origem da mercadoria (0-Nacional, 1-Estrangeira, etc)
  final String? cfop; // Código Fiscal de Operações e Prestações
  final String? cest; // Código Especificador da Substituição Tributária (quando aplicável)
  
  // Campos do Simples Nacional
  final String? csosn; // Código de Situação da Operação - Simples Nacional
  final double? simplesNacionalAliquota; // Alíquota do Simples Nacional (%)
  
  // Campos para controle de mesas/comandas
  final bool? paraCozinha; // Se true, item é preparado na cozinha
  final bool? paraBar; // Se true, item é preparado no bar
  
  // Campos para E-commerce
  final bool exibirNaLoja; // Se true, produto aparece na loja pública
  final bool emDestaque; // Se true, produto aparece em destaque no topo da loja
  final List<String> fotosUrls; // URLs das fotos do produto (múltiplas)
  final String? fotoPrincipalUrl; // URL da foto principal (primeira da lista)
  final String? descricaoEcommerce; // Descrição específica para e-commerce (pode ser diferente da descrição normal)
  final int? pesoGramas; // Peso do produto em gramas (para cálculo de frete)
  final double? alturaCm; // Altura em centímetros
  final double? larguraCm; // Largura em centímetros
  final double? profundidadeCm; // Profundidade em centímetros
  final List<String> tags; // Tags para busca e categorização na loja
  
  // Campos para variações de produto (tamanhos, cores, sabores, etc)
  final List<VariacaoProduto> variacoes; // Lista de variações disponíveis
  final bool temVariacoes; // Se o produto tem variações configuradas
  
  // Novos campos para ADICIONAIS (ex: Acai com Leite Ninho)
  final List<AdicionalProduto> adicionais; // Lista de adicionais disponíveis
  final bool temAdicionais; // Se o produto tem adicionais cadastrados
  final String? observacaoPadrao; // Observação padrão para este produto (ex: "Sem gelo")
  
  // Campos de Fornecedor
  final String? fornecedorId;
  final String? fornecedorNome;
  final double estoqueMinimo; // Novo: Estoque mínimo para alerta/compra
  
  // Produto Composto
  final bool ehComposto;
  final List<ItemComposicao> composicao;
  
  // Tracking de Pedidos de Compra
  final bool pedidoCompraGerado;
  final DateTime? dataUltimoPedido;

  // Mapeamento de estoque por fornecedor (Ex: {"Ambev": 10.0, "Coca": 10.0})
  final Map<String, double> estoquePorFornecedor; 
  final bool enviaBalanca; // Se true, produto é enviado para a balança 

  Produto({
    required this.id,
    this.codigo,
    this.codigoBarras,
    required this.nome,
    this.descricao,
    required this.unidade,
    required this.grupo,
    required this.preco,
    this.precoCusto,
    required this.estoque,
    required this.createdAt,
    required this.updatedAt,
    this.precoPromocional,
    this.promocaoInicio,
    this.promocaoFim,
    List<String>? codigosFornecedor,
    this.ncm,
    this.icmsAliquota,
    this.icmsCst,
    this.ipiAliquota,
    this.ipiCst,
    this.pisAliquota,
    this.pisCst,
    this.cofinsAliquota,
    this.cofinsCst,
    this.issAliquota,
    this.origem,
    this.cfop,
    this.cest,
    this.csosn,
    this.simplesNacionalAliquota,
    this.paraCozinha,
    this.paraBar,
    this.exibirNaLoja = false,
    this.emDestaque = false,
    this.enviaBalanca = false,
    List<String>? fotosUrls,
    this.fotoPrincipalUrl,
    this.descricaoEcommerce,
    this.pesoGramas,
    this.alturaCm,
    this.larguraCm,
    this.profundidadeCm,
    List<String>? tags,
    List<VariacaoProduto>? variacoes,
    bool? temVariacoes,
    List<AdicionalProduto>? adicionais,
    bool? temAdicionais,
    this.observacaoPadrao,
    this.fornecedorId,
    this.fornecedorNome,
    this.estoqueMinimo = 0.0,
    this.ehComposto = false,
    List<ItemComposicao>? composicao,
    this.pedidoCompraGerado = false,
    this.dataUltimoPedido,
    Map<String, double>? estoquePorFornecedor,
  }) : codigosFornecedor = codigosFornecedor ?? [],
       fotosUrls = fotosUrls ?? [],
       tags = tags ?? [],
       variacoes = variacoes ?? [],
       temVariacoes = temVariacoes ?? false,
       adicionais = adicionais ?? [],
       temAdicionais = temAdicionais ?? false,
       composicao = composicao ?? [],
       estoquePorFornecedor = estoquePorFornecedor ?? {};

  // Verifica se a promoção está ativa agora
  bool get promocaoAtiva {
    if (precoPromocional == null ||
        promocaoInicio == null ||
        promocaoFim == null) {
      return false;
    }
    final agora = DateTime.now();
    return agora.isAfter(promocaoInicio!) && agora.isBefore(promocaoFim!);
  }

  // Retorna o preço atual (promocional se ativo, normal caso contrário)
  double get precoAtual => promocaoAtiva ? precoPromocional! : preco;
  
  // Retorna o preço com variação (se houver variação selecionada)
  double precoComVariacao(List<VariacaoProduto>? variacoesSelecionadas) {
    double precoBase = precoAtual;
    if (variacoesSelecionadas != null && variacoesSelecionadas.isNotEmpty) {
      for (var variacao in variacoesSelecionadas) {
        if (variacao.precoAdicional != null) {
          precoBase += variacao.precoAdicional!;
        }
      }
    }
    return precoBase;
  }
  
  // Retorna o estoque total considerando variações
  double get estoqueTotal {
    if (temVariacoes && variacoes.isNotEmpty) {
      return variacoes.fold(0.0, (sum, v) => sum + v.estoque);
    }
    return estoque;
  }
  
  // Retorna o estoque de uma variação específica
  double? estoqueVariacao(List<VariacaoProduto>? variacoesSelecionadas) {
    if (!temVariacoes || variacoesSelecionadas == null || variacoesSelecionadas.isEmpty) {
      return estoque;
    }
    // Se tem variações, retorna o estoque da primeira variação selecionada
    // (assumindo que cada combinação de variações tem seu próprio estoque)
    if (variacoesSelecionadas.isNotEmpty) {
      final variacao = variacoesSelecionadas.first;
      return variacao.estoque;
    }
    return estoque;
  }

  // Calcula o percentual de desconto
  double get percentualDesconto {
    if (!promocaoAtiva || precoPromocional == null) return 0;
    return ((preco - precoPromocional!) / preco * 100);
  }

  // Calcula a margem de lucro em percentual
  double get margemLucroPercentual {
    if (precoCusto == null || precoCusto == 0) return 0;
    final lucro = preco - precoCusto!;
    return (lucro / precoCusto!) * 100;
  }

  // Calcula o lucro em valor (preço - custo)
  double get lucroValor {
    if (precoCusto == null) return 0;
    return preco - precoCusto!;
  }

  // Verifica se há lucro
  bool get temLucro {
    if (precoCusto == null) return true; // Se não tem custo, assume que tem lucro
    return preco > precoCusto!;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'codigo_barras': codigoBarras,
      'nome': nome,
      'descricao': descricao,
      'unidade': unidade,
      'grupo': grupo,
      'preco': preco,
      'preco_custo': precoCusto,
      'estoque': estoque,
      'estoque_minimo': estoqueMinimo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'preco_promocional': precoPromocional,
      'promocao_inicio': promocaoInicio?.toIso8601String(),
      'promocao_fim': promocaoFim?.toIso8601String(),
      'codigos_fornecedor': codigosFornecedor,
      'ncm': ncm,
      'icms_aliquota': icmsAliquota,
      'icms_cst': icmsCst,
      'ipi_aliquota': ipiAliquota,
      'ipi_cst': ipiCst,
      'pis_aliquota': pisAliquota,
      'pis_cst': pisCst,
      'cofins_aliquota': cofinsAliquota,
      'cofins_cst': cofinsCst,
      'iss_aliquota': issAliquota,
      'origem': origem,
      'cfop': cfop,
      'cest': cest,
      'csosn': csosn,
      'simples_nacional_aliquota': simplesNacionalAliquota,
      'para_cozinha': paraCozinha,
      'para_bar': paraBar,
      'exibir_na_loja': exibirNaLoja,
      'em_destaque': emDestaque,
      'envia_balanca': enviaBalanca,
      'fotos_urls': fotosUrls,
      'foto_principal_url': fotoPrincipalUrl,
      'descricao_ecommerce': descricaoEcommerce,
      'peso_gramas': pesoGramas,
      'altura_cm': alturaCm,
      'largura_cm': larguraCm,
      'profundidade_cm': profundidadeCm,
      'tags': tags,
      'variacoes': variacoes.map((v) => v.toMap()).toList(),
      'tem_variacoes': temVariacoes,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'tem_adicionais': temAdicionais,
      'eh_composto': ehComposto,
      'composicao': composicao.map((c) => c.toMap()).toList(),
      'observacao_padrao': observacaoPadrao,
      'fornecedor_id': fornecedorId,
      'fornecedor_nome': fornecedorNome,
      'estoque_por_fornecedor': estoquePorFornecedor,
      'pedido_compra_gerado': pedidoCompraGerado,
      'data_ultimo_pedido': dataUltimoPedido?.toIso8601String(),
    };
  }

  factory Produto.fromMap(Map<String, dynamic> map) {
    // Helper para pegar valor de ambos camelCase (localStorage) ou snake_case (Supabase)
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
    bool? getBool(String camel, String snake) => get<bool>(camel, snake);
    List? getList(String camel, String snake) => get<List>(camel, snake);
    Map? getMap(String camel, String snake) => get<Map>(camel, snake);

    DateTime? getDate(String camel, String snake) {
      final val = map[camel] ?? map[snake];
      if (val == null) return null;
      return DateParser.parse(val);
    }

    return Produto(
      id: map['id'] as String,
      codigo: map['codigo'] as String?,
      codigoBarras: getStr('codigoBarras', 'codigo_barras'),
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      unidade: map['unidade'] as String? ?? '',
      grupo: map['grupo'] as String? ?? 'Sem Grupo',
      preco: (getNum('preco', 'preco') ?? 0.0).toDouble(),
      precoCusto: getNum('precoCusto', 'preco_custo')?.toDouble(),
      estoque: (getNum('estoque', 'estoque') ?? 0.0).toDouble(),
      estoqueMinimo: getNum('estoqueMinimo', 'estoque_minimo')?.toDouble() ?? 0.0,
      createdAt: getDate('createdAt', 'created_at') ?? DateTime.now(),
      updatedAt: getDate('updatedAt', 'updated_at') ?? DateTime.now(),
      precoPromocional: getNum('precoPromocional', 'preco_promocional')?.toDouble(),
      promocaoInicio: getDate('promocaoInicio', 'promocao_inicio'),
      promocaoFim: getDate('promocaoFim', 'promocao_fim'),
      codigosFornecedor: getList('codigosFornecedor', 'codigos_fornecedor')?.cast<String>() ?? [],
      ncm: map['ncm'] as String?,
      icmsAliquota: getNum('icmsAliquota', 'icms_aliquota')?.toDouble(),
      icmsCst: getStr('icmsCst', 'icms_cst'),
      ipiAliquota: getNum('ipiAliquota', 'ipi_aliquota')?.toDouble(),
      ipiCst: getStr('ipiCst', 'ipi_cst'),
      pisAliquota: getNum('pisAliquota', 'pis_aliquota')?.toDouble(),
      pisCst: getStr('pisCst', 'pis_cst'),
      cofinsAliquota: getNum('cofinsAliquota', 'cofins_aliquota')?.toDouble(),
      cofinsCst: getStr('cofinsCst', 'cofins_cst'),
      issAliquota: getNum('issAliquota', 'iss_aliquota')?.toDouble(),
      origem: map['origem'] as String?,
      cfop: map['cfop'] as String?,
      cest: map['cest'] as String?,
      csosn: map['csosn'] as String?,
      simplesNacionalAliquota: getNum('simplesNacionalAliquota', 'simples_nacional_aliquota')?.toDouble(),
      paraCozinha: getBool('paraCozinha', 'para_cozinha'),
      paraBar: getBool('paraBar', 'para_bar'),
      exibirNaLoja: getBool('exibirNaLoja', 'exibir_na_loja') ?? false,
      emDestaque: getBool('emDestaque', 'em_destaque') ?? false,
      enviaBalanca: getBool('enviaBalanca', 'envia_balanca') ?? false,
      fotosUrls: getList('fotosUrls', 'fotos_urls')?.cast<String>() ?? [],
      fotoPrincipalUrl: getStr('fotoPrincipalUrl', 'foto_principal_url'),
      descricaoEcommerce: getStr('descricaoEcommerce', 'descricao_ecommerce'),
      pesoGramas: getNum('pesoGramas', 'peso_gramas')?.toInt(),
      alturaCm: getNum('alturaCm', 'altura_cm')?.toDouble(),
      larguraCm: getNum('larguraCm', 'largura_cm')?.toDouble(),
      profundidadeCm: getNum('profundidadeCm', 'profundidade_cm')?.toDouble(),
      tags: getList('tags', 'tags')?.cast<String>() ?? [],
      variacoes: getList('variacoes', 'variacoes')?.map((v) => VariacaoProduto.fromMap(v as Map<String, dynamic>)).toList() ?? [],
      temVariacoes: getBool('temVariacoes', 'tem_variacoes') ?? false,
      adicionais: getList('adicionais', 'adicionais')?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>)).toList() ?? [],
      temAdicionais: getBool('temAdicionais', 'tem_adicionais') ?? false,
      ehComposto: getBool('ehComposto', 'eh_composto') ?? false,
      composicao: getList('composicao', 'composicao')?.map((c) => ItemComposicao.fromMap(c as Map<String, dynamic>)).toList() ?? [],
      observacaoPadrao: getStr('observacaoPadrao', 'observacao_padrao'),
      fornecedorId: getStr('fornecedorId', 'fornecedor_id'),
      fornecedorNome: getStr('fornecedorNome', 'fornecedor_nome'),
      estoquePorFornecedor: getMap('estoquePorFornecedor', 'estoque_por_fornecedor')?.map((k, v) => MapEntry(k as String, (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0))) ?? {},
      pedidoCompraGerado: getBool('pedidoCompraGerado', 'pedido_compra_gerado') ?? false,
      dataUltimoPedido: getDate('dataUltimoPedido', 'data_ultimo_pedido'),
    );
  }

  /// Cria uma cópia do produto com campos atualizados
  Produto copyWith({
    String? id,
    String? codigo,
    String? codigoBarras,
    String? nome,
    String? descricao,
    String? unidade,
    String? grupo,
    double? preco,
    double? precoCusto,
    double? estoque,
    double? estoqueMinimo,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? precoPromocional,
    DateTime? promocaoInicio,
    DateTime? promocaoFim,
    List<String>? codigosFornecedor,
    String? ncm,
    double? icmsAliquota,
    String? icmsCst,
    double? ipiAliquota,
    String? ipiCst,
    double? pisAliquota,
    String? pisCst,
    double? cofinsAliquota,
    String? cofinsCst,
    double? issAliquota,
    String? origem,
    String? cfop,
    String? cest,
    String? csosn,
    double? simplesNacionalAliquota,
    bool? paraCozinha,
    bool? paraBar,
    bool? exibirNaLoja,
    bool? emDestaque,
    List<String>? fotosUrls,
    String? fotoPrincipalUrl,
    String? descricaoEcommerce,
    int? pesoGramas,
    double? alturaCm,
    double? larguraCm,
    double? profundidadeCm,
    List<String>? tags,
    List<VariacaoProduto>? variacoes,
    bool? temVariacoes,
    List<AdicionalProduto>? adicionais,
    bool? temAdicionais,
    bool? ehComposto,
    List<ItemComposicao>? composicao,
    String? observacaoPadrao,
    String? fornecedorId,
    String? fornecedorNome,
    Map<String, double>? estoquePorFornecedor,
    bool? pedidoCompraGerado,
    DateTime? dataUltimoPedido,
    bool? enviaBalanca,
  }) {
    return Produto(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      unidade: unidade ?? this.unidade,
      grupo: grupo ?? this.grupo,
      preco: preco ?? this.preco,
      precoCusto: precoCusto ?? this.precoCusto,
      estoque: estoque ?? this.estoque,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      precoPromocional: precoPromocional ?? this.precoPromocional,
      promocaoInicio: promocaoInicio ?? this.promocaoInicio,
      promocaoFim: promocaoFim ?? this.promocaoFim,
      codigosFornecedor: codigosFornecedor ?? this.codigosFornecedor,
      ncm: ncm ?? this.ncm,
      icmsAliquota: icmsAliquota ?? this.icmsAliquota,
      icmsCst: icmsCst ?? this.icmsCst,
      ipiAliquota: ipiAliquota ?? this.ipiAliquota,
      ipiCst: ipiCst ?? this.ipiCst,
      pisAliquota: pisAliquota ?? this.pisAliquota,
      pisCst: pisCst ?? this.pisCst,
      cofinsAliquota: cofinsAliquota ?? this.cofinsAliquota,
      cofinsCst: cofinsCst ?? this.cofinsCst,
      issAliquota: issAliquota ?? this.issAliquota,
      origem: origem ?? this.origem,
      cfop: cfop ?? this.cfop,
      cest: cest ?? this.cest,
      csosn: csosn ?? this.csosn,
      simplesNacionalAliquota: simplesNacionalAliquota ?? this.simplesNacionalAliquota,
      paraCozinha: paraCozinha ?? this.paraCozinha,
      paraBar: paraBar ?? this.paraBar,
      exibirNaLoja: exibirNaLoja ?? this.exibirNaLoja,
      emDestaque: emDestaque ?? this.emDestaque,
      fotosUrls: fotosUrls ?? this.fotosUrls,
      fotoPrincipalUrl: fotoPrincipalUrl ?? this.fotoPrincipalUrl,
      descricaoEcommerce: descricaoEcommerce ?? this.descricaoEcommerce,
      pesoGramas: pesoGramas ?? this.pesoGramas,
      alturaCm: alturaCm ?? this.alturaCm,
      larguraCm: larguraCm ?? this.larguraCm,
      profundidadeCm: profundidadeCm ?? this.profundidadeCm,
      tags: tags ?? this.tags,
      variacoes: variacoes ?? this.variacoes,
      temVariacoes: temVariacoes ?? this.temVariacoes,
      adicionais: adicionais ?? this.adicionais,
      temAdicionais: temAdicionais ?? this.temAdicionais,
      ehComposto: ehComposto ?? this.ehComposto,
      composicao: composicao ?? this.composicao,
      observacaoPadrao: observacaoPadrao ?? this.observacaoPadrao,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      estoquePorFornecedor: estoquePorFornecedor ?? this.estoquePorFornecedor,
      pedidoCompraGerado: pedidoCompraGerado ?? this.pedidoCompraGerado,
      dataUltimoPedido: dataUltimoPedido ?? this.dataUltimoPedido,
      enviaBalanca: enviaBalanca ?? this.enviaBalanca,
    );
  }
  
  // Getter para foto principal (primeira foto ou fotoPrincipalUrl)
  String? get fotoPrincipal => fotoPrincipalUrl ?? (fotosUrls.isNotEmpty ? fotosUrls.first : null);
  
  // Verifica se tem fotos
  bool get temFotos => fotosUrls.isNotEmpty;
  
  /// Verifica se um código do fornecedor corresponde a este produto
  bool temCodigoFornecedor(String codigoFornecedor) {
    return codigosFornecedor.contains(codigoFornecedor);
  }
  
  /// Adiciona um código do fornecedor (sem duplicatas)
  Produto adicionarCodigoFornecedor(String codigoFornecedor) {
    if (codigosFornecedor.contains(codigoFornecedor)) {
      return this; // Já existe, retorna o mesmo produto
    }
    return copyWith(
      codigosFornecedor: [...codigosFornecedor, codigoFornecedor],
      updatedAt: DateTime.now(),
    );
  }
}

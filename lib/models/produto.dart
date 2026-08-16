import 'package:sistema_exodo_novo/utils/date_parser.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/item_composicao.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';
import 'package:sistema_exodo_novo/models/forma_venda.dart';
import 'package:sistema_exodo_novo/models/regra_promocao.dart';

class Produto {
  final String id;
  final String? codigo; // Pode ser null para produtos antigos
  final String? codigoBarras; // Código de barras principal (EAN, UPC, etc)
  final List<String> codigosBarrasAdicionais; // Códigos de barras extras (mesmo produto pode ter vários EANs)
  final String nome;
  final String? descricao;
  final String unidade;
  // Forma de venda do produto: 'unidade', 'caixa', 'pacote' ou 'saco'.
  // Embalagens (caixa/pacote/saco) contêm N unidades internas (quantidadeBaixa).
  final String unidadeVenda;
  // Quantidade de unidades baixadas do estoque a cada 1 item vendido.
  // Ex.: 1 caixa contém 12 unidades -> vende 1 caixa, baixa 12 do estoque.
  final double quantidadeBaixa;
  // Múltiplas formas de venda do mesmo produto (cada uma com preço e baixa
  // próprios). Ex.: vender por unidade E por caixa sem cadastrar itens duplicados.
  // Quando vazio, o PDV usa a forma principal (unidadeVenda/quantidadeBaixa/preco).
  final List<FormaVenda> formasVenda;
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
  // Regras avançadas de promoção (empilháveis): por data, dia da semana,
  // quantidade mínima ou valor mínimo no carrinho. Os descontos somam-se ao
  // desconto da promoção simples (precoPromocional) quando aplicáveis.
  final List<RegraPromocao> promocoes;
  
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
  final String? departamentoId; // Departamento/setor de preparação (ex: "Cozinha", "Bar", "Sobremesas") — entidade separada da impressora
  final String? impressoraProducao; // Nome/Setor da impressora de produção (ex: "Cozinha", "Bar", ou nome da impressora Windows)
  final List<String> impressoraProducaoExtra; // Outros setores/impressoras onde o produto também deve imprimir (multi-seleção)
  
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
  // Quando true (padrão), a venda deste produto composto também baixa o estoque
  // dele mesmo. Quando false, a baixa acontece APENAS nos ingredientes (ideal
  // para produtos tipo Chop/Chopp: o controle é no barril, o chop é "ilimitado").
  final bool baixarEstoqueProprio;
  
  // Tracking de Pedidos de Compra
  final bool pedidoCompraGerado;
  final DateTime? dataUltimoPedido;

  // Mapeamento de estoque por fornecedor (Ex: {"Ambev": 10.0, "Coca": 10.0})
  final Map<String, double> estoquePorFornecedor; 
  final bool enviaBalanca;
  final bool cobrarGarcom; // Se true, cobra os 10% de taxa de garçom no PDV/Comandas
  final String? perfilTributarioId; // ID do Perfil Tributário (impostos)
  final List<PerguntaSelecao> perguntasSelecao;
  final bool exibirComposicaoPdv;
  final Map<String, double>? precosPorPerfil;
  final List<RegraQuantidade>? regrasQuantidade;
 // Se true, produto é enviado para a balança 

  Produto({
    required this.id,
    this.codigo,
    this.codigoBarras,
    List<String>? codigosBarrasAdicionais,
    required this.nome,
    this.descricao,
    required this.unidade,
    this.unidadeVenda = 'unidade',
    this.quantidadeBaixa = 1.0,
    List<FormaVenda>? formasVenda,
    required this.grupo,
    required this.preco,
    this.precoCusto,
    required this.estoque,
    required this.createdAt,
    required this.updatedAt,
    this.precoPromocional,
    this.promocaoInicio,
    this.promocaoFim,
    List<RegraPromocao>? promocoes,
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
    this.departamentoId,
    this.impressoraProducao,
    this.impressoraProducaoExtra = const [],
    this.exibirNaLoja = false,
    this.emDestaque = false,
    this.enviaBalanca = false,
    this.cobrarGarcom = true,
    this.perfilTributarioId,
    this.perguntasSelecao = const [],
    this.exibirComposicaoPdv = false,

    List<String>? fotosUrls,
    this.fotoPrincipalUrl,
    this.descricaoEcommerce,
    this.pesoGramas,
    this.alturaCm,
    this.larguraCm,
    this.profundidadeCm,
    this.precosPorPerfil,
    this.regrasQuantidade,
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
    this.baixarEstoqueProprio = true,
    List<ItemComposicao>? composicao,
    this.pedidoCompraGerado = false,
    this.dataUltimoPedido,
    Map<String, double>? estoquePorFornecedor,
  }) : codigosFornecedor = codigosFornecedor ?? [],
       codigosBarrasAdicionais = codigosBarrasAdicionais ?? [],
       fotosUrls = fotosUrls ?? [],
       tags = tags ?? [],
       variacoes = variacoes ?? [],
       temVariacoes = temVariacoes ?? false,
       adicionais = adicionais ?? [],
       temAdicionais = temAdicionais ?? false,
       composicao = composicao ?? [],
       estoquePorFornecedor = estoquePorFornecedor ?? {},
       formasVenda = formasVenda ?? [],
       promocoes = promocoes ?? [];

  /// Todos os códigos de barras do produto (principal + adicionais),
  /// sem duplicatas e sem valores vazios. Usado na busca por código de barras.
  List<String> get todosCodigosBarras {
    final todos = <String>[];
    if (codigoBarras != null && codigoBarras!.trim().isNotEmpty) {
      todos.add(codigoBarras!.trim());
    }
    for (final codigo in codigosBarrasAdicionais) {
      final valor = codigo.trim();
      if (valor.isNotEmpty &&
          !todos.any((t) => t.toLowerCase() == valor.toLowerCase())) {
        todos.add(valor);
      }
    }
    return todos;
  }

  /// Fator de baixa no estoque: quantas unidades saem a cada 1 item vendido.
  /// Se não configurado (<= 0), assume 1 (venda unitária padrão).
  double get fatorBaixaEstoque => quantidadeBaixa > 0 ? quantidadeBaixa : 1.0;

  /// Lista de formas de venda efetiva do produto.
  ///
  /// Se [formasVenda] estiver vazia (produtos antigos), devolve uma lista com
  /// uma única forma derivada dos campos legados (unidadeVenda/quantidadeBaixa/preco)
  /// para que o PDV continue funcionando normalmente.
  List<FormaVenda> get formasVendaEfetivas {
    if (formasVenda.isNotEmpty) return formasVenda;
    return [
      FormaVenda(
        tipo: unidadeVenda.isEmpty ? 'unidade' : unidadeVenda,
        quantidadeBaixa: quantidadeBaixa > 0 ? quantidadeBaixa : 1.0,
        preco: preco,
      ),
    ];
  }

  /// True se o produto tem mais de uma forma de venda configurada
  /// (o PDV pergunta qual forma usar ao vender).
  bool get temMultiplasFormasVenda => formasVendaEfetivas.length > 1;

  /// Busca uma forma de venda pelo tipo. Retorna null se não existir.
  FormaVenda? formaVendaPorTipo(String tipo) {
    for (final f in formasVendaEfetivas) {
      if (f.tipo == tipo) return f;
    }
    return null;
  }

  /// Preço da forma de venda. Se a forma não estiver configurada
  /// (produtos antigos), retorna o preço principal do produto.
  double precoDaFormaVenda(String tipo) {
    final forma = formaVendaPorTipo(tipo);
    return forma?.preco ?? preco;
  }

  /// Quantidade de baixa da forma de venda. Se a forma não estiver
  /// configurada, retorna a baixa principal (fatorBaixaEstoque).
  double quantidadeBaixaDaForma(String tipo) {
    final forma = formaVendaPorTipo(tipo);
    return forma?.quantidadeBaixa ?? fatorBaixaEstoque;
  }

  /// True se o produto é vendido por embalagem (caixa, pacote ou saco).
  /// Nesses casos o PDV informa a quantidade em embalagens e o estoque
  /// baixa em unidades (quantidadeBaixa por embalagem).
  bool get vendePorEmbalagem =>
      unidadeVenda == 'caixa' ||
      unidadeVenda == 'pacote' ||
      unidadeVenda == 'saco';

  /// Rótulo amigável da forma de venda (para exibição no PDV e formulário).
  /// Para valores desconhecidos (dados legados), devolve o valor em maiúsculas.
  String get unidadeVendaLabel {
    switch (unidadeVenda) {
      case 'caixa':
        return 'CAIXA';
      case 'pacote':
        return 'PACOTE';
      case 'saco':
        return 'SACO';
      case 'unidade':
        return 'UNIDADE';
      default:
        return unidadeVenda.isEmpty ? 'UNIDADE' : unidadeVenda.toUpperCase();
    }
  }

  /// Percentual de desconto da promoção simples (precoPromocional) no momento.
  /// Aceita datas nulas: se a data de início/fim não foi definida, a condição
  /// correspondente é ignorada (promoção sempre ativa).
  double _descontoPromocaoSimples([DateTime? agora]) {
    if (precoPromocional == null || precoPromocional! <= 0 || preco <= 0) return 0;
    final a = agora ?? DateTime.now();
    if (promocaoInicio != null && a.isBefore(promocaoInicio!)) return 0;
    if (promocaoFim != null && a.isAfter(promocaoFim!)) return 0;
    final pct = (preco - precoPromocional!) / preco * 100;
    return pct > 0 ? pct : 0;
  }

  /// Percentual de desconto total (empilhado) aplicável no momento.
  ///
  /// [quantidade] = quantidade do produto no carrinho;
  /// [subtotalItem] = subtotal do produto no carrinho (qtd × preço) para as
  /// regras de valor mínimo; se nulo, usa quantidade × preço.
  double descontoPromocionalAtual({
    double quantidade = 1.0,
    double? subtotalItem,
    DateTime? agora,
  }) {
    final subtotal = subtotalItem ?? quantidade * preco;
    double total = _descontoPromocaoSimples(agora);
    for (final r in promocoes) {
      if (r.aplicaPara(quantidade: quantidade, subtotalItem: subtotal, agora: agora)) {
        total += r.contribuicaoPercentual(preco);
      }
    }
    return total.clamp(0.0, 99.0);
  }

  /// Aplica os descontos promocionais (empilhados) sobre um preço base.
  double aplicarPromocoes(
    double precoBase, {
    double quantidade = 1.0,
    double? subtotalItem,
    DateTime? agora,
  }) {
    final desconto = descontoPromocionalAtual(
      quantidade: quantidade,
      subtotalItem: subtotalItem,
      agora: agora,
    );
    if (desconto <= 0) return precoBase;
    return precoBase * (1 - desconto / 100);
  }

  /// Verifica se há alguma promoção ativa neste momento (para exibir selos).
  /// Regras de quantidade/valor mínimo contam como ativas quando dentro da
  /// janela de tempo (a condição de carrinho é avaliada no fechamento).
  bool get promocaoAtiva {
    if (_descontoPromocaoSimples() > 0) return true;
    return promocoes.any((r) => r.ativo && r.janelaValidaNoMomento());
  }

  /// Retorna o preço atual considerando as promoções ativas no momento,
  /// sem contexto de carrinho (quantidade 1). No PDV, o preço real é calculado
  /// com [aplicarPromocoes] usando a quantidade/subtotal do item.
  double get precoAtual {
    final desconto = descontoPromocionalAtual(quantidade: 1.0, subtotalItem: preco);
    return desconto > 0 ? preco * (1 - desconto / 100) : preco;
  }
  
  // Retorna o preço do produto aplicando as regras de perfil e quantidade
  double getPrecoInteligente({
    String? perfilCliente, 
    double modificadorPerfil = 0.0, 
    String tipoModificador = 'desconto', // 'desconto' ou 'acrescimo'
    double quantidade = 1.0,
  }) {
    double precoAtual = preco; // Inicia com o preço de venda padrão

    bool precoFoiFixo = false;

    // 1. Aplica o preço do perfil (Preço Fixo no Produto), se existir e for maior que 0
    // O preço fixo tem prioridade sobre o desconto/acréscimo global.
    if (perfilCliente != null && precosPorPerfil != null && precosPorPerfil!.containsKey(perfilCliente)) {
      final precoPerfil = precosPorPerfil![perfilCliente];
      if (precoPerfil != null && precoPerfil > 0) {
        precoAtual = precoPerfil;
        precoFoiFixo = true;
      }
    }

    // 2. Aplica o Modificador Global do Perfil (se não houver preço fixo)
    if (!precoFoiFixo && modificadorPerfil > 0) {
      if (tipoModificador == 'desconto') {
        precoAtual = precoAtual * (1 - (modificadorPerfil / 100));
      } else if (tipoModificador == 'acrescimo') {
        precoAtual = precoAtual * (1 + (modificadorPerfil / 100));
      }
    }

    // 3. Aplica regras de quantidade (Atacarejo) - pega a maior quantidade atingida
    if (regrasQuantidade != null && regrasQuantidade!.isNotEmpty) {
      // Ordenar decrescente para pegar a regra mais vantajosa (maior quantidade) primeiro
      final regrasOrdenadas = List<RegraQuantidade>.from(regrasQuantidade!)
        ..sort((a, b) => b.quantidadeMinima.compareTo(a.quantidadeMinima));
        
      for (var regra in regrasOrdenadas) {
        if (quantidade >= regra.quantidadeMinima && regra.preco > 0) {
          // Só aplica se o preço de atacarejo for menor que o preço atual (para beneficiar o cliente)
          if (regra.preco < precoAtual) {
            precoAtual = regra.preco;
          }
          break; // Achou a maior regra que atende
        }
      }
    }

    return precoAtual;
  }

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

  // Calcula o percentual de desconto total (empilhado) no momento
  double get percentualDesconto {
    return descontoPromocionalAtual(quantidade: 1.0, subtotalItem: preco);
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
      'codigos_barras_adicionais': codigosBarrasAdicionais,
      'nome': nome,
      'descricao': descricao,
      'unidade': unidade,
      'unidade_venda': unidadeVenda,
      'quantidade_baixa': quantidadeBaixa,
      'formas_venda': formasVenda.map((f) => f.toMap()).toList(),
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
      'promocoes': promocoes.map((r) => r.toMap()).toList(),
      'codigos_fornecedor': codigosFornecedor,
      'ncm': ncm,
      'icms_aliquota': icmsAliquota,
      'icms_cst': icmsCst,
      'ipi_aliquota': ipiAliquota,
      'ipi_cst': ipiCst,
      'pis_aliquota': pisAliquota,
      'pis_cst': pisCst,
      'precos_por_perfil': precosPorPerfil,
      'regras_quantidade': regrasQuantidade?.map((r) => r.toMap()).toList(),
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
      'departamento_id': departamentoId,
      'impressora_producao': impressoraProducao,
      'impressora_producao_extra': impressoraProducaoExtra,
      'exibir_na_loja': exibirNaLoja,
      'em_destaque': emDestaque,
      'envia_balanca': enviaBalanca,
      'cobrar_garcom': cobrarGarcom,
      'perfil_tributario_id': perfilTributarioId,
      'perguntas_selecao': perguntasSelecao.map((p) => p.toMap()).toList(),
      'exibir_composicao_pdv': exibirComposicaoPdv,

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
      'baixar_estoque_proprio': baixarEstoqueProprio,
      'composicao': composicao.map((c) => c.toMap()).toList(),
      'observacao_padrao': observacaoPadrao,
      'fornecedor_id': fornecedorId,
      'fornecedor_nome': fornecedorNome,
      'estoque_por_fornecedor': estoquePorFornecedor,
      'pedido_compra_gerado': pedidoCompraGerado,
      'data_ultimo_pedido': dataUltimoPedido?.toIso8601String(),
    };
  }

  /// Converte o valor de códigos de barras adicionais vindo do banco/JSON
  /// (pode ser List, ou String separada por ';'/'|' em bancos antigos).
  static List<String> _parseListaCodigosBarras(dynamic value) {
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[;|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
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
      codigosBarrasAdicionais: _parseListaCodigosBarras(get<dynamic>('codigosBarrasAdicionais', 'codigos_barras_adicionais')),
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      unidade: map['unidade'] as String? ?? '',
      unidadeVenda: getStr('unidadeVenda', 'unidade_venda') ?? 'unidade',
      quantidadeBaixa: getNum('quantidadeBaixa', 'quantidade_baixa')?.toDouble() ?? 1.0,
      formasVenda: (getList('formasVenda', 'formas_venda') ?? [])
          .map((f) => FormaVenda.fromMap(Map<String, dynamic>.from(f is Map ? f : {})))
          .toList(),
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
      promocoes: (getList('promocoes', 'promocoes') ?? [])
          .map((r) => RegraPromocao.fromMap(Map<String, dynamic>.from(r is Map ? r : {})))
          .toList(),
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
      departamentoId: getStr('departamentoId', 'departamento_id'),
      impressoraProducao: (map['impressoraProducao'] ?? map['impressora_producao']) as String?,
      impressoraProducaoExtra: (getList('impressoraProducaoExtra', 'impressora_producao_extra') ?? [])
          .map((e) => e.toString())
          .toList(),
      exibirNaLoja: getBool('exibirNaLoja', 'exibir_na_loja') ?? false,
      emDestaque: getBool('emDestaque', 'em_destaque') ?? false,
      enviaBalanca: getBool('enviaBalanca', 'envia_balanca') ?? false,
      cobrarGarcom: getBool('cobrarGarcom', 'cobrar_garcom') ?? true,
      perfilTributarioId: getStr('perfilTributarioId', 'perfil_tributario_id'),
      perguntasSelecao: getList('perguntasSelecao', 'perguntas_selecao')?.map((p) => PerguntaSelecao.fromMap(Map<String, dynamic>.from(p is Map ? p : {}))).toList() ?? [],
      exibirComposicaoPdv: getBool('exibirComposicaoPdv', 'exibir_composicao_pdv') ?? false,

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
      baixarEstoqueProprio: getBool('baixarEstoqueProprio', 'baixar_estoque_proprio') ?? true,
      composicao: getList('composicao', 'composicao')?.map((c) => ItemComposicao.fromMap(c as Map<String, dynamic>)).toList() ?? [],
      observacaoPadrao: getStr('observacaoPadrao', 'observacao_padrao'),
      fornecedorId: getStr('fornecedorId', 'fornecedor_id'),
      fornecedorNome: getStr('fornecedorNome', 'fornecedor_nome'),
      estoquePorFornecedor: getMap('estoquePorFornecedor', 'estoque_por_fornecedor')?.map((k, v) => MapEntry(k as String, (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0))) ?? {},
      pedidoCompraGerado: getBool('pedidoCompraGerado', 'pedido_compra_gerado') ?? false,
      dataUltimoPedido: getDate('dataUltimoPedido', 'data_ultimo_pedido'),
      precosPorPerfil: getMap('precosPorPerfil', 'precos_por_perfil')?.map((k, v) => MapEntry(k as String, (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0))),
      regrasQuantidade: getList('regrasQuantidade', 'regras_quantidade')?.map((r) => RegraQuantidade.fromMap(Map<String, dynamic>.from(r is Map ? r : {}))).toList(),
    );
  }

  /// Cria uma cópia do produto com campos atualizados
  Produto copyWith({
    String? id,
    String? codigo,
    String? codigoBarras,
    List<String>? codigosBarrasAdicionais,
    String? nome,
    String? descricao,
    String? unidade,
    String? unidadeVenda,
    double? quantidadeBaixa,
    List<FormaVenda>? formasVenda,
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
    List<RegraPromocao>? promocoes,
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
    String? departamentoId,
    String? impressoraProducao,
    List<String>? impressoraProducaoExtra,
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
    bool? baixarEstoqueProprio,
    List<ItemComposicao>? composicao,
    String? observacaoPadrao,
    String? fornecedorId,
    String? fornecedorNome,
    Map<String, double>? estoquePorFornecedor,
    bool? pedidoCompraGerado,
    DateTime? dataUltimoPedido,
    bool? enviaBalanca,
    bool? cobrarGarcom,
    String? perfilTributarioId,
    List<PerguntaSelecao>? perguntasSelecao,
    bool? exibirComposicaoPdv,

  }) {
    return Produto(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      codigosBarrasAdicionais: codigosBarrasAdicionais ?? this.codigosBarrasAdicionais,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      unidade: unidade ?? this.unidade,
      unidadeVenda: unidadeVenda ?? this.unidadeVenda,
      quantidadeBaixa: quantidadeBaixa ?? this.quantidadeBaixa,
      formasVenda: formasVenda ?? this.formasVenda,
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
      promocoes: promocoes ?? this.promocoes,
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
      departamentoId: departamentoId ?? this.departamentoId,
      impressoraProducao: impressoraProducao ?? this.impressoraProducao,
      impressoraProducaoExtra: impressoraProducaoExtra ?? this.impressoraProducaoExtra,
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
      baixarEstoqueProprio: baixarEstoqueProprio ?? this.baixarEstoqueProprio,
      composicao: composicao ?? this.composicao,
      observacaoPadrao: observacaoPadrao ?? this.observacaoPadrao,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      estoquePorFornecedor: estoquePorFornecedor ?? this.estoquePorFornecedor,
      pedidoCompraGerado: pedidoCompraGerado ?? this.pedidoCompraGerado,
      dataUltimoPedido: dataUltimoPedido ?? this.dataUltimoPedido,
      enviaBalanca: enviaBalanca ?? this.enviaBalanca,
      cobrarGarcom: cobrarGarcom ?? this.cobrarGarcom,
      perfilTributarioId: perfilTributarioId ?? this.perfilTributarioId,
      perguntasSelecao: perguntasSelecao ?? this.perguntasSelecao,
      exibirComposicaoPdv: exibirComposicaoPdv ?? this.exibirComposicaoPdv,

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


class RegraQuantidade {
  final double quantidadeMinima;
  final double preco;

  RegraQuantidade({required this.quantidadeMinima, required this.preco});

  Map<String, dynamic> toMap() => {
    'quantidadeMinima': quantidadeMinima,
    'preco': preco,
  };

  factory RegraQuantidade.fromMap(Map<String, dynamic> map) => RegraQuantidade(
    quantidadeMinima: map['quantidadeMinima'] != null ? (map['quantidadeMinima'] as num).toDouble() : 0.0,
    preco: map['preco'] != null ? (map['preco'] as num).toDouble() : 0.0,
  );
}

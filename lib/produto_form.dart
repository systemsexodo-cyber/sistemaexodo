import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/codigo_service.dart';
import 'package:sistema_exodo_novo/services/grupos_manager.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/forma_venda.dart';
import 'package:sistema_exodo_novo/models/regra_promocao.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/lote_produto.dart';
import 'package:sistema_exodo_novo/models/produto_historico.dart';
import 'package:sistema_exodo_novo/utils/units.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/services/image_storage_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/item_composicao.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';
import 'package:sistema_exodo_novo/services/impressao_service.dart';
import 'package:sistema_exodo_novo/services/producao_pdf_service.dart';
import 'package:sistema_exodo_novo/models/permissao.dart';
import 'package:sistema_exodo_novo/services/permission_service.dart';
import 'package:uuid/uuid.dart';

class ProdutoServicoForm extends StatefulWidget {
  final dynamic item; // Produto ou Servico
  final Function(dynamic) onSave;

  const ProdutoServicoForm({super.key, this.item, required this.onSave});

  @override
  State<ProdutoServicoForm> createState() => _ProdutoServicoFormState();
}

class _ProdutoServicoFormState extends State<ProdutoServicoForm> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  
  final _codigoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _unidadeController = TextEditingController();
  final _grupoController = TextEditingController();
  final _subgrupoController = TextEditingController();
  final _precoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _precoPromocionalController = TextEditingController();

  // Precificação Inteligente
  final Map<String, TextEditingController> _precosPerfilControllers = {};
  final Set<String> _tabelasPrecoSelecionadas = {};
  List<RegraQuantidade> _regrasQuantidade = [];

  final _fornecedorNomeController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  final _observacaoPadraoController = TextEditingController();

  // Forma de venda: 'unidade' ou 'caixa' + quantidade de baixa no estoque
  final _quantidadeBaixaController = TextEditingController();
  String _unidadeVenda = 'unidade';
  // Múltiplas formas de venda do produto (cada uma com preço e baixa próprios)
  List<FormaVenda> _formasVenda = [];
  
  // Controllers para impostos
  final _ncmController = TextEditingController();
  final _icmsAliquotaController = TextEditingController();
  final _icmsCstController = TextEditingController();
  final _ipiAliquotaController = TextEditingController();
  final _ipiCstController = TextEditingController();
  final _pisAliquotaController = TextEditingController();
  final _pisCstController = TextEditingController();
  final _cofinsAliquotaController = TextEditingController();
  final _cofinsCstController = TextEditingController();
  final _issAliquotaController = TextEditingController();
  final _origemController = TextEditingController();
  final _cfopController = TextEditingController();
  final _cestController = TextEditingController();
  
  // Controllers para Simples Nacional
  final _csosnController = TextEditingController();
  final _simplesNacionalAliquotaController = TextEditingController();
  
  late String _codigo;
  late String _codigoBarras;
  // Códigos de barras adicionais (um produto pode ter vários EANs)
  final List<TextEditingController> _codigosBarrasAdicionaisControllers = [];

  List<String> _coletarCodigosBarrasAdicionais() {
    final extras = <String>[];
    final principalLower = _codigoBarras.trim().toLowerCase();
    for (final controller in _codigosBarrasAdicionaisControllers) {
      final valor = controller.text.trim();
      final valorLower = valor.toLowerCase();
      if (valor.isNotEmpty &&
          valorLower != principalLower &&
          !extras.any((e) => e.toLowerCase() == valorLower)) {
        extras.add(valor);
      }
    }
    return extras;
  }

  late String _nome;
  late String _descricao;
  late String _unidade;
  late String _grupo;
  late String _subgrupo;
  late double _quantidadeBaixa;
  late double _preco;
  late double? _precoCusto;
  late double _estoque;
  Map<String, double> _estoquePorFornecedor = {};
  String? _fornecedorId;
  bool _codigoEditavel = false; // Controlar se código é editável

  // Campos de promoção
  bool _temPromocao = false;
  double? _precoPromocional;
  DateTime? _promocaoInicio;
  DateTime? _promocaoFim;
  // Regras avançadas de promoção (empilháveis): por data, dia da semana,
  // quantidade mínima ou valor mínimo no carrinho.
  List<RegraPromocao> _promocoes = [];
  
  // Campos de impostos
  String? _ncm;
  double? _icmsAliquota;
  String? _icmsCst;
  double? _ipiAliquota;
  String? _ipiCst;
  double? _pisAliquota;
  String? _pisCst;
  double? _cofinsAliquota;
  String? _cofinsCst;
  double? _issAliquota;
  String? _origem;
  String? _cfop;
  String? _cest;
  String? _perfilTributarioId; // ID do Perfil Tributário selecionado
  
  // Campos do Simples Nacional
  String? _csosn;
  double? _simplesNacionalAliquota;
  // Campos de E-commerce
  bool _exibirNaLoja = false;
  bool _emDestaque = false;
  List<String> _fotosUrls = [];
  String? _descricaoEcommerce;
  int? _pesoGramas;
  double? _alturaCm;
  double? _larguraCm;
  double? _profundidadeCm;
  List<String> _tags = [];
  final _descricaoEcommerceController = TextEditingController();
  final _pesoGramasController = TextEditingController();
  final _alturaCmController = TextEditingController();
  final _larguraCmController = TextEditingController();
  final _profundidadeCmController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _uploadingFotos = false;
  
  // Campos para variações
  List<VariacaoProduto> _variacoes = [];
  bool _temVariacoes = false;
  
  // Campos para preparação
  bool _paraCozinha = false;
  bool _paraBar = false;
  String? _departamentoId; // Departamento/setor de preparação (entidade separada da impressora)
  List<String> _departamentosAdicionais = []; // Outros DEPARTAMENTOS onde o produto também deve imprimir (multi-seleção)
  bool _enviaBalanca = false;
  String? _impressoraProducao; // Legado
  List<String> _impressoraProducaoExtra = []; // Outras impressoras onde o produto também deve imprimir (multi-seleção)
  List<String> _codigosFornecedor = [];
  
  // Campos para Adicionais
  List<AdicionalProduto> _adicionais = [];
  bool _temAdicionais = false;
  final _uuid = const Uuid();
  
  // Campos para Composição
  bool _ehComposto = false;
  bool _exibirComposicaoPdv = false;
  // true = vender o composto também baixa o estoque dele mesmo (padrão);
  // false = baixa apenas nos ingredientes (ex.: Chop controlado pelo Barril).
  bool _baixarEstoqueProprio = true;
  List<ItemComposicao> _composicao = [];
  List<PerguntaSelecao> _perguntasSelecao = [];
  
  // Variáveis para a aba de estoque
  DateTime? _estoqueDataInicial;
  DateTime? _estoqueDataFinal;
  String? _estoqueTipoFiltro;
  bool _estoqueVisaoGeral = false;

  @override
  void initState() {
    super.initState();
    _estoqueDataInicial = DateTime.now().subtract(const Duration(days: 30));
    _estoqueDataFinal = DateTime.now();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    // Adicionar listener para atualizar contador de caracteres
    _descricaoController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    if (widget.item != null) {
      // Editando produto existente
      _codigo = widget.item?.codigo ?? '';
      _codigoEditavel = (widget.item?.id ?? '').isEmpty; // Editável se for um clone (ID vazio)
      if (_codigo.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _gerarProximoCodigo();
        });
      }
      _codigoBarras = widget.item?.codigoBarras ?? '';
      _nome = widget.item?.nome ?? '';
      _descricao = widget.item?.descricao ?? '';
      _unidade = (widget.item?.unidade ?? '').isNotEmpty
          ? widget.item!.unidade
          : 'peça';
      _grupo = widget.item?.grupo ?? 'Sem Grupo';
      _subgrupo = widget.item is Produto
          ? (widget.item as Produto).subgrupo
          : '';
      _preco = widget.item?.preco ?? 0.0;
      _precoCusto = widget.item?.precoCusto;
      _estoque = widget.item?.estoque ?? 0.0;
      _codigoController.text = _codigo;
      _codigoBarrasController.text = _codigoBarras;
      // Carregar códigos de barras adicionais do produto em edição
      for (final c in _codigosBarrasAdicionaisControllers) {
        c.dispose();
      }
      _codigosBarrasAdicionaisControllers.clear();
      for (final extra in widget.item?.codigosBarrasAdicionais ?? <String>[]) {
        _codigosBarrasAdicionaisControllers.add(TextEditingController(text: extra));
      }
      _descricaoController.text = _descricao;
      _unidadeController.text = _unidade;
      // Forma de venda (caixa/unidade) e quantidade de baixa
      _unidadeVenda = widget.item is Produto
          ? (widget.item as Produto).unidadeVenda
          : 'unidade';
      _quantidadeBaixa = widget.item is Produto
          ? (widget.item as Produto).quantidadeBaixa
          : 1.0;
      _quantidadeBaixaController.text =
          _quantidadeBaixa > 0 ? _quantidadeBaixa.toString() : '1';
      // Carregar múltiplas formas de venda (migração: vazio = forma principal)
      _formasVenda = widget.item is Produto
          ? List<FormaVenda>.from((widget.item as Produto).formasVendaEfetivas)
          : [];
      _grupoController.text = _grupo;
      _subgrupoController.text = _subgrupo;
      _precoController.text = _preco.toString();
      _precoCustoController.text = _precoCusto?.toString() ?? '';
      _estoqueController.text = _estoque.toString();
      _fornecedorId = widget.item?.fornecedorId;
      _estoquePorFornecedor = Map<String, double>.from(widget.item?.estoquePorFornecedor ?? {});
      _fornecedorNomeController.text = widget.item?.fornecedorNome ?? '';
      _estoqueMinimoController.text = (widget.item?.estoqueMinimo ?? 0).toString();

      // Carregar dados de promoção
      _precoPromocional = widget.item?.precoPromocional;
      _promocaoInicio = widget.item?.promocaoInicio;
      _promocaoFim = widget.item?.promocaoFim;
      _temPromocao = _precoPromocional != null;
      if (_precoPromocional != null) {
        _precoPromocionalController.text = _precoPromocional.toString();
      }
      _promocoes = List<RegraPromocao>.from(widget.item?.promocoes ?? []);
      
      // Carregar campos de preparação
      _paraCozinha = widget.item?.paraCozinha ?? false;
      _paraBar = widget.item?.paraBar ?? false;
      _departamentoId = widget.item is Produto ? (widget.item as Produto).departamentoId : null;
      _departamentosAdicionais = widget.item is Produto
          ? List<String>.from((widget.item as Produto).departamentosAdicionais)
          : [];
      _enviaBalanca = widget.item?.enviaBalanca ?? false;
      _impressoraProducao = widget.item is Produto ? (widget.item as Produto).impressoraProducao : null;
      _impressoraProducaoExtra = widget.item is Produto
          ? List<String>.from((widget.item as Produto).impressoraProducaoExtra)
              .where((e) => e != _impressoraProducao) // dedupe defensivo contra dados antigos
              .toList()
          : [];
      
      _codigosFornecedor = List<String>.from(widget.item?.codigosFornecedor ?? []);
      _observacaoPadraoController.text = widget.item is Produto ? ((widget.item as Produto).observacaoPadrao ?? '') : '';
      
      // Carregar adicionais
      _adicionais = widget.item is Produto 
          ? List<AdicionalProduto>.from((widget.item as Produto).adicionais)
          : [];
      _temAdicionais = widget.item is Produto 
          ? (widget.item as Produto).temAdicionais
          : false;
          
      _ehComposto = widget.item is Produto 
          ? (widget.item as Produto).ehComposto
          : false;
      _exibirComposicaoPdv = widget.item is Produto
          ? (widget.item as Produto).exibirComposicaoPdv
          : false;
      _baixarEstoqueProprio = widget.item is Produto
          ? (widget.item as Produto).baixarEstoqueProprio
          : true;
      _composicao = widget.item is Produto 
          ? List<ItemComposicao>.from((widget.item as Produto).composicao)
          : [];
      _perguntasSelecao = widget.item is Produto
          ? List<PerguntaSelecao>.from((widget.item as Produto).perguntasSelecao)
          : [];

      // Carregar preços por perfil de cliente
      if (widget.item is Produto) {
        final produto = widget.item as Produto;
        if (produto.precosPorPerfil != null) {
          produto.precosPorPerfil!.forEach((perfil, preco) {
            _tabelasPrecoSelecionadas.add(perfil);
            _precosPerfilControllers[perfil] = TextEditingController(
              text: preco > 0 ? preco.toStringAsFixed(2) : '',
            );
          });
        }
        // Carregar regras de quantidade (atacarejo)
        _regrasQuantidade = List<RegraQuantidade>.from(produto.regrasQuantidade ?? []);
      }
    } else {
      // Novo produto
      _nome = '';
      _descricao = '';
      _unidade = '';
      _unidadeVenda = 'unidade';
      _quantidadeBaixa = 1.0;
      _quantidadeBaixaController.text = '1';
      _formasVenda = [
        const FormaVenda(tipo: 'unidade', quantidadeBaixa: 1.0, preco: 0.0),
      ];
      _preco = 0.0;
      _precoCusto = null;
      _estoque = 0.0;
      _codigoBarras = '';
      for (final c in _codigosBarrasAdicionaisControllers) {
        c.dispose();
      }
      _codigosBarrasAdicionaisControllers.clear();
      _grupo = 'Sem Grupo';
      _codigoEditavel = true; // Código é editável para novos produtos
      _temPromocao = false;
      _precoPromocional = null;
      _promocaoInicio = null;
      _promocaoFim = null;
      
      // Inicializar campos de impostos
      // PADRÃO CORRETO: Tributado (CFOP 5102, CSOSN 102 no Simples / CST 00 no
      // Regime Normal). ANTES o produto novo nascia como Substituição Tributária
      // (CFOP 5405, CSOSN 500), o que gerava notas erradas.
      _ncm = '22011000';
      _icmsAliquota = null;
      _icmsCst = '00';
      _ipiAliquota = null;
      _ipiCst = null;
      _pisAliquota = null;
      _pisCst = null;
      _cofinsAliquota = null;
      _cofinsCst = null;
      _issAliquota = null;
      _origem = null;
      _cfop = '5102';
      _cest = null;
      _csosn = '102';
      _simplesNacionalAliquota = null;
      // Aplica automaticamente o perfil tributário PADRÃO do regime atual da
      // empresa (ex.: Tributado 5102/102 no Simples ou 5102/00 no Regime Normal).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          final service = Provider.of<DataService>(context, listen: false);
          final perfis = service.perfisTributariosDoRegime;
          PerfilTributario? padrao;
          for (final p in perfis) {
            if (p.isDefault) { padrao = p; break; }
          }
          padrao ??= perfis.isNotEmpty ? perfis.first : null;
          if (padrao != null) {
            // Variável final local: permite type promotion dentro do closure
            // do setState (Dart não promove variáveis capturadas por closures).
            final perfil = padrao;
            setState(() {
              _perfilTributarioId = perfil.id;
              _cfop = perfil.cfop;
              _cfopController.text = perfil.cfop;
              _csosn = perfil.csosn;
              _csosnController.text = perfil.csosn ?? '';
              _icmsCst = perfil.icmsCst;
              _icmsCstController.text = perfil.icmsCst ?? '';
              _ncm = perfil.ncm ?? _ncm;
              _ncmController.text = _ncm ?? '';
              _pisCst = perfil.pisCst;
              _pisCstController.text = perfil.pisCst ?? '';
              _cofinsCst = perfil.cofinsCst;
              _cofinsCstController.text = perfil.cofinsCst ?? '';
              _icmsAliquota = perfil.aliquotaIcms;
              _icmsAliquotaController.text = perfil.aliquotaIcms?.toString() ?? '';
              _pisAliquota = perfil.aliquotaPis;
              _pisAliquotaController.text = perfil.aliquotaPis?.toString() ?? '';
              _cofinsAliquota = perfil.aliquotaCofins;
              _cofinsAliquotaController.text = perfil.aliquotaCofins?.toString() ?? '';
            });
          }
        } catch (_) {}
      });
      _paraCozinha = false;
      _paraBar = false;
      _departamentoId = null;
      _enviaBalanca = false;
      _codigosFornecedor = [];
      _observacaoPadraoController.text = '';
      _ehComposto = false;
      _exibirComposicaoPdv = false;
      _baixarEstoqueProprio = true;
      _composicao = [];
      _perguntasSelecao = [];
      
      // Gerar código automaticamente para novo produto
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gerarProximoCodigo();
      });
    }
    
    // Carregar dados de impostos (tanto para novo quanto para edição)
    if (widget.item != null) {
      _ncm = widget.item?.ncm;
      _icmsAliquota = widget.item?.icmsAliquota;
      _icmsCst = widget.item?.icmsCst;
      _ipiAliquota = widget.item?.ipiAliquota;
      _ipiCst = widget.item?.ipiCst;
      _pisAliquota = widget.item?.pisAliquota;
      _pisCst = widget.item?.pisCst;
      _cofinsAliquota = widget.item?.cofinsAliquota;
      _cofinsCst = widget.item?.cofinsCst;
      _issAliquota = widget.item?.issAliquota;
      _origem = widget.item?.origem;
      _cfop = widget.item?.cfop;
      _cest = widget.item?.cest;
      _csosn = widget.item?.csosn;
      _perfilTributarioId = widget.item?.perfilTributarioId;
      _simplesNacionalAliquota = widget.item?.simplesNacionalAliquota;
      

      
      // Carregar dados de e-commerce
      _exibirNaLoja = widget.item?.exibirNaLoja ?? false;
      _emDestaque = widget.item?.emDestaque ?? false;
      _fotosUrls = widget.item?.fotosUrls ?? [];
      _descricaoEcommerce = widget.item?.descricaoEcommerce;
      _pesoGramas = widget.item?.pesoGramas;
      _alturaCm = widget.item?.alturaCm;
      _larguraCm = widget.item?.larguraCm;
      _profundidadeCm = widget.item?.profundidadeCm;
      _tags = widget.item?.tags ?? [];
      
      // Carregar variações
      _variacoes = widget.item?.variacoes ?? [];
      _temVariacoes = widget.item?.temVariacoes ?? false;
      
      _descricaoEcommerceController.text = _descricaoEcommerce ?? '';
      _pesoGramasController.text = _pesoGramas?.toString() ?? '';
      _alturaCmController.text = _alturaCm?.toString() ?? '';
      _larguraCmController.text = _larguraCm?.toString() ?? '';
      _profundidadeCmController.text = _profundidadeCm?.toString() ?? '';
      _tagsController.text = _tags.join(', ');
    } else {
      // Inicializar campos de e-commerce para novo produto
      _exibirNaLoja = false;
      _emDestaque = false;
      _fotosUrls = [];
      _descricaoEcommerce = null;
      _pesoGramas = null;
      _alturaCm = null;
      _larguraCm = null;
      _profundidadeCm = null;
      _tags = [];
    }

    // Preencher controllers de impostos
    _ncmController.text = _ncm ?? '';
    _icmsAliquotaController.text = _icmsAliquota?.toString() ?? '';
    _icmsCstController.text = _icmsCst ?? '';
    _ipiAliquotaController.text = _ipiAliquota?.toString() ?? '';
    _ipiCstController.text = _ipiCst ?? '';
    _pisAliquotaController.text = _pisAliquota?.toString() ?? '';
    _pisCstController.text = _pisCst ?? '';
    _cofinsAliquotaController.text = _cofinsAliquota?.toString() ?? '';
    _cofinsCstController.text = _cofinsCst ?? '';
    _issAliquotaController.text = _issAliquota?.toString() ?? '';
    _origemController.text = _origem ?? '';
    _cfopController.text = _cfop ?? '';
    _cestController.text = _cest ?? '';
    _csosnController.text = _csosn ?? '';
    _simplesNacionalAliquotaController.text = _simplesNacionalAliquota?.toString() ?? '';
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _codigoController.dispose();
    _codigoBarrasController.dispose();
    for (final c in _codigosBarrasAdicionaisControllers) {
      c.dispose();
    }
    _codigosBarrasAdicionaisControllers.clear();
    _descricaoController.dispose();
    _unidadeController.dispose();
    _quantidadeBaixaController.dispose();
    _grupoController.dispose();
    _subgrupoController.dispose();
    _precoController.dispose();
    _precoCustoController.dispose();
    _estoqueController.dispose();
    _precoPromocionalController.dispose();
    _fornecedorNomeController.dispose();
    _ncmController.dispose();
    _icmsAliquotaController.dispose();
    _icmsCstController.dispose();
    _ipiAliquotaController.dispose();
    _ipiCstController.dispose();
    _pisAliquotaController.dispose();
    _pisCstController.dispose();
    _cofinsAliquotaController.dispose();
    _cofinsCstController.dispose();
    _issAliquotaController.dispose();
    _origemController.dispose();
    _cfopController.dispose();
    _cestController.dispose();
            _csosnController.dispose();
            _simplesNacionalAliquotaController.dispose();
            _descricaoEcommerceController.dispose();
            _pesoGramasController.dispose();
            _alturaCmController.dispose();
            _larguraCmController.dispose();
            _profundidadeCmController.dispose();
            _tagsController.dispose();
            _estoqueMinimoController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProdutoServicoForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recriar TabController se necessário (garantir que length está correto)
    if (_tabController.length != 7) {
      _tabController.dispose();
      _tabController = TabController(length: 7, vsync: this);
      _tabController.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  void _gerarProximoCodigo() {
    final service = Provider.of<DataService>(context, listen: false);

    // Pega TODOS os códigos existentes (inclusive de produtos não salvos)
    final codigosExistentes = [
      ...service.produtos.map((p) => p.codigo),
      _codigoController.text.isNotEmpty ? _codigoController.text : null,
    ].where((c) => c != null && c.isNotEmpty).toList();

    print('📋 Códigos existentes: $codigosExistentes');

    // Gera o próximo código
    final proximoCodigo = CodigoService.gerarProximoCodigo(codigosExistentes);

    setState(() {
      _codigo = proximoCodigo;
      _codigoController.text = _codigo;
    });

    // Feedback visual
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Novo código gerado: $_codigo'),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _gerarProximoUltimo() {
    final service = Provider.of<DataService>(context, listen: false);

    // Pega TODOS os códigos existentes (inclusive de produtos não salvos)
    final codigosExistentes = [
      ...service.produtos.map((p) => p.codigo),
      _codigoController.text.isNotEmpty ? _codigoController.text : null,
    ].where((c) => c != null && c.isNotEmpty).toList();

    print('📋 Códigos existentes: $codigosExistentes');

    // Gera o próximo código após o último (sem preencher furos)
    final proximoCodigo = CodigoService.gerarProximoUltimo(codigosExistentes);

    setState(() {
      _codigo = proximoCodigo;
      _codigoController.text = _codigo;
    });

    // Feedback visual
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Próximo do último: $_codigo'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _podeVerCusto() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual;
    if (usuario == null) return false;
    if (usuario.isAdmin || usuario.isGerente || usuario.isMaster || usuario.email.toLowerCase() == 'user') {
      return true;
    }
    final permissionService = PermissionService();
    return permissionService.temPermissao(usuario, TipoPermissao.produtosVisualizarCusto) ||
           permissionService.temPermissao(usuario, TipoPermissao.vendasVerCusto);
  }

  /// Calcula e retorna a string da margem de lucro
  String _calcularMargemLucro() {
    if (_precoCusto == null || _precoCusto == 0 || _preco == 0) {
      return 'Informe preço e custo para calcular';
    }
    
    final lucro = _preco - _precoCusto!;
    final margemPercentual = (lucro / _precoCusto!) * 100;
    
    String status;
    if (lucro > 0) {
      status = 'Lucro';
    } else if (lucro < 0) {
      status = 'Prejuízo';
    } else {
      status = 'Sem lucro';
    }
    
    return '💰 $status: R\$ ${lucro.toStringAsFixed(2)} | 📊 Margem: ${margemPercentual.toStringAsFixed(2)}%';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Deep Midnight Blue
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Minimalista
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.item == null ? Icons.add_rounded : Icons.edit_rounded,
                        color: Colors.blueAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item == null ? 'Novo Produto' : 'Editar Produto',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _nome.isEmpty ? 'Preencha os dados' : _nome,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Ações Rápidas no Header
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancelar', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (_formKey.currentState?.validate() ?? false) {
                              _salvarProduto();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(widget.item == null ? 'SALVAR' : 'ATUALIZAR', 
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // TabBar Minimalista
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.blueAccent,
                indicatorWeight: 3,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(text: 'Básico'),
                  Tab(text: 'Fiscal'),
                  Tab(text: 'E-commerce'),
                  Tab(text: 'Estoque'),
                  Tab(text: 'Composição'),
                  Tab(text: 'Adicionais'),
                  Tab(text: 'Histórico'),
                ],
              ),
              // Conteúdo
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaInformacoes(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaImpostos(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaEcommerce(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaEstoque(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaComposicao(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaAdicionais(),
                    ),
                    if (widget.item != null)
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: _buildAbaHistoricoAlteracoes(),
                      )
                    else
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 48, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              'Histórico disponível após salvar o produto',
                              style: TextStyle(color: Colors.white38, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ VALIDAÇÃO CFOP × CSOSN ═══
  bool _validarCfopCsosn(String cfop, String csosn) {
    if (csosn.isEmpty) return true;
    final cfopsTributados = {'5102', '1102', '6102', '7102', '5101', '1101', '6101', '7101'};
    final cfopsSt = {'5405', '1551', '5551', '6551', '7551', '5403', '1403', '6403'};
    // 300=Imune, 400=Não tributada, 600=Exigibilidade suspensa → requer CFOPs de tributação
    final csosnsTributados = {'101', '102', '103', '201', '202', '203', '300', '400', '600'};
    if (csosnsTributados.contains(csosn)) return cfopsTributados.contains(cfop);
    if (csosn == '500') return cfopsSt.contains(cfop) || cfopsTributados.contains(cfop);
    if (csosn == '900') return true;
    if (cfop == '5949' && csosn != '900') return false;
    return true;
  }

  String _sugestaoCfopCsosn(String cfop, String csosn) {
    final csosnsTributados = {'101', '102', '103', '201', '202', '203', '300', '400', '600'};
    if (csosnsTributados.contains(csosn)) return 'CSOSN $csosn requer CFOP: 5102, 1102, 6102 ou 7102';
    if (csosn == '500') return 'CSOSN 500 requer CFOP: 5405, 1551, 5551 ou similar de ST';
    if (cfop == '5949') return 'CFOP 5949 só aceita CSOSN 900 (Outros)';
    return 'Verifique a combinação CFOP/CSOSN no manual da SEFAZ';
  }

  Map<String, String> _corrigirCfopCsosnLocal(String cfop, String csosn) {
    String cfopCorrigido = cfop;
    String csosnCorrigido = csosn;
    final cfopsTributados = {'5102', '1102', '6102', '7102', '5101', '1101', '6101', '7101'};
    final cfopsSt = {'5405', '1551', '5551', '6551', '7551', '5403', '1403', '6403'};
    // 300=Imune, 400=Não tributada, 600=Exigibilidade suspensa
    final csosnsTributados = {'101', '102', '103', '201', '202', '203', '300', '400', '600'};
    if (csosnsTributados.contains(csosn)) {
      if (!cfopsTributados.contains(cfop)) cfopCorrigido = '5102';
    } else if (csosn == '500') {
      if (!cfopsSt.contains(cfop) && !cfopsTributados.contains(cfop)) cfopCorrigido = '5405';
    } else if (cfop == '5949' && csosn != '900') {
      csosnCorrigido = '900';
    }
    return {'cfop': cfopCorrigido, 'csosn': csosnCorrigido};
  }

  void _salvarProduto() {
    // Verificar se já existe produto com o mesmo código
    final service = Provider.of<DataService>(
      context,
      listen: false,
    );
    final codigoJaExiste = service.produtos.any(
      (p) =>
          p.codigo == _codigo &&
          p.id != (widget.item?.id ?? ''),
    );

    if (codigoJaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ Produto com código $_codigo já existe!',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Processar tags (separar por vírgula e limpar espaços)
    final tagsProcessadas = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    // Processar dimensões e peso
    final pesoGramas = _pesoGramasController.text.isNotEmpty
        ? int.tryParse(_pesoGramasController.text)
        : null;
    final alturaCm = _alturaCmController.text.isNotEmpty
        ? double.tryParse(_alturaCmController.text.replaceAll(',', '.'))
        : null;
    final larguraCm = _larguraCmController.text.isNotEmpty
        ? double.tryParse(_larguraCmController.text.replaceAll(',', '.'))
        : null;
    final profundidadeCm = _profundidadeCmController.text.isNotEmpty
        ? double.tryParse(_profundidadeCmController.text.replaceAll(',', '.'))
        : null;

    // Determinar foto principal (primeira da lista)
    final fotoPrincipalUrl = _fotosUrls.isNotEmpty ? _fotosUrls.first : null;

    // Debug: Log dos dados de e-commerce
    debugPrint('>>> [ProdutoForm] ========================================');
    debugPrint('>>> [ProdutoForm] SALVANDO DADOS DE E-COMMERCE');
    debugPrint('>>> [ProdutoForm] Exibir na loja: $_exibirNaLoja');
    debugPrint('>>> [ProdutoForm] Tipo de _exibirNaLoja: ${_exibirNaLoja.runtimeType}');
    debugPrint('>>> [ProdutoForm] Em destaque: $_emDestaque');
    debugPrint('>>> [ProdutoForm] Nome produto: $_nome');
    debugPrint('>>> [ProdutoForm] Estoque: $_estoque');
    debugPrint('>>> [ProdutoForm] Fotos URLs: ${_fotosUrls.length} fotos');
    debugPrint('>>> [ProdutoForm] Foto principal: $fotoPrincipalUrl');
    debugPrint('>>> [ProdutoForm] Descrição e-commerce: ${_descricaoEcommerceController.text.isNotEmpty ? "SIM" : "NÃO"}');
    debugPrint('>>> [ProdutoForm] Peso (gramas): $pesoGramas');
    debugPrint('>>> [ProdutoForm] Altura (cm): $alturaCm');
    debugPrint('>>> [ProdutoForm] Largura (cm): $larguraCm');
    debugPrint('>>> [ProdutoForm] Profundidade (cm): $profundidadeCm');
    debugPrint('>>> [ProdutoForm] Tags: $tagsProcessadas');
    debugPrint('>>> [ProdutoForm] ========================================');

    // Sincronizar campos legados com a forma principal antes de salvar
    if (_formasVenda.isNotEmpty) {
      final principal = _formasVenda.first;
      _unidadeVenda = principal.tipo;
      _quantidadeBaixa = principal.quantidadeBaixa > 0
          ? principal.quantidadeBaixa
          : 1.0;
      // Se a forma principal não tem preço próprio, usar o preço principal
      _formasVenda = [
        if (principal.preco <= 0)
          FormaVenda(tipo: principal.tipo, quantidadeBaixa: _quantidadeBaixa, preco: _preco)
        else
          principal,
        ..._formasVenda.skip(1),
      ];
    }

    final produto = Produto(
      id: (widget.item?.id != null && widget.item!.id.isNotEmpty)
          ? widget.item!.id
          : _uuid.v4(),
      codigo: _codigo,
      codigoBarras: _codigoBarras.isNotEmpty
          ? _codigoBarras
          : null,
      codigosBarrasAdicionais: _coletarCodigosBarrasAdicionais(),
      nome: _nome,
      descricao: _descricao,
      unidade: (_unidadeController.text.trim().isNotEmpty ? _unidadeController.text.trim() : 'peça'),
      unidadeVenda: _unidadeVenda,
      quantidadeBaixa: ((double.tryParse(_quantidadeBaixaController.text.replaceAll(',', '.')) ?? 1.0).clamp(0.001, 9999999)).toDouble(),
      formasVenda: _formasVenda.isNotEmpty ? _formasVenda : null,
      grupo: (_grupo.isNotEmpty ? _grupo : 'Sem Grupo'),
      subgrupo: _subgrupoController.text.trim(),
      preco: _preco,
      precoCusto: _precoCusto,
      estoque: _estoque,
      estoqueMinimo: double.tryParse(_estoqueMinimoController.text.replaceAll(',', '.')) ?? 0.0,
      createdAt: widget.item?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      precoPromocional: _temPromocao
          ? _precoPromocional
          : null,
      promocaoInicio: _temPromocao ? _promocaoInicio : null,
      promocaoFim: _temPromocao ? _promocaoFim : null,
      promocoes: _promocoes.isNotEmpty ? _promocoes : null,
      perfilTributarioId: _perfilTributarioId,
      ncm: _ncm?.isNotEmpty == true ? _ncm : null,
      icmsAliquota: _icmsAliquota,
      icmsCst: _icmsCst?.isNotEmpty == true ? _icmsCst : null,
      ipiAliquota: _ipiAliquota,
      ipiCst: _ipiCst?.isNotEmpty == true ? _ipiCst : null,
      pisAliquota: _pisAliquota,
      pisCst: _pisCst?.isNotEmpty == true ? _pisCst : null,
      cofinsAliquota: _cofinsAliquota,
      cofinsCst: _cofinsCst?.isNotEmpty == true ? _cofinsCst : null,
      issAliquota: _issAliquota,
      origem: _origem?.isNotEmpty == true ? _origem : null,
      cfop: _cfop?.isNotEmpty == true ? _cfop : null,
      cest: _cest?.isNotEmpty == true ? _cest : null,
      csosn: _csosn?.isNotEmpty == true ? _csosn : null,
      simplesNacionalAliquota: _simplesNacionalAliquota,
      // Campos de Preparação
      paraCozinha: _paraCozinha,
      paraBar: _paraBar,
      departamentoId: _departamentoId,
      departamentosAdicionais: _departamentosAdicionais,
      enviaBalanca: _enviaBalanca,
      impressoraProducao: _impressoraProducao,
      impressoraProducaoExtra: _impressoraProducaoExtra,
      codigosFornecedor: _codigosFornecedor,
      // Campos de E-commerce
      exibirNaLoja: _exibirNaLoja,
      emDestaque: _emDestaque,
      fotosUrls: _fotosUrls,
      fotoPrincipalUrl: fotoPrincipalUrl,
      descricaoEcommerce: _descricaoEcommerceController.text.isNotEmpty
          ? _descricaoEcommerceController.text.trim()
          : null,
      pesoGramas: pesoGramas,
      alturaCm: alturaCm,
      larguraCm: larguraCm,
      profundidadeCm: profundidadeCm,
      tags: tagsProcessadas,
      variacoes: _temVariacoes ? _variacoes : [],
      temVariacoes: _temVariacoes,
      fornecedorId: _fornecedorId,
      fornecedorNome: _fornecedorNomeController.text.trim(),
      estoquePorFornecedor: _estoquePorFornecedor,
      adicionais: _adicionais,
      temAdicionais: _adicionais.isNotEmpty,
      ehComposto: _ehComposto,
      baixarEstoqueProprio: _baixarEstoqueProprio,
      exibirComposicaoPdv: _exibirComposicaoPdv,
      composicao: _composicao,
      perguntasSelecao: _perguntasSelecao,
      observacaoPadrao: _observacaoPadraoController.text.trim().isNotEmpty ? _observacaoPadraoController.text.trim() : null,
      // Preços por perfil de cliente (apenas tabelas selecionadas)
      precosPorPerfil: {
        for (final nome in _tabelasPrecoSelecionadas)
          if (_precosPerfilControllers[nome]?.text.trim().isNotEmpty == true)
            nome: double.tryParse(
                  _precosPerfilControllers[nome]!.text.replaceAll(',', '.'),
                ) ??
                0.0,
      },
      // Regras de quantidade (atacarejo)
      regrasQuantidade: _regrasQuantidade.isNotEmpty ? _regrasQuantidade : null,
    );
    
    // DEBUG CRÍTICO: Verificar produto criado
    debugPrint('>>> [ProdutoForm] ========================================');
    debugPrint('>>> [ProdutoForm] PRODUTO CRIADO/ATUALIZADO');
    debugPrint('>>> [ProdutoForm] Nome: ${produto.nome}');
    debugPrint('>>> [ProdutoForm] ID: ${produto.id}');
    debugPrint('>>> [ProdutoForm] exibirNaLoja no objeto: ${produto.exibirNaLoja}');
    debugPrint('>>> [ProdutoForm] emDestaque no objeto: ${produto.emDestaque}');
    debugPrint('>>> [ProdutoForm] estoque: ${produto.estoque}');
    final mapTest = produto.toMap();
    debugPrint('>>> [ProdutoForm] toMap["exibirNaLoja"]: ${mapTest["exibirNaLoja"]}');
    debugPrint('>>> [ProdutoForm] ========================================');

    final nomeDuplicado = service.produtos.any(
      (p) =>
          p.nome.trim().toLowerCase() == _nome.trim().toLowerCase() &&
          p.id != (widget.item?.id ?? ''),
    );

    if (nomeDuplicado) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.amber),
              SizedBox(width: 8),
              Text('Produto Duplicado', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'Já existe um produto cadastrado com o nome "$_nome". Deseja salvar assim mesmo?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _confirmarSalvamento(produto);
              },
              child: const Text('SALVAR ASSIM MESMO', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      _confirmarSalvamento(produto);
    }
  }

  void _confirmarSalvamento(Produto produto) {
    widget.onSave(produto);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Produto cadastrado com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Exibe diálogo para ajuste rápido de estoque
  void _exibirDialogoAjusteEstoque() {
    if (widget.item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salve o produto antes de ajustar o estoque')),
      );
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final qtdController = TextEditingController();
    final fornecedorController = TextEditingController(text: _fornecedorNomeController.text);
    final obsController = TextEditingController();
    // RawAutocomplete exige focusNode + textEditingController SEMPRE juntos
    // (assert: (focusNode == null) == (textEditingController == null))
    final fornecedorFocusNode = FocusNode();
    String tipo = 'entrada';

    showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Ajuste de Estoque', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('ENTRADA'),
                        selected: tipo == 'entrada',
                        onSelected: (s) => setDialogState(() => tipo = 'entrada'),
                        selectedColor: Colors.greenAccent.withOpacity(0.2),
                        labelStyle: TextStyle(color: tipo == 'entrada' ? Colors.greenAccent : Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('SAÍDA'),
                        selected: tipo == 'saida',
                        onSelected: (s) => setDialogState(() => tipo = 'saida'),
                        selectedColor: Colors.redAccent.withOpacity(0.2),
                        labelStyle: TextStyle(color: tipo == 'saida' ? Colors.redAccent : Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtdController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Quantidade',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                RawAutocomplete<String>(
                  textEditingController: fornecedorController,
                  focusNode: fornecedorFocusNode,
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    final fornecedores = _obterFornecedoresUnicos();
                    if (textEditingValue.text.isEmpty) {
                      return fornecedores;
                    }
                    return fornecedores.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    fornecedorController.text = selection;
                  },
                  fieldViewBuilder: (BuildContext context, TextEditingController fieldController,
                      FocusNode focusNode, VoidCallback onFieldSubmitted) {
                    return TextField(
                      controller: fieldController,
                      focusNode: focusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Fornecedor',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected,
                      Iterable<String> options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        color: const Color(0xFF1E293B),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                        child: Container(
                          width: 250, // Largura fixa segura para evitar loops de LayoutBuilder
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);
                              return ListTile(
                                title: Text(option, style: const TextStyle(color: Colors.white70)),
                                onTap: () {
                                  onSelected(option);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (Opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  final qtdStr = qtdController.text.trim().replaceAll(',', '.');
                  final qtd = double.tryParse(qtdStr) ?? 0.0;
                  if (qtd <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Informe uma quantidade válida'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  setDialogState(() => isLoading = true);

                  try {
                    if (tipo == 'entrada') {
                      await dataService.registrarEntradaEstoque(
                        produtoId: widget.item.id,
                        quantidade: qtd,
                        fornecedorNome: fornecedorController.text.isEmpty ? 'Geral' : fornecedorController.text,
                        observacao: obsController.text,
                        usuario: authService.usuarioAtual?.nome,
                      );
                    } else {
                      await dataService.registrarSaidaEstoque(
                        produtoId: widget.item.id,
                        quantidade: qtd,
                        fornecedorNome: fornecedorController.text.isEmpty ? 'Geral' : fornecedorController.text,
                        motivo: 'ajuste',
                        observacao: obsController.text,
                        usuario: authService.usuarioAtual?.nome,
                      );
                    }
                    
                    // Fechar o diálogo IMEDIATAMENTE após o processamento local (DataService)
                    if (context.mounted) Navigator.pop(context);

                    setState(() {
                      final prod = dataService.produtos.firstWhere((p) => p.id == widget.item.id);
                      _estoque = prod.estoque;
                      _estoquePorFornecedor = Map<String, double>.from(prod.estoquePorFornecedor);
                      _estoqueController.text = _estoque.toString();
                    });

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✓ Estoque ajustado: $qtd unidades ($tipo)'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    debugPrint('>>> Erro no ajuste: $e');
                    if (context.mounted) {
                      setDialogState(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao ajustar estoque: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: tipo == 'entrada' ? Colors.green : Colors.redAccent),
                child: isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('CONFIRMAR'),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      // Liberar recursos ao fechar o diálogo
      qtdController.dispose();
      fornecedorController.dispose();
      obsController.dispose();
      fornecedorFocusNode.dispose();
    });
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent.withOpacity(0.8),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Seção de Validade e Lote: lista os lotes do produto (controle de
  /// vencimento para ração, medicamentos etc.) e permite adicionar/remover.
  Widget _buildLotesSection() {
    final produtoId = widget.item!.id;
    final dataService = Provider.of<DataService>(context);
    final lotes = dataService.lotesProdutos
        .where((l) => l.produtoId == produtoId)
        .toList()
      ..sort((a, b) {
        // Ordenar por validade (vencidos primeiro)
        final da = a.dataValidade ?? DateTime(9999);
        final db = b.dataValidade ?? DateTime(9999);
        return da.compareTo(db);
      });

    return _buildSection('Validade e Lote', [
      if (lotes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.event_available_outlined, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nenhum lote cadastrado. Produtos com validade (ração, medicamentos, etc.) podem ser controlados por lote — a baixa de estoque acontece primeiro nos lotes que vencem antes (FEFO).',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                ),
              ),
            ],
          ),
        )
      else
        ...lotes.map((lote) {
          final dias = lote.diasParaVencer;
          final vencido = lote.estaVencido;
          final Color corStatus = vencido
              ? Colors.redAccent
              : (dias != null && dias <= 30 ? Colors.orangeAccent : Colors.greenAccent);
          final IconData iconeStatus = vencido
              ? Icons.error
              : (dias != null && dias <= 30 ? Icons.warning_amber : Icons.check_circle);
          final String textoStatus = vencido
              ? 'VENCIDO'
              : (dias == null
                  ? 'Sem validade'
                  : (dias == 0
                      ? 'Vence HOJE'
                      : (dias <= 30 ? 'Vence em $dias dia(s)' : 'OK ($dias dias)')));

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: vencido
                  ? Colors.red.withOpacity(0.08)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: vencido ? Colors.red.withOpacity(0.4) : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(iconeStatus, size: 18, color: corStatus),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lote: ${lote.numeroLote.isEmpty ? '(sem nº)' : lote.numeroLote}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (lote.fornecedorNome != null && lote.fornecedorNome!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.storefront_outlined, size: 11, color: Colors.white38),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  lote.fornecedorNome!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        [
                          if (lote.dataValidade != null)
                            'Validade: ${DateFormat('dd/MM/yyyy').format(lote.dataValidade!)}',
                          'Qtd: ${lote.quantidade.toStringAsFixed(2)}',
                        ].join('  |  '),
                        style: TextStyle(
                          fontSize: 11,
                          color: corStatus,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  tooltip: 'Remover lote',
                  onPressed: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E2E),
                        title: const Text('Remover Lote', style: TextStyle(color: Colors.white)),
                        content: Text(
                          'Remover o lote "${lote.numeroLote}"? A quantidade restante (${lote.quantidade.toStringAsFixed(2)}) deixará de ser considerada no estoque por lote.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('REMOVER'),
                          ),
                        ],
                      ),
                    );
                    if (confirmar == true) {
                      await dataService.removerLoteProduto(lote.id);
                    }
                  },
                ),
              ],
            ),
          );
        }),
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _exibirDialogoNovoLote(dataService, produtoId),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar Lote'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orangeAccent,
            side: BorderSide(color: Colors.orangeAccent.withOpacity(0.4)),
          ),
        ),
      ),
    ]);
  }

  Future<void> _exibirDialogoNovoLote(DataService dataService, String produtoId) async {
    final loteController = TextEditingController();
    final qtdController = TextEditingController();
    final fornecedorController = TextEditingController(text: _fornecedorNomeController.text);
    DateTime? dataValidade;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Adicionar Lote', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: loteController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nº do Lote',
                      hintText: 'Ex: LOTE-A1-2026',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: fornecedorController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Fornecedor do lote',
                      hintText: 'Ex: Distribuidora XYZ',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      prefixIcon: Icon(Icons.storefront_outlined, color: Colors.white38, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtdController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade',
                      hintText: 'Ex: 10',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final data = await showDatePicker(
                        context: ctx,
                        initialDate: dataValidade ?? DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                        helpText: 'Data de Validade',
                      );
                      if (data != null) setDialogState(() => dataValidade = data);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Validade',
                        labelStyle: TextStyle(
                          color: dataValidade != null ? Colors.white : Colors.white54,
                        ),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        suffixIcon: const Icon(Icons.calendar_today, color: Colors.white54, size: 18),
                      ),
                      child: Text(
                        dataValidade != null
                            ? DateFormat('dd/MM/yyyy').format(dataValidade!)
                            : 'Selecionar data',
                        style: TextStyle(color: dataValidade != null ? Colors.white : Colors.white38),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                onPressed: () async {
                  final numero = loteController.text.trim();
                  final qtd = double.tryParse(qtdController.text.replaceAll(',', '.')) ?? 0;
                  final fornecedor = fornecedorController.text.trim();
                  if (numero.isEmpty && dataValidade == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Informe ao menos o nº do lote ou a validade')),
                    );
                    return;
                  }
                  // Produto ainda não salvo (ID vazio): não dá para atrelar o lote
                  // nem dar entrada no estoque. Bloquear com mensagem clara em vez
                  // de criar um lote "órfão" que nunca soma no estoque.
                  if (produtoId.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Salve o produto primeiro para adicionar o lote ao estoque.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final id = '${DateTime.now().microsecondsSinceEpoch}_lote_$produtoId';
                  await dataService.salvarLoteProduto(LoteProduto(
                    id: id,
                    produtoId: produtoId,
                    numeroLote: numero.isEmpty ? 'LOTE ${DateTime.now().year}' : numero,
                    dataValidade: dataValidade,
                    quantidade: qtd,
                    fornecedorId: fornecedor.isEmpty ? null : _fornecedorId,
                    fornecedorNome: fornecedor.isEmpty ? null : fornecedor,
                  ));
                  bool estoqueAtualizado = false;
                  if (qtd > 0) {
                    // Somar ao estoque geral do produto (e ao histórico)
                    estoqueAtualizado = await dataService.registrarEntradaEstoque(
                      produtoId: produtoId,
                      quantidade: qtd,
                      observacao: 'Entrada manual de lote ${numero.isEmpty ? '' : numero}',
                      usuario: 'Sistema',
                      fornecedorId: fornecedor.isEmpty ? null : _fornecedorId,
                      fornecedorNome: fornecedor.isEmpty ? null : fornecedor,
                    );
                  }
                  if (mounted) {
                    // Atualizar a exibição local do estoque no formulário
                    Produto? prod;
                    try {
                      prod = dataService.produtos.firstWhere((p) => p.id == produtoId);
                    } catch (_) {
                      prod = null;
                    }
                    setState(() {
                      _estoque = prod?.estoque ?? _estoque;
                      _estoqueController.text = _estoque.toString();
                    });
                    final String msg;
                    final Color cor;
                    if (qtd > 0 && estoqueAtualizado) {
                      msg = 'Lote ${numero.isEmpty ? '' : numero} adicionado! Estoque agora: ${_estoque.toStringAsFixed(2)}';
                      cor = Colors.green;
                    } else if (qtd > 0) {
                      msg = 'Lote adicionado, mas não foi possível dar entrada no estoque.';
                      cor = Colors.orange;
                    } else {
                      msg = 'Lote ${numero.isEmpty ? '' : numero} adicionado (sem quantidade).';
                      cor = Colors.orange;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: cor),
                    );
                  }
                },
                child: const Text('SALVAR'),
              ),
            ],
          );
        },
      ),
    );

    loteController.dispose();
    qtdController.dispose();
    fornecedorController.dispose();
  }

  /// Linha de uma forma de venda no formulário (tipo + preço + baixa + remover).
  Widget _buildFormaVendaRow(int index, FormaVenda forma) {
    final tiposUsados = _formasVenda.map((f) => f.tipo).toSet();
    final tiposDisponiveis = <String>['unidade', 'caixa', 'pacote', 'saco']
        .where((t) => t == forma.tipo || !tiposUsados.contains(t))
        .toList();

    String rotuloTipo(String t) {
      switch (t) {
        case 'caixa':
          return 'Caixa';
        case 'pacote':
          return 'Pacote';
        case 'saco':
          return 'Saco';
        default:
          return 'Unidade';
      }
    }

    IconData iconeTipo(String t) {
      switch (t) {
        case 'caixa':
          return Icons.inventory_outlined;
        case 'pacote':
          return Icons.widgets_outlined;
        case 'saco':
          return Icons.shopping_bag_outlined;
        default:
          return Icons.inventory_2_outlined;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: forma.tipo,
                  dropdownColor: const Color(0xFF1E1E2E),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: index == 0 ? 'Forma Principal' : 'Forma',
                    labelStyle: TextStyle(
                      color: index == 0 ? Colors.orangeAccent : Colors.white54,
                    ),
                    prefixIcon: Icon(
                      iconeTipo(forma.tipo),
                      size: 18,
                      color: index == 0 ? Colors.orangeAccent : Colors.white54,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    isDense: true,
                  ),
                  items: tiposDisponiveis
                      .map((t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(rotuloTipo(t)),
                          ))
                      .toList(),
                  onChanged: (novo) {
                    if (novo == null || novo == forma.tipo) return;
                    setState(() {
                      _formasVenda[index] = forma.copyWith(tipo: novo);
                    });
                  },
                ),
              ),
              if (_formasVenda.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.redAccent, size: 18),
                  tooltip: 'Remover forma',
                  onPressed: () {
                    setState(() {
                      _formasVenda.removeAt(index);
                      _sincronizarFormaPrincipal();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: forma.preco > 0
                      ? forma.preco.toStringAsFixed(2)
                      : '',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _minimalInput('Ex: 120,00')
                      .copyWith(prefixText: 'Preço: '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final p = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    setState(() {
                      _formasVenda[index] =
                          forma.copyWith(preco: p > 0 ? p : 0.0);
                      // A forma principal mantém o preço principal em sincronia
                      if (index == 0 && p > 0) {
                        _preco = p;
                        _precoController.text = p.toStringAsFixed(2);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: forma.quantidadeBaixa > 0
                      ? (forma.quantidadeBaixa ==
                              forma.quantidadeBaixa.roundToDouble()
                          ? forma.quantidadeBaixa.toStringAsFixed(0)
                          : forma.quantidadeBaixa.toString())
                      : '',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration:
                      _minimalInput('Ex: 1').copyWith(prefixText: 'Baixa: '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final q = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    setState(() {
                      _formasVenda[index] =
                          forma.copyWith(quantidadeBaixa: q > 0 ? q : 1.0);
                      if (index == 0) {
                        _quantidadeBaixa = q > 0 ? q : 1.0;
                        _quantidadeBaixaController.text =
                            _quantidadeBaixa.toString();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          if (forma.vendePorEmbalagem)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '💡 1 ${rotuloTipo(forma.tipo).toLowerCase()} contém '
                '${forma.quantidadeBaixa == forma.quantidadeBaixa.roundToDouble() ? forma.quantidadeBaixa.toStringAsFixed(0) : forma.quantidadeBaixa} '
                'unidade(s) — vende 1, baixa essa quantidade.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Diálogo para adicionar uma nova forma de venda.
  Future<void> _exibirDialogoNovaFormaVenda() async {
    final tiposUsados = _formasVenda.map((f) => f.tipo).toSet();
    final tiposDisponiveis = <String>['unidade', 'caixa', 'pacote', 'saco']
        .where((t) => !tiposUsados.contains(t))
        .toList();

    if (tiposDisponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todas as formas de venda já estão cadastradas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String tipoSelecionado = tiposDisponiveis.first;
    final precoController = TextEditingController();
    final baixaController = TextEditingController();

    String rotuloTipo(String t) {
      switch (t) {
        case 'caixa':
          return 'Caixa';
        case 'pacote':
          return 'Pacote';
        case 'saco':
          return 'Saco';
        default:
          return 'Unidade';
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Nova Forma de Venda',
                style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tipoSelecionado,
                    dropdownColor: const Color(0xFF1E1E2E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Forma',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                    ),
                    items: tiposDisponiveis
                        .map((t) => DropdownMenuItem<String>(
                              value: t,
                              child: Text(rotuloTipo(t)),
                            ))
                        .toList(),
                    onChanged: (novo) {
                      if (novo != null) {
                        setDialogState(() => tipoSelecionado = novo);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: precoController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Preço',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: baixaController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Baixa no estoque',
                      hintText: 'Quantas unidades baixa por item vendido',
                      hintStyle: TextStyle(color: Colors.white24),
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () {
                  final preco =
                      double.tryParse(precoController.text.replaceAll(',', '.')) ??
                          0.0;
                  final baixa =
                      double.tryParse(baixaController.text.replaceAll(',', '.')) ??
                          1.0;
                  Navigator.pop(ctx);
                  setState(() {
                    _formasVenda.add(FormaVenda(
                      tipo: tipoSelecionado,
                      preco: preco > 0 ? preco : 0.0,
                      quantidadeBaixa: baixa > 0 ? baixa : 1.0,
                    ));
                  });
                },
                child: const Text('ADICIONAR'),
              ),
            ],
          );
        },
      ),
    );

    precoController.dispose();
    baixaController.dispose();
  }

  /// Sincroniza os campos legados (unidadeVenda/quantidadeBaixa) com a
  /// primeira forma da lista (forma principal), para compatibilidade com
  /// telas/relatórios que ainda usam os campos antigos.
  void _sincronizarFormaPrincipal() {
    if (_formasVenda.isEmpty) return;
    final principal = _formasVenda.first;
    _unidadeVenda = principal.tipo;
    _quantidadeBaixa = principal.quantidadeBaixa > 0
        ? principal.quantidadeBaixa
        : 1.0;
    _quantidadeBaixaController.text = _quantidadeBaixa.toString();
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: value ? activeColor.withOpacity(0.12) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? activeColor : Colors.white12,
            width: value ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: value ? activeColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: value ? activeColor : Colors.white60, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: value ? Colors.white : Colors.white70,
                      fontWeight: value ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: activeColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  /// Resolve as impressoras de produção deste produto a partir dos
  /// DEPARTAMENTOS selecionados (principal + adicionais), com fallback para os
  /// campos legados de impressora direta.
  List<String> _impressorasProducaoDoProduto() {
    final ds = Provider.of<DataService>(context, listen: false);
    final deps = ds.departamentos;
    final setores = <String>{};
    void addDep(String? id) {
      if (id == null || id.isEmpty) return;
      final dep = deps.where((d) => d.id == id).firstOrNull;
      if (dep == null) return;
      if (dep.impressoraProducao != null && dep.impressoraProducao!.trim().isNotEmpty) {
        setores.add(dep.impressoraProducao!.trim());
      }
      for (final e in dep.impressoraProducaoExtra) {
        if (e.trim().isNotEmpty) setores.add(e.trim());
      }
    }
    addDep(_departamentoId);
    for (final id in _departamentosAdicionais) {
      addDep(id);
    }
    // Legado: impressora configurada direto no produto
    if (setores.isEmpty || _departamentoId == null) {
      if (_impressoraProducao != null && _impressoraProducao!.trim().isNotEmpty) {
        setores.add(_impressoraProducao!.trim());
      }
      for (final e in _impressoraProducaoExtra) {
        if (e.trim().isNotEmpty) setores.add(e.trim());
      }
    }
    return setores.toList();
  }

  /// Imprime um ticket de PRODUÇÃO de exemplo nas impressoras configuradas,
  /// para o usuário conferir o layout e a impressora certa.
  Future<void> _testarImpressaoProducao() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = dataService.empresaAtual ?? authService.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não encontrada para o teste de impressão.')),
      );
      return;
    }

    final impressoras = _impressorasProducaoDoProduto();

    // Confirmação antes de imprimir (informa onde vai imprimir)
    final destino = impressoras.isEmpty
        ? 'IMPRESSORA PADRÃO DO TERMINAL'
        : impressoras.join(' • ');
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Testar Impressão de Produção',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          impressoras.isEmpty
              ? 'Nenhuma impressora de produção configurada para este produto.\n\nO ticket de teste será enviado para a impressora padrão do terminal para você conferir o layout.'
              : 'O ticket de teste será impresso em:\n\n$destino\n\nConfira se é a impressora do setor de produção (Cozinha, Bar, etc.).',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
            child: const Text('Imprimir Teste',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final impressos = await ProducaoPdfService.imprimirTicketTeste(
      empresa: empresa,
      impressoras: impressoras,
      dataService: dataService,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          impressos > 0
              ? '✅ Ticket de teste enviado para: $destino'
              : 'Não foi possível imprimir. Verifique se há uma impressora instalada/ativa no Windows.',
        ),
        backgroundColor: impressos > 0 ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    bool last = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
        child,
        if (!last) ...[
          Divider(color: Colors.white.withOpacity(0.05), height: 32),
        ],
      ],
    );
  }

  InputDecoration _minimalInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
      border: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      errorStyle: const TextStyle(fontSize: 10),
    );
  }

  List<String> _obterFornecedoresUnicos() {
    final service = Provider.of<DataService>(context, listen: false);
    final fornecedores = service.produtos
        .map((p) => p.fornecedorNome)
        .where((f) => f != null && f.trim().isNotEmpty)
        .map((f) => f!.trim())
        .toSet()
        .toList();
    fornecedores.sort();
    return fornecedores;
  }

  List<String> _obterGruposUnicos() {
    final service = Provider.of<DataService>(context, listen: false);
    final grupos = service.produtos
        .map((p) => p.grupo)
        .where((g) => g.trim().isNotEmpty && g != 'Sem Grupo')
        .map((g) => g.trim())
        .toSet()
        .toList();
    // Adicionar opções padrão se não existirem
    final GruposManager gruposManager = GruposManager();
    for (var g in gruposManager.gruposRegistrados) {
      if (g != 'Sem Grupo' && !grupos.contains(g)) {
        grupos.add(g);
      }
    }
    grupos.sort();
    return grupos;
  }

  /// Subgrupos já cadastrados (ex: 'Refrigerantes', 'Sucos' dentro de 'Bebidas').
  List<String> _obterSubgruposUnicos() {
    final service = Provider.of<DataService>(context, listen: false);
    final subgrupos = service.produtos
        .map((p) => p.subgrupo)
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toSet()
        .toList();
    subgrupos.sort();
    return subgrupos;
  }

  List<String> _obterUnidadesUnicas() {
    final service = Provider.of<DataService>(context, listen: false);
    final unidades = service.produtos
        .map((p) => p.unidade)
        .where((u) => u.trim().isNotEmpty)
        .map((u) => u.trim())
        .toSet()
        .toList();
    
    // Garantir que unidades básicas estejam sempre presentes
    for (var padrao in ['UN', 'KG', 'LT', 'CX', 'FD', 'PCT', 'GR']) {
      if (!unidades.contains(padrao)) {
        unidades.add(padrao);
      }
    }
    
    unidades.sort();
    return unidades;
  }

  Widget _buildAutocomplete({
    required TextEditingController controller,
    required String hint,
    required List<String> sugestoes,
    Function(String)? onChanged,
  }) {
    return _CustomAutocompleteField(
      controller: controller,
      hint: hint,
      sugestoes: sugestoes,
      onChanged: onChanged,
    );
  }
  List<Map<String, dynamic>> _obterConfigTabelasPreco() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = dataService.empresaAtual ?? authService.empresaAtual;
    if (empresa == null) return [];

    final cfg = empresa.configuracoes?['perfis_preco'];
    if (cfg is List && cfg.isNotEmpty) {
      return cfg
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((c) => (c['nome']?.toString() ?? '').isNotEmpty)
          .toList();
    }

    return empresa.perfisDePreco
        .map((nome) => {'nome': nome, 'tipo': 'fixo', 'valor': 0.0})
        .toList();
  }

  String _descricaoTipoTabela(Map<String, dynamic> config) {
    final tipo = config['tipo'] as String? ?? 'fixo';
    final valor = (config['valor'] as num?)?.toDouble() ?? 0.0;
    switch (tipo) {
      case 'desconto':
        return 'Desconto global: ${valor.toStringAsFixed(1)}%';
      case 'acrescimo':
        return 'Acréscimo global: ${valor.toStringAsFixed(1)}%';
      default:
        return 'Preço fixo por produto';
    }
  }

  void _alternarTabelaPreco(String nome, bool selecionada) {
    setState(() {
      if (selecionada) {
        _tabelasPrecoSelecionadas.add(nome);
        _precosPerfilControllers.putIfAbsent(nome, () => TextEditingController());
      } else {
        _tabelasPrecoSelecionadas.remove(nome);
      }
    });
  }

  Widget _buildPrecosInteligentes() {
    final tabelas = _obterConfigTabelasPreco();

    if (tabelas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhuma tabela de preço cadastrada. Crie tabelas em Configurações → Empresa para habilitar preços diferenciados.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final tabelasSelecionadasOrdenadas = tabelas
        .map((c) => c['nome'] as String)
        .where(_tabelasPrecoSelecionadas.contains)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Selecione as Tabelas de Preço',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escolha uma ou mais tabelas cadastradas na empresa (as mesmas usadas no cliente) e defina o preço deste produto em cada uma.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tabelas.map((config) {
            final nome = config['nome'] as String;
            final selecionada = _tabelasPrecoSelecionadas.contains(nome);
            final tipo = config['tipo'] as String? ?? 'fixo';
            final corTipo = tipo == 'desconto'
                ? Colors.greenAccent
                : (tipo == 'acrescimo' ? Colors.redAccent : Colors.orangeAccent);

            return FilterChip(
              label: Text(nome),
              selected: selecionada,
              onSelected: (s) => _alternarTabelaPreco(nome, s),
              selectedColor: Colors.blueAccent.withOpacity(0.25),
              checkmarkColor: Colors.blueAccent,
              backgroundColor: Colors.white.withOpacity(0.05),
              side: BorderSide(
                color: selecionada ? Colors.blueAccent : Colors.white24,
              ),
              labelStyle: TextStyle(
                color: selecionada ? Colors.white : Colors.white70,
                fontWeight: selecionada ? FontWeight.bold : FontWeight.normal,
              ),
              avatar: Icon(Icons.price_change, size: 16, color: corTipo),
            );
          }).toList(),
        ),
        if (tabelasSelecionadasOrdenadas.isEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app, color: Colors.white38, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Toque nas tabelas acima para selecionar e definir os preços.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 20),
          const Text(
            'Valores por Tabela Selecionada',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...tabelasSelecionadasOrdenadas.map((nome) {
            final config = tabelas.firstWhere(
              (t) => t['nome'] == nome,
              orElse: () => {'nome': nome, 'tipo': 'fixo', 'valor': 0.0},
            );
            final tipo = config['tipo'] as String? ?? 'fixo';
            final isFixo = tipo == 'fixo';
            _precosPerfilControllers.putIfAbsent(nome, () => TextEditingController());

            return _buildField(
              label: nome,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _descricaoTipoTabela(config),
                    style: TextStyle(
                      color: tipo == 'desconto'
                          ? Colors.greenAccent
                          : (tipo == 'acrescimo' ? Colors.redAccent : Colors.orangeAccent),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _precosPerfilControllers[nome],
                    style: const TextStyle(color: Colors.white),
                    decoration: _minimalInput(
                      isFixo
                          ? 'Preço fixo para esta tabela (ex: 15.00)'
                          : 'Deixe vazio para usar o % global da tabela',
                    ).copyWith(prefixText: 'R\$ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }



  Widget _buildAbaInformacoes() {
    return Column(
      children: [
        _buildSection('Identificação', [
          _buildField(
            label: 'Nome do Produto',
            child: TextFormField(
              initialValue: _nome,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              decoration: _minimalInput('Ex: Cerveja Antarctica 350ml'),
              onChanged: (v) => setState(() => _nome = v),
              validator: (v) => v?.isEmpty ?? true ? 'Campo obrigatório' : null,
            ),
          ),
          _buildField(
            label: 'Código Interno',
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _codigoController,
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
                    decoration: _minimalInput('Automático'),
                    readOnly: !_codigoEditavel,
                    onChanged: (v) => _codigo = v,
                  ),
                ),
                if (_codigoEditavel) ...[
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 18, color: Colors.blueAccent),
                    onPressed: _gerarProximoCodigo,
                    tooltip: 'Gerar Próximo',
                  ),
                ],
              ],
            ),
          ),
          _buildField(
            label: 'Código de Barras (EAN)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _codigoBarrasController,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
                  decoration: _minimalInput('Ex: 789000...'),
                  onChanged: (v) => _codigoBarras = v,
                ),
                // Códigos de barras adicionais
                for (var i = 0; i < _codigosBarrasAdicionaisControllers.length; i++) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codigosBarrasAdicionaisControllers[i],
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
                          decoration: _minimalInput('Código de barras ${i + 2}'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Remover código',
                        onPressed: () {
                          final controller = _codigosBarrasAdicionaisControllers[i];
                          setState(() {
                            _codigosBarrasAdicionaisControllers.removeAt(i);
                          });
                          // Descartar o controller após a reconstrução da tela
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            controller.dispose();
                          });
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _codigosBarrasAdicionaisControllers.add(TextEditingController());
                    });
                  },
                  icon: const Icon(Icons.add, size: 18, color: Colors.orange),
                  label: const Text(
                    'Adicionar outro código de barras',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
          _buildField(
            label: 'Observação Padrão (PDV)',
            last: true,
            child: TextFormField(
              controller: _observacaoPadraoController,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
              decoration: _minimalInput('Ex: Sem cebola, Bem passado'),
            ),
          ),
        ]),

        _buildSection('Departamento e Impressora', [
          // ── DEPARTAMENTO (separado da impressora) ──────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.food_bank_outlined, color: Colors.orangeAccent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Departamento de Preparação',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Onde este item é preparado (ex.: Cozinha, Bar, Sobremesas). Cadastre os departamentos no menu → Departamentos.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                ),
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final ds = Provider.of<DataService>(context, listen: false);
                  final deps = ds.departamentos;
                  // Fallback de compatibilidade: produtos antigos com paraCozinha/paraBar
                  // mas sem departamentoId selecionado.
                  if (_departamentoId == null && deps.isNotEmpty) {
                    if (_paraCozinha) {
                      final dep = deps.firstWhere((d) => d.nome.toLowerCase() == 'cozinha', orElse: () => deps.first);
                      _departamentoId = dep.id;
                    } else if (_paraBar) {
                      final dep = deps.firstWhere((d) => d.nome.toLowerCase() == 'bar', orElse: () => deps.first);
                      _departamentoId = dep.id;
                    }
                  }
                  return DropdownButtonFormField<String?>(
                    value: _departamentoId,
                    dropdownColor: const Color(0xFF2A2D3E),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Nenhum departamento',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                      filled: true,
                      fillColor: Colors.black12,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Nenhum departamento', style: TextStyle(color: Colors.white70)),
                      ),
                      ...deps.map((dep) => DropdownMenuItem<String?>(
                            value: dep.id,
                            child: Text(dep.nome, style: const TextStyle(color: Colors.white)),
                          )),
                    ],
                    onChanged: (val) => setState(() {
                      _departamentoId = val;
                      // Compatibilidade: deriva os flags antigos de cozinha/bar
                      // a partir do departamento escolhido, para as telas de
                      // mesas/comandas que ainda leem paraCozinha/paraBar.
                      final nome = ds.nomeDepartamento(val).toLowerCase();
                      _paraCozinha = nome == 'cozinha';
                      _paraBar = nome == 'bar';
                    }),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── IMPRESSÃO POR DEPARTAMENTO (multi-seleção) ─────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Builder(builder: (context) {
              final ds = Provider.of<DataService>(context, listen: false);
              final deps = ds.departamentos;
              final destinoResolvido = _impressorasProducaoDoProduto();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.print, color: Colors.blueAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Impressão de Produção',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'O ticket imprime na impressora configurada no departamento acima e em cada departamento extra marcado abaixo (a impressora de cada um é definida no cadastro de Departamentos).',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  if (deps.isEmpty)
                    Text(
                      'Nenhum departamento cadastrado. Cadastre os departamentos no menu → Departamentos.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: deps.map((dep) {
                        final ehPrincipal = dep.id == _departamentoId;
                        final selecionado = _departamentosAdicionais.contains(dep.id);
                        return FilterChip(
                          label: Text(
                            dep.nome + (ehPrincipal ? ' ★' : ''),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: ehPrincipal || selecionado,
                          // O principal já imprime — chip desabilitado como extra
                          onSelected: ehPrincipal
                              ? null
                              : (sel) => setState(() {
                                  if (sel) {
                                    if (!_departamentosAdicionais.contains(dep.id)) {
                                      _departamentosAdicionais.add(dep.id);
                                    }
                                  } else {
                                    _departamentosAdicionais.remove(dep.id);
                                  }
                                }),
                          selectedColor: Colors.tealAccent.withOpacity(0.25),
                          checkmarkColor: Colors.tealAccent,
                          backgroundColor: Colors.white.withOpacity(0.05),
                          side: BorderSide(
                            color: ehPrincipal || selecionado ? Colors.tealAccent : Colors.white24,
                          ),
                          labelStyle: TextStyle(
                            color: ehPrincipal || selecionado ? Colors.white : Colors.white70,
                            fontWeight: ehPrincipal || selecionado ? FontWeight.bold : FontWeight.normal,
                          ),
                          avatar: Icon(
                            ehPrincipal ? Icons.star : Icons.print_outlined,
                            size: 16,
                            color: ehPrincipal
                                ? Colors.amberAccent
                                : (selecionado ? Colors.tealAccent : Colors.white54),
                          ),
                        );
                      }).toList(),
                    ),
                  if (destinoResolvido.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Vai imprimir em: ${destinoResolvido.join(' • ')}',
                        style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),
                  // Teste de impressão de produção
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testarImpressaoProducao,
                      icon: const Icon(Icons.print_outlined, color: Colors.amberAccent, size: 18),
                      label: const Text(
                        'TESTAR IMPRESSÃO DE PRODUÇÃO',
                        style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: const BorderSide(color: Colors.amberAccent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Imprime um ticket de exemplo na(s) impressora(s) acima para conferir se o layout e a impressora estão certos.',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                  ),
                ],
              );
            }),
          ),
        ]),

        _buildSection('Preços e Estoque', [
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'Preço Venda',
                  child: TextFormField(
                    controller: _precoController,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: _minimalInput('0.00'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      _preco = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                      setState(() {});
                    },
                  ),
                ),
              ),
              if (_podeVerCusto()) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: _buildField(
                    label: 'Preço de Custo',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _precoCustoController,
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                          decoration: _minimalInput('0.00'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            _precoCusto = double.tryParse(v.replaceAll(',', '.'));
                            setState(() {});
                          },
                        ),
                        if (_precoCusto != null && _precoCusto! > 0 && _preco > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(_calcularMargemLucro(), style: const TextStyle(color: Colors.blueAccent, fontSize: 10)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'Estoque Atual',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _estoqueController,
                              style: TextStyle(
                                color: widget.item != null ? Colors.white.withOpacity(0.5) : Colors.white, 
                                fontSize: 18, 
                                fontWeight: FontWeight.bold
                              ),
                              decoration: _minimalInput('0').copyWith(
                                suffixText: widget.item != null ? '🔒 Bloqueado' : null,
                                suffixStyle: const TextStyle(fontSize: 10, color: Colors.white24),
                              ),
                              keyboardType: TextInputType.number,
                              readOnly: widget.item != null, // Bloquear edição direta em produtos existentes
                              onChanged: (v) => _estoque = double.tryParse(v.replaceAll(',', '.')) ?? 0.0,
                            ),
                          ),
                           if (widget.item != null) ...[
                            TextButton.icon(
                              icon: const Icon(Icons.playlist_add_circle_outlined, size: 16, color: Colors.blueAccent),
                              label: const Text('AJUSTAR', style: TextStyle(fontSize: 10, color: Colors.blueAccent)),
                              onPressed: _exibirDialogoAjusteEstoque,
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                            ),
                            const SizedBox(width: 4),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
                              label: const Text('ZERAR', style: TextStyle(fontSize: 10, color: Colors.redAccent)),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E2E),
                                    title: const Text('Zerar Estoque', style: TextStyle(color: Colors.white)),
                                    content: const Text(
                                      'Tem certeza que deseja zerar o estoque deste produto? Isso registrará um movimento de saída correspondente.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          final dataService = Provider.of<DataService>(context, listen: false);
                                          final authService = Provider.of<AuthService>(context, listen: false);
                                          final nomeUsuario = authService.usuarioAtual?.nome ?? 'Sistema';
                                          
                                          try {
                                            await dataService.zerarEstoqueCompleto(
                                              produtoId: widget.item.id,
                                              usuario: nomeUsuario,
                                            );
                                              
                                            setState(() {
                                              final prod = dataService.produtos.firstWhere((p) => p.id == widget.item.id);
                                              _estoque = prod.estoque;
                                              _estoquePorFornecedor = Map<String, double>.from(prod.estoquePorFornecedor);
                                              _estoqueController.text = _estoque.toString();
                                            });
                                            
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('✓ Todo o estoque de fornecedores e o geral foram zerados!'), backgroundColor: Colors.green),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Erro ao zerar estoque: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        },
                                        child: const Text('CONFIRMAR'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                            ),
                          ],
                        ],
                      ),
                      if (_estoquePorFornecedor.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: _estoquePorFornecedor.entries
                              .where((e) => e.value != 0)
                              .map((e) => InkWell(
                                onTap: () {
                                  // Abrir diálogo de ajuste focando neste fornecedor
                                  _fornecedorNomeController.text = e.key;
                                  _exibirDialogoAjusteEstoque();
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${e.key}: ${e.value}',
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () {
                                          // Confirmar zeramento individual deste fornecedor
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(0xFF1E1E2E),
                                              title: Text('Zerar fornecedor ${e.key}', style: const TextStyle(color: Colors.white)),
                                              content: Text('Deseja zerar o estoque exclusivo do fornecedor "${e.key}"?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx),
                                                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                  onPressed: () async {
                                                    Navigator.pop(ctx);
                                                    final dataService = Provider.of<DataService>(context, listen: false);
                                                    final authService = Provider.of<AuthService>(context, listen: false);
                                                    final nomeUsuario = authService.usuarioAtual?.nome ?? 'Sistema';
                                                    
                                                    try {
                                                      if (e.value > 0) {
                                                        await dataService.registrarSaidaEstoque(
                                                          produtoId: widget.item.id,
                                                          quantidade: e.value,
                                                          fornecedorNome: e.key,
                                                          motivo: 'ajuste',
                                                          observacao: 'Zerar estoque individual do fornecedor "${e.key}" por $nomeUsuario',
                                                          usuario: nomeUsuario,
                                                        );
                                                      } else {
                                                        await dataService.registrarEntradaEstoque(
                                                          produtoId: widget.item.id,
                                                          quantidade: e.value.abs(),
                                                          fornecedorNome: e.key,
                                                          observacao: 'Zerar estoque individual (entrada) do fornecedor "${e.key}" por $nomeUsuario',
                                                          usuario: nomeUsuario,
                                                        );
                                                      }
                                                      
                                                      setState(() {
                                                        final prod = dataService.produtos.firstWhere((p) => p.id == widget.item.id);
                                                        _estoque = prod.estoque;
                                                        _estoquePorFornecedor = Map<String, double>.from(prod.estoquePorFornecedor);
                                                        _estoqueController.text = _estoque.toString();
                                                      });
                                                      
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('✓ Estoque de "${e.key}" zerado!'), backgroundColor: Colors.green),
                                                      );
                                                    } catch (err) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Erro ao zerar: $err'), backgroundColor: Colors.red),
                                                      );
                                                    }
                                                  },
                                                  child: const Text('CONFIRMAR'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        child: Icon(Icons.cancel, size: 14, color: Colors.redAccent.withOpacity(0.7)),
                                      ),
                                    ],
                                  ),
                                ),
                              )).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildField(
                  label: 'Estoque Mínimo',
                  last: true,
                  child: TextFormField(
                    controller: _estoqueMinimoController,
                    style: TextStyle(color: Colors.orangeAccent.shade100, fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: _minimalInput('Ex: 5'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
            ],
          ),
        ]),

        // Só exibir a seção de lotes para produto JÁ SALVO (ID preenchido) —
        // nunca para Serviços nem para clones/novos produtos ainda não salvos.
        if (widget.item is Produto && (widget.item!.id ?? '').toString().isNotEmpty) _buildLotesSection(),

        _buildSection('Tabelas de Preço', [
          _buildPrecosInteligentes(),
        ]),

        _buildSection('Agrupamento e Fornecedor', [
          _buildField(
            label: 'Fornecedor Principal',
            child: Row(
              children: [
                Expanded(
                  child: _buildAutocomplete(
                    controller: _fornecedorNomeController,
                    hint: 'Ex: Ambev, Nestlé, etc',
                    sugestoes: _obterFornecedoresUnicos(),
                  ),
                ),
                if (_fornecedorNomeController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                    onPressed: () {
                      setState(() {
                        _fornecedorNomeController.clear();
                        _fornecedorId = null;
                      });
                    },
                  ),
              ],
            ),
          ),
          _buildField(
            label: 'Grupo / Categoria',
            child: _buildAutocomplete(
              controller: _grupoController,
              hint: 'Ex: Bebidas',
              sugestoes: _obterGruposUnicos(),
              onChanged: (v) => _grupo = v,
            ),
          ),
          _buildField(
            label: 'Subgrupo',
            child: _buildAutocomplete(
              controller: _subgrupoController,
              hint: 'Ex: Refrigerantes (dentro de Bebidas)',
              sugestoes: _obterSubgruposUnicos(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _buildField(
            label: 'Unidade de Medida',
            child: _buildAutocomplete(
              controller: _unidadeController,
              hint: 'Ex: UN, KG, LT',
              sugestoes: _obterUnidadesUnicas(),
              onChanged: (v) => setState(() => _unidade = v),
            ),
          ),
          _buildField(
            label: 'Formas de Venda',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venda o mesmo produto de várias formas sem cadastrar itens duplicados. No PDV você escolhe qual forma usar.',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 10),
                ..._formasVenda.asMap().entries.map((entry) {
                  final index = entry.key;
                  final forma = entry.value;
                  return _buildFormaVendaRow(index, forma);
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _exibirDialogoNovaFormaVenda,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar Forma de Venda'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent,
                      side: BorderSide(color: Colors.blueAccent.withOpacity(0.4)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                  ),
                  child: Text(
                    '💡 Ex.: ração vendida por unidade (R\$ 120,00) e por pacote de 3 kg (R\$ 35,00). Cada forma tem seu preço e sua baixa no estoque.',
                    style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
            last: true,
          ),
        ]),

        _buildSection('Promoção', [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Preço promocional (data a data)', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              Switch(
                value: _temPromocao,
                activeColor: Colors.orangeAccent,
                onChanged: (v) => setState(() => _temPromocao = v),
              ),
            ],
          ),
          if (_temPromocao) ...[
            const SizedBox(height: 12),
            _buildField(
              label: 'Preço Promocional (R\$)',
              last: true,
              child: TextFormField(
                controller: _precoPromocionalController,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold),
                decoration: _minimalInput('0.00'),
                onChanged: (v) => _precoPromocional = double.tryParse(v.replaceAll(',', '.')),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDataPromoField(
                    label: 'Início',
                    data: _promocaoInicio,
                    onTap: () => _selecionarDataPromocao(inicio: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDataPromoField(
                    label: 'Fim',
                    data: _promocaoFim,
                    onTap: () => _selecionarDataPromocao(inicio: false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.sell_outlined, size: 16, color: Colors.deepPurpleAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Regras de promoção (empilháveis)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Crie várias regras: por dia da semana, por quantidade levada ou por valor mínimo do produto no carrinho. Os descontos somam-se entre si e com o preço promocional acima.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (_promocoes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nenhuma regra criada.', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 12)),
            )
          else
            ..._promocoes.asMap().entries.map((entry) {
              final regra = entry.value;
              return Card(
                color: regra.ativo ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.02),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.percent, color: regra.ativo ? Colors.deepPurpleAccent : Colors.white24),
                  title: Text(
                    regra.nome ?? regra.tipo.rotulo,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${regra.tipo.rotulo} · ${regra.descricaoCondicao}\n${regra.descricaoDesconto}${regra.ativo ? '' : ' · DESATIVADA'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueAccent),
                        onPressed: () => _exibirDialogoRegraPromocao(regra: regra, index: entry.key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        onPressed: () => setState(() => _promocoes.removeAt(entry.key)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _exibirDialogoRegraPromocao(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Regra'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurpleAccent),
            ),
          ),
        ]),
      ],
    );
  }

  /// Campo compacto para seleção de data da promoção simples.
  Widget _buildDataPromoField({
    required String label,
    required DateTime? data,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: data == null ? Colors.white38 : Colors.orangeAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(
                    data == null ? '—' : DateFormat('dd/MM/yyyy').format(data!),
                    style: TextStyle(
                      color: data == null ? Colors.white54 : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (data != null)
              InkWell(
                onTap: onClear ??
                    () => setState(() {
                      if (label == 'Início') {
                        _promocaoInicio = null;
                      } else {
                        _promocaoFim = null;
                      }
                    }),
                child: const Icon(Icons.close, size: 14, color: Colors.white38),
              ),
          ],
        ),
      ),
    );
  }

  /// Abre o seletor de data para a promoção simples (início ou fim).
  Future<void> _selecionarDataPromocao({required bool inicio}) async {
    final agora = DateTime.now();
    final selecionada = await showDatePicker(
      context: context,
      initialDate: inicio ? (_promocaoInicio ?? agora) : (_promocaoFim ?? agora),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: inicio ? 'Início da promoção' : 'Fim da promoção',
    );
    if (selecionada == null) return;
    setState(() {
      if (inicio) {
        _promocaoInicio = selecionada;
      } else {
        _promocaoFim = selecionada;
      }
    });
  }

  /// Diálogo para adicionar/editar uma regra de promoção.
  Future<void> _exibirDialogoRegraPromocao({RegraPromocao? regra, int? index}) async {
    final nomeController = TextEditingController(text: regra?.nome ?? '');
    final valorController = TextEditingController();
    TipoRegraPromocao tipoSelecionado = regra?.tipo ?? TipoRegraPromocao.diaSemana;
    bool usaFixo = regra?.usaPrecoFixo ?? false;
    if (regra?.descontoPercentual != null && regra!.descontoPercentual! > 0) {
      valorController.text = regra.descontoPercentual!.toString().replaceAll('.', ',');
    } else if (regra?.precoFixo != null && regra!.precoFixo! > 0) {
      valorController.text = regra.precoFixo!.toString().replaceAll('.', ',');
    }
    DateTime? dataInicio = regra?.dataInicio;
    DateTime? dataFim = regra?.dataFim;
    final Set<int> diasSelecionados = Set<int>.from(regra?.diasSemana ?? []);
    int? horaInicioMin = regra?.horaInicioMin;
    int? horaFimMin = regra?.horaFimMin;
    final qtdMinimaController = TextEditingController(
      text: (regra?.quantidadeMinima ?? 0) > 0 ? regra!.quantidadeMinima.toString().replaceAll('.', ',') : '',
    );
    final valorMinimoController = TextEditingController(
      text: (regra?.valorMinimo ?? 0) > 0 ? regra!.valorMinimo.toString().replaceAll('.', ',') : '',
    );
    bool ativo = regra?.ativo ?? true;

    const nomesDias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

    Future<void> pickDate({required bool inicio}) async {
      final agora = DateTime.now();
      final sel = await showDatePicker(
        context: context,
        initialDate: inicio ? (dataInicio ?? agora) : (dataFim ?? agora),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (sel == null) return;
      if (inicio) {
        dataInicio = sel;
      } else {
        dataFim = sel;
      }
    }

    Future<void> pickTime({required bool inicio}) async {
      final atual = inicio ? horaInicioMin : horaFimMin;
      final sel = await showTimePicker(
        context: context,
        initialTime: atual != null
            ? TimeOfDay(hour: atual ~/ 60, minute: atual % 60)
            : const TimeOfDay(hour: 8, minute: 0),
      );
      if (sel == null) return;
      final min = sel.hour * 60 + sel.minute;
      if (inicio) {
        horaInicioMin = min;
      } else {
        horaFimMin = min;
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: Text(regra == null ? 'Nova Regra de Promoção' : 'Editar Regra de Promoção',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nomeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nome (opcional, ex: Terça da Ração)',
                      labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tipo de condição', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: TipoRegraPromocao.values.map((t) {
                      final selecionado = tipoSelecionado == t;
                      return ChoiceChip(
                        label: Text(t.rotulo, style: TextStyle(color: selecionado ? Colors.white : Colors.white70, fontSize: 11)),
                        selected: selecionado,
                        selectedColor: Colors.deepPurpleAccent.withOpacity(0.5),
                        backgroundColor: Colors.white.withOpacity(0.05),
                        onSelected: (_) => setStateModal(() => tipoSelecionado = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tipo de desconto', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDescontoChip(
                          rotulo: 'Percentual (%)',
                          selecionado: !usaFixo,
                          cor: Colors.orangeAccent,
                          onTap: () => setStateModal(() => usaFixo = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDescontoChip(
                          rotulo: 'Preço fixo (R\$)',
                          selecionado: usaFixo,
                          cor: Colors.greenAccent,
                          onTap: () => setStateModal(() => usaFixo = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: usaFixo ? Colors.greenAccent : Colors.orangeAccent),
                    decoration: InputDecoration(
                      labelText: usaFixo ? 'Preço fixo (R\$)' : 'Desconto (%)',
                      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  if (tipoSelecionado == TipoRegraPromocao.data) ...[...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDataPromoField(
                            label: 'Início',
                            data: dataInicio,
                            onTap: () async {
                              await pickDate(inicio: true);
                              setStateModal(() {});
                            },
                            onClear: () => setStateModal(() => dataInicio = null),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDataPromoField(
                            label: 'Fim',
                            data: dataFim,
                            onTap: () async {
                              await pickDate(inicio: false);
                              setStateModal(() {});
                            },
                            onClear: () => setStateModal(() => dataFim = null),
                          ),
                        ),
                      ],
                    ),
                  ]],
                  if (tipoSelecionado == TipoRegraPromocao.diaSemana) ...[...[
                    const SizedBox(height: 14),
                    const Text('Dias da semana (toque para marcar)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(7, (i) {
                        final dia = i + 1; // 1=Seg .. 7=Dom
                        final selecionado = diasSelecionados.contains(dia);
                        return FilterChip(
                          label: Text(nomesDias[i], style: TextStyle(color: selecionado ? Colors.white : Colors.white70, fontSize: 11)),
                          selected: selecionado,
                          selectedColor: Colors.orangeAccent.withOpacity(0.4),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          onSelected: (v) => setStateModal(() {
                            if (v) {
                              diasSelecionados.add(dia);
                            } else {
                              diasSelecionados.remove(dia);
                            }
                          }),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await pickTime(inicio: true);
                              setStateModal(() {});
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                'De: ${horaInicioMin == null ? '—' : RegraPromocao.fmtHora(horaInicioMin!)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await pickTime(inicio: false);
                              setStateModal(() {});
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                'Até: ${horaFimMin == null ? '—' : RegraPromocao.fmtHora(horaFimMin!)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]],
                  if (tipoSelecionado == TipoRegraPromocao.quantidade) ...[...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtdMinimaController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Quantidade mínima levada',
                        labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                    ),
                  ]],
                  if (tipoSelecionado == TipoRegraPromocao.valorMinimo) ...[...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: valorMinimoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Valor mínimo do produto no carrinho (R\$)',
                        labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                    ),
                  ]],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.toggle_on_outlined, size: 16, color: Colors.white54),
                      const SizedBox(width: 6),
                      const Text('Regra ativa', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      Switch(
                        value: ativo,
                        activeColor: Colors.greenAccent,
                        onChanged: (v) => setStateModal(() => ativo = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () {
                  final descontoPerc = double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0;
                  final qtdMinima = double.tryParse(qtdMinimaController.text.replaceAll(',', '.')) ?? 0.0;
                  final vMinimo = double.tryParse(valorMinimoController.text.replaceAll(',', '.')) ?? 0.0;
                  final novaRegra = RegraPromocao(
                    tipo: tipoSelecionado,
                    nome: nomeController.text.trim().isEmpty ? null : nomeController.text.trim(),
                    ativo: ativo,
                    descontoPercentual: !usaFixo && descontoPerc > 0 ? descontoPerc : null,
                    precoFixo: usaFixo && descontoPerc > 0 ? descontoPerc : null,
                    dataInicio: tipoSelecionado == TipoRegraPromocao.data ? dataInicio : null,
                    dataFim: tipoSelecionado == TipoRegraPromocao.data ? dataFim : null,
                    diasSemana: tipoSelecionado == TipoRegraPromocao.diaSemana ? diasSelecionados.toList() : const [],
                    horaInicioMin: tipoSelecionado == TipoRegraPromocao.diaSemana ? horaInicioMin : null,
                    horaFimMin: tipoSelecionado == TipoRegraPromocao.diaSemana ? horaFimMin : null,
                    quantidadeMinima: tipoSelecionado == TipoRegraPromocao.quantidade && qtdMinima > 0 ? qtdMinima : null,
                    valorMinimo: tipoSelecionado == TipoRegraPromocao.valorMinimo && vMinimo > 0 ? vMinimo : null,
                  );
                  if (!novaRegra.temDesconto) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Informe o desconto percentual ou o preço fixo.')),
                    );
                    return;
                  }
                  if (!novaRegra.temConfiguracoesRelevantes) {
                    final String msg;
                    switch (novaRegra.tipo) {
                      case TipoRegraPromocao.data:
                        msg = 'Informe a data de início e/ou de fim da promoção.';
                        break;
                      case TipoRegraPromocao.diaSemana:
                        msg = 'Selecione pelo menos um dia da semana (ou defina o horário).';
                        break;
                      case TipoRegraPromocao.quantidade:
                        msg = 'Informe a quantidade mínima de itens.';
                        break;
                      case TipoRegraPromocao.valorMinimo:
                        msg = 'Informe o valor mínimo do produto no carrinho.';
                        break;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                    return;
                  }
                  setState(() {
                    if (index != null && index >= 0 && index < _promocoes.length) {
                      _promocoes[index] = novaRegra;
                    } else {
                      _promocoes.add(novaRegra);
                    }
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDescontoChip({
    required String rotulo,
    required bool selecionado,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selecionado ? cor.withOpacity(0.18) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selecionado ? cor.withOpacity(0.6) : Colors.white12),
        ),
        child: Text(
          rotulo,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selecionado ? cor : Colors.white70,
            fontSize: 12,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  Widget _buildAbaEcommerce() {
    return Column(
      children: [
        _buildSection('Visibilidade e Destaque', [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 16, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              const Text('Exibir na Loja Online', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Switch(
                value: _exibirNaLoja,
                activeColor: Colors.purpleAccent,
                onChanged: (v) => setState(() {
                  _exibirNaLoja = v;
                  if (!v) _emDestaque = false;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star_outline, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              const Text('Produto em Destaque', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Switch(
                value: _emDestaque,
                activeColor: Colors.orangeAccent,
                onChanged: _exibirNaLoja ? (v) => setState(() => _emDestaque = v) : null,
              ),
            ],
          ),
        ]),

        _buildSection('Logística (Frete)', [
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'Peso (g)',
                  child: TextFormField(
                    controller: _pesoGramasController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _minimalInput('Ex: 500'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _pesoGramas = int.tryParse(v),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildField(
                  label: 'Altura (cm)',
                  child: TextFormField(
                    controller: _alturaCmController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _minimalInput('0.0'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _alturaCm = double.tryParse(v.replaceAll(',', '.')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'Largura (cm)',
                  child: TextFormField(
                    controller: _larguraCmController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _minimalInput('0.0'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _larguraCm = double.tryParse(v.replaceAll(',', '.')),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildField(
                  label: 'Profundidade (cm)',
                  child: TextFormField(
                    controller: _profundidadeCmController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: _minimalInput('0.0'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _profundidadeCm = double.tryParse(v.replaceAll(',', '.')),
                  ),
                ),
              ),
            ],
          ),
        ]),

        _buildSection('Descrição Vitrine', [
          _buildField(
            label: 'Texto para Site',
            last: true,
            child: TextFormField(
              controller: _descricaoEcommerceController,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
              decoration: _minimalInput('Descrição detalhada para a loja...'),
              maxLines: 5,
              onChanged: (v) => _descricaoEcommerce = v.isEmpty ? null : v,
            ),
          ),
        ]),

        _buildSection('Fotos e Mídia', [
           _buildBotoesFotos(),
           if (_fotosUrls.isNotEmpty) ...[
             const SizedBox(height: 16),
             _buildGridFotos(),
           ],
        ]),

        const SizedBox(height: 16),
        _buildSecaoVariacoes(),
      ],
    );
  }
  
  Future<void> _adicionarFotos() async {
    try {
      setState(() {
        _uploadingFotos = true;
      });

      FilePickerResult? result;
      
      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true, // Obter bytes diretamente no web
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final empresaId = authService.empresaAtual?.id ?? 'default';
        final produtoId = widget.item?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
        
        final novasFotos = <String>[];
        
        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          String? fotoUrl;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          
          if (kIsWeb) {
            if (file.bytes == null || file.bytes!.isEmpty) {
              debugPrint('>>> Erro: Arquivo ${i + 1} não tem bytes');
              continue;
            }
            
            // Web: usar armazenamento GRATUITO no Firestore
            try {
              fotoUrl = await ImageStorageService.salvarImagemERetornarUrl(
                imageBytes: file.bytes!,
                empresaId: empresaId,
                categoria: 'produtos',
                nome: '${widget.item?.nome ?? "Produto"} - Foto ${i + 1}',
                metadata: {
                  'produto_id': produtoId,
                  'indice': i.toString(),
                  'timestamp': timestamp.toString(),
                },
              );
            } catch (e, stackTrace) {
              debugPrint('>>> ❌ ERRO ao salvar foto ${i + 1}: $e');
              debugPrint('>>> StackTrace: $stackTrace');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao salvar foto ${i + 1}: ${e.toString()}'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
              continue;
            }
          } else {
            if (file.path == null || file.path!.isEmpty) {
              debugPrint('>>> Erro: Arquivo ${i + 1} não tem caminho');
              continue;
            }
            
            // Mobile: ler arquivo e usar armazenamento GRATUITO
            try {
              final fileData = await File(file.path!).readAsBytes();
              fotoUrl = await ImageStorageService.salvarImagemERetornarUrl(
                imageBytes: fileData,
                empresaId: empresaId,
                categoria: 'produtos',
                nome: '${widget.item?.nome ?? "Produto"} - Foto ${i + 1}',
                metadata: {
                  'produto_id': produtoId,
                  'indice': i.toString(),
                  'timestamp': timestamp.toString(),
                },
              );
            } catch (e, stackTrace) {
              debugPrint('>>> ❌ Erro ao salvar foto ${i + 1}: $e');
              debugPrint('>>> StackTrace: $stackTrace');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao salvar foto ${i + 1}: ${e.toString()}'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
              continue;
            }
          }
          
          if (fotoUrl != null && fotoUrl.isNotEmpty) {
            novasFotos.add(fotoUrl);
            debugPrint('>>> ✅ Foto ${i + 1} salva com sucesso (GRATUITO no Firestore)');
          } else {
            debugPrint('>>> ❌ Erro: Upload da foto ${i + 1} retornou vazio');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro: Foto ${i + 1} retornou vazio'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
        
        if (mounted) {
          setState(() {
            _fotosUrls.addAll(novasFotos);
            _uploadingFotos = false;
          });
          
          if (novasFotos.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${novasFotos.length} foto(s) adicionada(s) com sucesso!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else if (result.files.isNotEmpty) {
            // Se havia arquivos mas nenhum foi enviado com sucesso
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Nenhuma foto foi enviada. Verifique os arquivos e tente novamente.'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _uploadingFotos = false;
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('>>> Erro ao adicionar fotos: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _uploadingFotos = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar fotos: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  Widget _buildBotoesFotos() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _uploadingFotos ? null : _adicionarFotos,
            icon: _uploadingFotos
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_a_photo_outlined, size: 16),
            label: Text(_uploadingFotos ? 'Enviando...' : 'Adicionar Fotos', style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent.withOpacity(0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        if (_fotosUrls.isNotEmpty) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
            onPressed: () => setState(() => _fotosUrls.clear()),
            tooltip: 'Remover Todas',
          ),
        ],
      ],
    );
  }

  Widget _buildGridFotos() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _fotosUrls.length,
      itemBuilder: (context, index) {
        final url = _fotosUrls[index];
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                border: Border.all(color: index == 0 ? Colors.purpleAccent : Colors.white10),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => setState(() => _fotosUrls.removeAt(index)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
            if (index == 0)
              Positioned(
                bottom: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.purpleAccent, borderRadius: BorderRadius.circular(4)),
                  child: const Text('CAPA', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAbaImpostos() {
    return Column(
      children: [
        _buildSection('Perfil Tributário', [
          _buildField(
            label: 'Perfil de Impostos do Produto',
            last: true,
            child: Consumer<DataService>(
              builder: (context, service, _) {
              // Mostra apenas os perfis do regime tributário atual da empresa
              final perfis = service.perfisTributariosDoRegime;
              return DropdownButtonFormField<String?>(
              // Guard: se o perfil salvo foi excluído da lista, cai em "Sem Perfil"
              value: perfis.any((p) => p.id == _perfilTributarioId)
                  ? _perfilTributarioId
                  : null,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF161621),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sem Perfil / Manual', style: TextStyle(color: Colors.white54)),
                ),
                ...perfis.map((p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(p.nome, style: const TextStyle(color: Colors.white)),
                )),
              ],
              onChanged: (v) {
                setState(() {
                  _perfilTributarioId = v;
                  if (v != null) {
                    PerfilTributario? perfil;
                    for (final p in perfis) {
                      if (p.id == v) { perfil = p; break; }
                    }
                    if (perfil != null) {
                      // Preenche automaticamente todos os campos fiscais a partir do perfil
                      _cfop = perfil.cfop;
                      _cfopController.text = perfil.cfop;
                      _csosn = perfil.csosn;
                      _csosnController.text = perfil.csosn ?? '';
                      _icmsCst = perfil.icmsCst;
                      _icmsCstController.text = perfil.icmsCst ?? '';
                      _ncm = perfil.ncm;
                      _ncmController.text = perfil.ncm ?? '';
                      _pisCst = perfil.pisCst;
                      _pisCstController.text = perfil.pisCst ?? '';
                      _cofinsCst = perfil.cofinsCst;
                      _cofinsCstController.text = perfil.cofinsCst ?? '';
                      _icmsAliquota = perfil.aliquotaIcms;
                      _icmsAliquotaController.text = perfil.aliquotaIcms?.toString() ?? '';
                      _pisAliquota = perfil.aliquotaPis;
                      _pisAliquotaController.text = perfil.aliquotaPis?.toString() ?? '';
                      _cofinsAliquota = perfil.aliquotaCofins;
                      _cofinsAliquotaController.text = perfil.aliquotaCofins?.toString() ?? '';
                    }
                  }
                });
              },
              );
              },
            ),
          ),
        ]),

        _buildSection('Documentação Fiscal', [
          _buildField(
            label: 'NCM',
            child: TextFormField(
              controller: _ncmController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('Ex: 85171200'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _ncm = v,
            ),
          ),
          _buildField(
            label: 'Origem da Mercadoria',
            child: TextFormField(
              controller: _origemController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('0-Nacional, 1-Estrangeira...'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _origem = v,
            ),
          ),
          _buildField(
            label: 'CFOP Padrão',
            last: true,
            child: TextFormField(
              controller: _cfopController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('Ex: 5102'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _cfop = v,
            ),
          ),
        ]),

        _buildSection('Simples Nacional / CRT', [
          _buildField(
            label: 'CSOSN',
            child: TextFormField(
              controller: _csosnController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('Ex: 102'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _csosn = v,
            ),
          ),
          _buildField(
            label: 'Alíquota Simples (%)',
            last: true,
            child: TextFormField(
              controller: _simplesNacionalAliquotaController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('0.00'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _simplesNacionalAliquota = double.tryParse(v.replaceAll(',', '.')),
            ),
          ),
          // ═══ AVISO DE INCOMPATIBILIDADE CFOP × CSOSN ═══
          if (_cfop != null && _csosn != null && _cfop!.isNotEmpty && _csosn!.isNotEmpty)
            Builder(
              builder: (ctx) {
                final cfop = _cfop!.replaceAll(RegExp(r'[^0-9]'), '');
                final csosn = _csosn!.replaceAll(RegExp(r'[^0-9]'), '');
                if (!_validarCfopCsosn(cfop, csosn)) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '⚠️ CFOP incompatível com o CSOSN!',
                                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _sugestaoCfopCsosn(cfop, csosn),
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final correcao = _corrigirCfopCsosnLocal(cfop, csosn);
                            setState(() {
                              _cfop = correcao['cfop'];
                              _cfopController.text = correcao['cfop']!;
                              _csosn = correcao['csosn'];
                              _csosnController.text = correcao['csosn']!;
                            });
                          },
                          child: const Text('CORRIGIR', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        ]),

        _buildSection('ICMS Detalhado', [
          _buildField(
            label: 'CST ICMS',
            child: TextFormField(
              controller: _icmsCstController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('Ex: 00'),
              onChanged: (v) => _icmsCst = v,
            ),
          ),
          _buildField(
            label: 'Alíquota ICMS (%)',
            last: true,
            child: TextFormField(
              controller: _icmsAliquotaController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _minimalInput('0.00'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _icmsAliquota = double.tryParse(v.replaceAll(',', '.')),
            ),
          ),
        ]),

        _buildSection('Outros Impostos (IPI/PIS/COFINS)', [
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'CST PIS',
                  child: TextFormField(
                    controller: _pisCstController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _minimalInput('01'),
                    onChanged: (v) => _pisCst = v,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildField(
                  label: 'CST COFINS',
                  child: TextFormField(
                    controller: _cofinsCstController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _minimalInput('01'),
                    onChanged: (v) => _cofinsCst = v,
                  ),
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }
  
  // Seção de Variações de Produto
  Widget _buildSecaoVariacoes() {
    return _buildSection('Variações de Produto', [
      Row(
        children: [
          const Icon(Icons.layers_outlined, size: 16, color: Colors.blueAccent),
          const SizedBox(width: 8),
          const Text('Produto com Variações', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Switch(
            value: _temVariacoes,
            activeColor: Colors.blueAccent,
            onChanged: (v) => setState(() {
              _temVariacoes = v;
              if (!v) _variacoes.clear();
            }),
          ),
        ],
      ),
      if (_temVariacoes) ...[
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _adicionarVariacao,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nova Variação', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent.withOpacity(0.1),
            foregroundColor: Colors.blueAccent,
            side: const BorderSide(color: Colors.blueAccent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (_variacoes.isNotEmpty) ...[
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _variacoes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final variacao = _variacoes[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${variacao.nomeAtributo}: ${variacao.valor}',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    if (variacao.precoAdicional != null && variacao.precoAdicional! > 0)
                      Text(
                        '+ R\$ ${variacao.precoAdicional!.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                      onPressed: () => setState(() => _variacoes.removeAt(index)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    ]);
  }

  void _adicionarVariacao() {
    _mostrarDialogVariacao();
  }
  
  void _editarVariacao(int index) {
    _mostrarDialogVariacao(variacao: _variacoes[index], index: index);
  }
  
  void _removerVariacao(int index) {
    setState(() {
      _variacoes.removeAt(index);
    });
  }
  
  void _mostrarDialogVariacao({VariacaoProduto? variacao, int? index}) {
    final nomeAtributoController = TextEditingController(text: variacao?.nomeAtributo ?? '');
    final valorController = TextEditingController(text: variacao?.valor ?? '');
    final precoAdicionalController = TextEditingController(text: variacao?.precoAdicional?.toString() ?? '');
    final estoqueController = TextEditingController(text: variacao?.estoque.toString() ?? '0');
    final codigoBarrasController = TextEditingController(text: variacao?.codigoBarras ?? '');
    final skuController = TextEditingController(text: variacao?.sku ?? '');
    bool ativo = variacao?.ativo ?? true;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
          title: Text(variacao == null ? 'Nova Variação' : 'Editar Variação', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(
                  label: 'Atributo (ex: Tamanho)',
                  child: TextFormField(
                    controller: nomeAtributoController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _minimalInput('Ex: Cor'),
                  ),
                ),
                _buildField(
                  label: 'Valor (ex: G)',
                  child: TextFormField(
                    controller: valorController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _minimalInput('Ex: Azul'),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        label: 'Preço +',
                        child: TextFormField(
                          controller: precoAdicionalController,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
                          decoration: _minimalInput('0.00'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildField(
                        label: 'Estoque',
                        child: TextFormField(
                          controller: estoqueController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: _minimalInput('0'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
                _buildField(
                  label: 'Cód. Barras / SKU',
                  last: true,
                  child: TextFormField(
                    controller: codigoBarrasController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _minimalInput('Opcional'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ElevatedButton(
              onPressed: () {
                if (nomeAtributoController.text.isEmpty || valorController.text.isEmpty) return;
                
                final novaVariacao = VariacaoProduto(
                  id: (variacao?.id != null && variacao!.id.isNotEmpty)
                      ? variacao!.id
                      : _uuid.v4(),
                  nomeAtributo: nomeAtributoController.text.trim(),
                  valor: valorController.text.trim(),
                  precoAdicional: double.tryParse(precoAdicionalController.text.replaceAll(',', '.')),
                  estoque: (int.tryParse(estoqueController.text) ?? 0).toDouble(),
                  codigoBarras: codigoBarrasController.text.trim(),
                  sku: skuController.text.trim(),
                  ativo: ativo,
                );
                
                setState(() {
                  if (index != null) _variacoes[index] = novaVariacao;
                  else _variacoes.add(novaVariacao);
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildAbaEstoque() {
    if (widget.item == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Salve o produto primeiro para gerenciar o estoque.',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCentralEstoqueMinimo(),
          const SizedBox(height: 8),
          _buildConteudoHistoricoEstoque(),
        ],
      ),
    );
  }

  Widget _buildCentralEstoqueMinimo() {
    final double minEstoque = double.tryParse(_estoqueMinimoController.text) ?? 0.0;
    final double atualEstoque = _estoque;
    
    String status = "ESTOQUE NORMAL";
    Color statusColor = Colors.greenAccent;
    IconData statusIcon = Icons.check_circle_outline;
    String dica = "Seu estoque está saudável.";
    
    if (minEstoque > 0) {
      if (atualEstoque == 0) {
        status = "ESTOQUE ZERADO";
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline;
        dica = "Reposição imediata necessária!";
      } else if (atualEstoque < minEstoque) {
        status = "ABAIXO DO MÍNIMO";
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.warning_amber_rounded;
        dica = "Reposição sugerida em breve.";
      } else if (atualEstoque == minEstoque) {
        status = "LIMITE ALCANÇADO";
        statusColor = Colors.yellowAccent;
        statusIcon = Icons.notification_important_outlined;
        dica = "Atenção: estoque no limite mínimo.";
      }
    } else {
      status = "MÍNIMO NÃO CONFIGURADO";
      statusColor = Colors.white24;
      statusIcon = Icons.settings_outlined;
      dica = "Configure o estoque mínimo na aba Básico.";
    }

    return Container(
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.15)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dica,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (minEstoque > atualEstoque)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Faltam: ${minEstoque - atualEstoque}',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard('Estoque Atual', atualEstoque.toString(), Colors.blueAccent, Icons.inventory_2),
              const SizedBox(width: 12),
              _buildStatCard('Estoque Mínimo', minEstoque.toString(), Colors.orangeAccent, Icons.low_priority),
            ],
          ),
          if (minEstoque > 0) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (atualEstoque / (minEstoque * 1.5)).clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 8,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color.withOpacity(0.5), size: 16),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudoHistoricoEstoque() {
    final dataService = Provider.of<DataService>(context);
    
    // Filtragem de dados baseada na visão selecionada (Este produto ou Geral)
    List<EstoqueHistorico> historicoFull = dataService.estoqueHistorico;
    
    final List<EstoqueHistorico> historico = historicoFull.where((h) {
      // Filtro de visão (este produto ou geral)
      if (!_estoqueVisaoGeral && h.produtoId != widget.item!.id) return false;
      
      // Filtros de data
      if (_estoqueDataInicial != null && h.data.isBefore(_estoqueDataInicial!)) return false;
      if (_estoqueDataFinal != null && h.data.isAfter(_estoqueDataFinal!.add(const Duration(days: 1)))) return false;
      
      // Filtro de tipo
      if (_estoqueTipoFiltro != null && h.tipo != _estoqueTipoFiltro) return false;
      
      return true;
    }).toList();
    
    historico.sort((a, b) => b.data.compareTo(a.data));

    // Fornecedores únicos para filtro
    final fornecedores = historicoFull
        .map((h) => h.fornecedorNome)
        .where((f) => f != null && f.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    fornecedores.sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabeçalho e Seleção de Visão
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RELATÓRIO DE MOVIMENTAÇÕES',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBotaoVisao('Este Item', !_estoqueVisaoGeral),
                  _buildBotaoVisao('Geral', _estoqueVisaoGeral),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Seção de Filtros "Inteligentes"
        _buildFiltrosHistorico(),
        const SizedBox(height: 16),

        // Resumo do período filtrado
        _buildResumoEstoque(historico),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _estoqueVisaoGeral ? 'TODAS AS MOVIMENTAÇÕES' : 'HISTÓRICO DO PRODUTO',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent.withOpacity(0.8)),
            ),
            if (!_estoqueVisaoGeral)
              TextButton.icon(
                onPressed: _exibirDialogoAjusteEstoque,
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: const Text('NOVA ENTRADA', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(foregroundColor: Colors.greenAccent, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (historico.isEmpty)
          _buildEmptyHistorico()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: historico.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final h = historico[index];
              Produto? prod;
              if (_estoqueVisaoGeral) {
                prod = dataService.produtos.firstWhere(
                  (p) => p.id == h.produtoId, 
                  orElse: () => Produto(
                    id: '', 
                    nome: 'Excluído', 
                    preco: 0, 
                    estoque: 0,
                    unidade: 'un',
                    grupo: 'Geral',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
              }
              return _buildItemHistoricoMelhorado(h, prod);
            },
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBotaoVisao(String label, bool selecionado) {
    return GestureDetector(
      onTap: () => setState(() => _estoqueVisaoGeral = label == 'Geral'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(color: selecionado ? Colors.white : Colors.white38, fontSize: 11, fontWeight: selecionBold(selecionado)),
        ),
      ),
    );
  }

  FontWeight selecionBold(bool s) => s ? FontWeight.bold : FontWeight.normal;

  Widget _buildFiltrosHistorico() {
    return Row(
      children: [
        // Data
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: _selecionarPeriodoEstoque,
            child: _boxFiltro(
              icon: Icons.calendar_today,
              label: '${DateFormat('dd/MM').format(_estoqueDataInicial!)} - ${DateFormat('dd/MM').format(_estoqueDataFinal!)}',
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Tipo
        Expanded(
          flex: 1,
          child: _boxFiltroDropdown(
            value: _estoqueTipoFiltro,
            hint: 'Tipo',
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos')),
              DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
              DropdownMenuItem(value: 'saida', child: Text('Saída')),
            ],
            onChanged: (v) => setState(() => _estoqueTipoFiltro = v),
          ),
        ),
      ],
    );
  }

  Widget _boxFiltro({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _boxFiltroDropdown({String? value, required String hint, required List<DropdownMenuItem<String?>> items, required Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E2E),
          hint: Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildResumoEstoque(List<EstoqueHistorico> lista) {
    final double ent = lista.where((h) => h.tipo == 'entrada').fold<double>(0.0, (p, e) => p + e.quantidade);
    final double sai = lista.where((h) => h.tipo == 'saida').fold<double>(0.0, (p, e) => p + e.quantidade);

    return Row(
      children: [
        _cardResumoPequeno('ENTRADAS', ent.toInt(), Colors.greenAccent),
        const SizedBox(width: 12),
        _cardResumoPequeno('SAÍDAS', sai.toInt(), Colors.redAccent),
      ],
    );
  }

  Widget _cardResumoPequeno(String label, int valor, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cor.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: cor.withOpacity(0.1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: cor.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.bold)),
            Text(valor.toString(), style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemHistoricoMelhorado(EstoqueHistorico h, Produto? p) {
    final isEntrada = h.tipo == 'entrada';
    final ehQuebra = (h.observacao?.toLowerCase().contains('quebra') ?? false) ||
        (h.observacao?.toLowerCase().contains('motivo: quebra') ?? false);
    final cor = isEntrada
        ? Colors.greenAccent
        : (ehQuebra ? Colors.orangeAccent : Colors.redAccent);
    final temCusto = h.valorCusto != null && h.valorCusto! > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ehQuebra ? Colors.orange.withOpacity(0.06) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ehQuebra ? Colors.orange.withOpacity(0.25) : Colors.white.withOpacity(0.03)),
      ),
      child: Row(
        children: [
          Icon(
            ehQuebra ? Icons.broken_image_rounded : (isEntrada ? Icons.arrow_downward : Icons.arrow_upward),
            color: cor.withOpacity(0.7),
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p != null)
                  Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Text(DateFormat('dd/MM/yy HH:mm').format(h.data), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                    const SizedBox(width: 8),
                    Text('Forn: ${h.fornecedorNome ?? "Geral"}', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 10)),
                    const SizedBox(width: 8),
                    Text('•', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
                    const SizedBox(width: 8),
                    Text(
                      'Usuário: ${h.usuario ?? "Sistema"}', 
                      style: TextStyle(color: Colors.orangeAccent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
                if (ehQuebra)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'QUEBRA',
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                  ),
                if (h.observacao != null && h.observacao!.isNotEmpty)
                  Text(h.observacao!, style: TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic), maxLines: 2),
                if (temCusto)
                  Text(
                    'Custo da mercadoria: R\$ ${h.valorCusto!.toStringAsFixed(2)}'
                    '${(h.custoUnitario != null && h.custoUnitario! > 0 ? ' (R\$ ${h.custoUnitario!.toStringAsFixed(2)}/un)' : '')}',
                    style: TextStyle(color: Colors.orangeAccent.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          Text('${isEntrada ? "+" : "-"}${h.quantidade}', style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEmptyHistorico() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off, size: 32, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),
          Text('Nenhuma movimentação encontrada.', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12)),
        ],
      ),
    );
  }

  // ============================================================
  // ABA DE HISTÓRICO DE ALTERAÇÕES (AUDITORIA)
  // ============================================================
  
  Widget _buildAbaHistoricoAlteracoes() {
    return FutureBuilder<List<ProdutoHistorico>>(
      future: _carregarHistoricoProduto(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.blueAccent),
                SizedBox(height: 16),
                Text(
                  'Carregando histórico...',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar histórico',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          );
        }

        final historico = snapshot.data ?? [];

        if (historico.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                const Text(
                  'Nenhuma alteração registrada',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'As mudanças no produto aparecerão aqui',
                  style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'HISTÓRICO DE ALTERAÇÕES',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${historico.length} registro(s)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Lista de alterações
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: historico.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = historico[index];
                return _buildItemHistoricoAlteracao(item);
              },
            ),
          ],
        );
      },
    );
  }

  Future<List<ProdutoHistorico>> _carregarHistoricoProduto() async {
    if (widget.item == null) return [];
    
    final dataService = Provider.of<DataService>(context, listen: false);
    return await dataService.buscarHistoricoProduto(widget.item!.id, limite: 50);
  }

  Widget _buildItemHistoricoAlteracao(ProdutoHistorico item) {
    final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(item.dataAlteracao);
    
    Color corOperacao;
    IconData iconeOperacao;
    String textoOperacao;
    
    switch (item.tipoOperacao) {
      case 'CREATE':
        corOperacao = Colors.green;
        iconeOperacao = Icons.add_circle;
        textoOperacao = 'Criação';
        break;
      case 'UPDATE':
        corOperacao = Colors.blue;
        iconeOperacao = Icons.edit;
        textoOperacao = 'Atualização';
        break;
      case 'DELETE':
        corOperacao = Colors.red;
        iconeOperacao = Icons.delete;
        textoOperacao = 'Exclusão';
        break;
      default:
        corOperacao = Colors.grey;
        iconeOperacao = Icons.help;
        textoOperacao = item.tipoOperacao;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho do item
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: corOperacao.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconeOperacao, color: corOperacao, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textoOperacao,
                      style: TextStyle(
                        color: corOperacao,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      dataFormatada,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Usuário
          if (item.usuarioNome.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 6),
                Text(
                  'Por: ${item.usuarioNome}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          
          // Campos alterados
          if (item.camposAlterados.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.camposAlterados.map((campo) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    campo,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          
          // Resumo das mudanças
          if (item.resumoMudancas != null && item.resumoMudancas!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.1)),
              ),
              child: Text(
                item.resumoMudancas!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selecionarPeriodoEstoque() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _estoqueDataInicial!, end: _estoqueDataFinal!),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.blueAccent, surface: Color(0xFF1E1E2E))),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _estoqueDataInicial = picked.start;
        _estoqueDataFinal = picked.end;
      });
    }
  }

  /// Chip de informação reutilizável na seção de combos
  Widget _chipBadge(IconData icon, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cor),
          const SizedBox(width: 4),
          Text(texto, style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Texto de prévia da baixa da opção (usado no diálogo de opção)
  String _previewTextoBaixa(TextEditingController nome, TextEditingController qtd, TextEditingController preco, String produtoNome) {
    final nomeOpcao = nome.text.trim().isEmpty ? produtoNome : nome.text.trim();
    final q = double.tryParse(qtd.text.replaceAll(',', '.')) ?? 1.0;
    final p = double.tryParse(preco.text.replaceAll(',', '.')) ?? 0.0;
    final qTxt = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
    final pTxt = p > 0 ? ' · +R\$ ${p.toStringAsFixed(2)}' : '';
    return 'No PDV: escolher "$nomeOpcao" → baixa $qTxt × $produtoNome$pTxt';
  }

  Widget _buildAbaComposicao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('Produto Composto', [
          Row(
            children: [
              const Icon(Icons.layers_rounded, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text('É um produto composto?', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Switch(
                value: _ehComposto,
                activeColor: Colors.blueAccent,
                onChanged: (v) => setState(() {
                  _ehComposto = v;
                  if (v) _exibirComposicaoPdv = true;
                }),
              ),
            ],
          ),
          if (_ehComposto) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ingredientes / Matérias-primas',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _exibirDialogoAdicionarComposicao,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adicionar Item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.2),
                    foregroundColor: Colors.blueAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '💡 Cada ingrediente tem 2 modos de baixa: (1) Fluxo comum — vende 15 e baixa 15 unidades; (2) Conversão — vende fracionado (ex.: kg) e a baixa é proporcional: completou 15 kg = 1 saco. No PDV o operador alterna entre os dois por venda.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 15, color: Colors.tealAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mostrar itens do kit no carrinho do PDV (ex.: Batata (1 UN))',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
                Switch(
                  value: _exibirComposicaoPdv,
                  activeColor: Colors.tealAccent,
                  onChanged: (v) => setState(() => _exibirComposicaoPdv = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _baixarEstoqueProprio
                      ? Icons.inventory_2_outlined
                      : Icons.local_drink_outlined,
                  size: 15,
                  color: _baixarEstoqueProprio ? Colors.blueAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _baixarEstoqueProprio
                        ? 'Baixar também o estoque DESTE produto ao vender'
                        : 'NÃO baixar o estoque deste produto — baixa só nos ingredientes (ex.: Chop controlado pelo Barril em ml)',
                    style: TextStyle(
                      color: _baixarEstoqueProprio ? Colors.white70 : Colors.orangeAccent,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Switch(
                  value: _baixarEstoqueProprio,
                  activeColor: Colors.orangeAccent,
                  onChanged: (v) => setState(() => _baixarEstoqueProprio = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_composicao.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: const Text('Nenhum ingrediente adicionado', style: TextStyle(color: Colors.white38)),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _composicao.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final item = _composicao[index];
                  final dataService = Provider.of<DataService>(context, listen: false);
                  final produtoOrigem = dataService.produtos.cast<Produto?>().firstWhere(
                    (p) => p?.id == item.produtoId,
                    orElse: () => null,
                  );
                  final nomeProduto = produtoOrigem?.nome ?? 'Produto Desconhecido';
                  final unidade = produtoOrigem?.unidade ?? 'un';
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(nomeProduto, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      item.pesoTotalSaco != null && item.fracaoBase != null
                          ? '⚖️ Vende fracionado: ${textoConversao(item.fracaoBase!, item.pesoTotalSaco!, unidadeBaixa: item.unidadeBaixa ?? unidade, unidadeVenda: item.unidadeVenda ?? widget.item?.unidade)}\n   Baixa proporcional por venda'
                          : 'Fluxo comum: baixa ${item.quantidade} $unidade por unidade vendida',
                      style: TextStyle(
                        color: item.pesoTotalSaco != null ? Colors.amber : Colors.blueAccent,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () => _exibirDialogoAdicionarComposicao(itemEdicao: item),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      onPressed: () {
                        setState(() {
                          _composicao.removeAt(index);
                        });
                      },
                    ),
                  );
                },
              ),
            // Resumo de custo da composição
            if (_composicao.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.attach_money, color: Colors.greenAccent, size: 18),
                        SizedBox(width: 6),
                        Text('Resumo de Custo', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._composicao.map((item) {
                      final p = Provider.of<DataService>(context, listen: false).produtos.cast<Produto?>().firstWhere((x) => x?.id == item.produtoId, orElse: () => null);
                      final custoUnit = p?.precoCusto ?? 0;
                      final custoItem = custoUnit * item.quantidade;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text('${p?.nome ?? "?"} (${item.quantidade}x)', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11))),
                            Text(custoUnit > 0 ? 'R\$ ${custoItem.toStringAsFixed(2)}' : 'Sem custo', style: TextStyle(color: custoUnit > 0 ? Colors.white70 : Colors.white30, fontSize: 11)),
                          ],
                        ),
                      );
                    }),
                    const Divider(color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Custo Total da Composição:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(
                          'R\$ ${_composicao.fold<double>(0, (sum, item) {
                            final p = Provider.of<DataService>(context, listen: false).produtos.cast<Produto?>().firstWhere((x) => x?.id == item.produtoId, orElse: () => null);
                            return sum + ((p?.precoCusto ?? 0) * item.quantidade);
                          }).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ]),
        const SizedBox(height: 24),

        // ================= COMBO / OPÇÕES DE SELEÇÃO =================
        _buildSection('Combo / Opções de Seleção', [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fastfood_rounded, color: Colors.tealAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Combo sem perguntas — kit fixo',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _composicao.isNotEmpty && _ehComposto
                            ? '✔ Kit com ${_composicao.length} ${_composicao.length == 1 ? 'item' : 'itens'}: vende 1 no carrinho e a baixa acontece em todos.'
                            : 'Selecione os itens do kit (ex.: batata + coca + lanche). Na venda entra 1 item no carrinho e a baixa acontece em todos.',
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _exibirDialogoCriarCombo,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    _composicao.isNotEmpty && _ehComposto ? 'EDITAR COMBO' : 'CRIAR COMBO',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.withOpacity(0.25),
                    foregroundColor: Colors.tealAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Divider(color: Colors.white12)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('ou use perguntas', style: TextStyle(color: Colors.white30, fontSize: 10)),
              ),
              Expanded(child: Divider(color: Colors.white12)),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Crie perguntas que aparecem no PDV ao vender este produto. Ex.: "Escolha o sabor", '
            'onde cada opção (ex.: Morango) dá baixa no estoque de um produto específico.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Perguntas do Combo',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _exibirDialogoAdicionarPergunta,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Adicionar Pergunta'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.2),
                  foregroundColor: Colors.blueAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_perguntasSelecao.length} pergunta(s) · ${_perguntasSelecao.fold<int>(0, (s, p) => s + p.opcoes.length)} opção(ões) · ${_perguntasSelecao.expand((p) => p.opcoes).where((o) => o.produtoId.isNotEmpty).map((o) => o.produtoId).toSet().length} produto(s) vinculado(s)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (_perguntasSelecao.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: const Text('Nenhuma pergunta cadastrada', style: TextStyle(color: Colors.white38)),
            )
          else
            ..._perguntasSelecao.asMap().entries.map((entry) {
              final idx = entry.key;
              final pergunta = entry.value;
              final dataService = Provider.of<DataService>(context, listen: false);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.help_outline, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pergunta.titulo,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_all_outlined, color: Colors.white38, size: 18),
                          onPressed: () {
                            setState(() {
                              _perguntasSelecao.insert(
                                idx + 1,
                                PerguntaSelecao(
                                  id: _uuid.v4(),
                                  titulo: pergunta.titulo,
                                  obrigatorio: pergunta.obrigatorio,
                                  minimo: pergunta.minimo,
                                  maximo: pergunta.maximo,
                                  opcoes: pergunta.opcoes
                                      .map((o) => OpcaoPerguntaSelecao(
                                            id: _uuid.v4(),
                                            produtoId: o.produtoId,
                                            nome: o.nome,
                                            precoAdicional: o.precoAdicional,
                                            quantidadeBaixa: o.quantidadeBaixa,
                                          ))
                                      .toList(),
                                ),
                              );
                            });
                          },
                          tooltip: 'Duplicar pergunta (com opções)',
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 18),
                          onPressed: () => _exibirDialogoAdicionarPergunta(perguntaEdicao: pergunta),
                          tooltip: 'Editar pergunta',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          onPressed: () {
                            setState(() {
                              _perguntasSelecao.removeAt(idx);
                            });
                          },
                          tooltip: 'Excluir pergunta',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chipBadge(
                          pergunta.obrigatorio ? Icons.verified_user_outlined : Icons.visibility_off_outlined,
                          pergunta.obrigatorio ? 'Obrigatória' : 'Opcional',
                          pergunta.obrigatorio ? const Color(0xFFFFB74D) : Colors.white54,
                        ),
                        _chipBadge(Icons.filter_alt_outlined, 'min ${pergunta.minimo} · máx ${pergunta.maximo}', Colors.blueAccent),
                        _chipBadge(Icons.list_alt_outlined, '${pergunta.opcoes.length} opção(ões)', Colors.greenAccent),
                      ],
                    ),
                    if (pergunta.opcoes.isEmpty ||
                        pergunta.opcoes.any((o) => o.produtoId.isEmpty) ||
                        pergunta.opcoes.length < pergunta.minimo) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                pergunta.opcoes.isEmpty
                                    ? 'Sem opções — adicione ao menos uma opção com produto para a baixa.'
                                    : (pergunta.opcoes.length < pergunta.minimo
                                        ? 'Mín. ${pergunta.minimo} opção(ões) mas só ${pergunta.opcoes.length} cadastrada(s) — impossível finalizar no PDV.'
                                        : 'Alguma(s) opção(ões) sem produto vinculado — a baixa não vai acontecer no PDV.'),
                                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (pergunta.opcoes.isEmpty)
                      const Text('Sem opções', style: TextStyle(color: Colors.white38, fontSize: 12))
                    else
                      ...pergunta.opcoes.map((opcao) {
                        final produtoOpcao = dataService.produtos.cast<Produto?>().firstWhere(
                          (p) => p?.id == opcao.produtoId,
                          orElse: () => null,
                        );
                        final nomeProduto = produtoOpcao?.nome ?? (opcao.nome.isEmpty ? 'Produto' : opcao.nome);
                        final semProdutoVinculado = produtoOpcao == null;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            semProdutoVinculado ? Icons.error_outline : Icons.check_circle_outline,
                            color: semProdutoVinculado ? Colors.redAccent : Colors.greenAccent,
                            size: 18,
                          ),
                          title: Text(opcao.nome.isEmpty ? nomeProduto : opcao.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          subtitle: semProdutoVinculado
                              ? const Text('Produto da baixa não encontrado', style: TextStyle(color: Colors.redAccent, fontSize: 11))
                              : Text(
                                  'Baixa: ${opcao.quantidadeBaixa.toStringAsFixed(opcao.quantidadeBaixa == opcao.quantidadeBaixa.roundToDouble() ? 0 : 2)} × $nomeProduto'
                                  '${opcao.precoAdicional > 0 ? ' · +R\$ ${opcao.precoAdicional.toStringAsFixed(2)}' : ''}',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 16),
                                onPressed: () => _exibirDialogoAdicionarOpcao(perguntaIdx: idx, opcaoEdicao: opcao),
                                tooltip: 'Editar opção',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _perguntasSelecao[idx] = PerguntaSelecao(
                                      id: pergunta.id,
                                      titulo: pergunta.titulo,
                                      obrigatorio: pergunta.obrigatorio,
                                      minimo: pergunta.minimo,
                                      maximo: pergunta.maximo,
                                      opcoes: pergunta.opcoes.where((o) => o.id != opcao.id).toList(),
                                    );
                                  });
                                },
                                tooltip: 'Excluir opção',
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _exibirDialogoAdicionarOpcao(perguntaIdx: idx),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Adicionar opção', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            _PreviewPopupCombo(
              perguntas: _perguntasSelecao,
              nomeProduto: widget.item is Produto ? (widget.item as Produto).nome : '',
            ),
        ]),
      ],
    );
  }

  /// Diálogo para adicionar/editar uma pergunta do combo
  void _exibirDialogoAdicionarPergunta({PerguntaSelecao? perguntaEdicao}) {
    final tituloController = TextEditingController(text: perguntaEdicao?.titulo ?? '');
    bool obrigatoria = perguntaEdicao?.obrigatorio ?? true;
    final minimoController = TextEditingController(text: (perguntaEdicao?.minimo ?? 1).toString());
    final maximoController = TextEditingController(text: (perguntaEdicao?.maximo ?? 1).toString());
    String erro = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text(perguntaEdicao != null ? 'Editar Pergunta' : 'Adicionar Pergunta', style: const TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Título da pergunta', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: tituloController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ex.: Escolha o sabor',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Este título aparece no PDV como pergunta para o operador/cliente.',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                    if (perguntaEdicao != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Esta pergunta já tem ${perguntaEdicao.opcoes.length} opção(ões) vinculada(s).',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 11),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Obrigatória?', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const Spacer(),
                        Switch(
                          value: obrigatoria,
                          activeColor: Colors.blueAccent,
                          onChanged: (v) => setDialogState(() => obrigatoria = v),
                        ),
                      ],
                    ),
                    const Text(
                      'Obrigatória: o PDV só finaliza se o cliente escolher. Opcional: pode deixar em branco.',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minimoController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Mínimo',
                              labelStyle: TextStyle(color: Colors.white38, fontSize: 12),
                              hintStyle: TextStyle(color: Colors.white24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maximoController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Máximo',
                              labelStyle: TextStyle(color: Colors.white38, fontSize: 12),
                              hintStyle: TextStyle(color: Colors.white24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Quantas opções podem ser escolhidas no PDV. Ex.: mínimo 1 e máximo 1 = escolha única; mínimo 1 e máximo 3 = escolha múltipla.',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                    if (erro.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(erro, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final titulo = tituloController.text.trim();
                    if (titulo.isEmpty) {
                      setDialogState(() => erro = 'Informe um título para a pergunta.');
                      return;
                    }
                    var minimo = int.tryParse(minimoController.text) ?? 1;
                    var maximo = int.tryParse(maximoController.text) ?? 1;
                    if (minimo < 1) minimo = 1;
                    if (maximo < minimo) maximo = minimo; // ajuste inteligente
                    setState(() {
                      final index = _perguntasSelecao.indexWhere((p) => p.id == perguntaEdicao?.id);
                      final novaPergunta = PerguntaSelecao(
                        id: perguntaEdicao?.id ?? _uuid.v4(),
                        titulo: titulo,
                        obrigatorio: obrigatoria,
                        minimo: minimo,
                        maximo: maximo,
                        opcoes: perguntaEdicao?.opcoes ?? [],
                      );
                      if (index >= 0) {
                        _perguntasSelecao[index] = novaPergunta;
                      } else {
                        _perguntasSelecao.add(novaPergunta);
                      }
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Diálogo para adicionar/editar uma opção dentro de uma pergunta
  void _exibirDialogoAdicionarOpcao({required int perguntaIdx, OpcaoPerguntaSelecao? opcaoEdicao}) {
    final nomeController = TextEditingController(text: opcaoEdicao?.nome ?? '');
    final qtdController = TextEditingController(text: (opcaoEdicao?.quantidadeBaixa ?? 1.0).toString());
    final precoController = TextEditingController(
        text: opcaoEdicao?.precoAdicional != null && opcaoEdicao!.precoAdicional > 0
            ? opcaoEdicao.precoAdicional.toStringAsFixed(2)
            : '');
    String? produtoSelecionadoId = opcaoEdicao?.produtoId;
    String? produtoSelecionadoNome;
    String erro = '';
    final dataService = Provider.of<DataService>(context, listen: false);
    if (produtoSelecionadoId != null && produtoSelecionadoId.isNotEmpty) {
      final p = dataService.produtos.cast<Produto?>().firstWhere(
            (prod) => prod?.id == produtoSelecionadoId,
            orElse: () => null,
          );
      produtoSelecionadoNome = p?.nome;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text(opcaoEdicao != null ? 'Editar Opção' : 'Adicionar Opção', style: const TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nome da opção (ex.: Morango)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nomeController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Se vazio, usa o nome do produto',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Produto que sofre a baixa no estoque', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final selecionado = await showDialog<Produto>(
                          context: context,
                          builder: (ctx) => _DialogoBuscarProduto(dataService: dataService),
                        );
                        if (selecionado != null) {
                          setDialogState(() {
                            produtoSelecionadoId = selecionado.id;
                            produtoSelecionadoNome = selecionado.nome;
                            // Inteligente: preenche o nome com o do produto se o campo estiver vazio
                            if (nomeController.text.trim().isEmpty) {
                              nomeController.text = selecionado.nome;
                            }
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: produtoSelecionadoNome != null ? Colors.blueAccent.withOpacity(0.4) : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.blueAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                produtoSelecionadoNome ?? 'Toque para buscar produto...',
                                style: TextStyle(
                                  color: produtoSelecionadoNome != null ? Colors.white : Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (produtoSelecionadoNome != null) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                                onPressed: () => setDialogState(() {
                                  produtoSelecionadoId = null;
                                  produtoSelecionadoNome = null;
                                }),
                                tooltip: 'Remover produto',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtdController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Qtd. de baixa',
                              labelStyle: TextStyle(color: Colors.white38, fontSize: 12),
                              hintText: '1.0',
                              hintStyle: TextStyle(color: Colors.white24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: precoController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Preço adicional (R\$)',
                              labelStyle: TextStyle(color: Colors.white38, fontSize: 12),
                              hintText: '0.00',
                              hintStyle: TextStyle(color: Colors.white24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Qtd. de baixa: quantas unidades do produto saem do estoque quando esta opção é escolhida.',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                    if (produtoSelecionadoNome != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_outlined, size: 14, color: Colors.greenAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _previewTextoBaixa(nomeController, qtdController, precoController, produtoSelecionadoNome!),
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (erro.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(erro, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (produtoSelecionadoId == null || produtoSelecionadoId!.isEmpty) {
                      setDialogState(() => erro = 'Selecione o produto que sofre a baixa no estoque.');
                      return;
                    }
                    final qtd = double.tryParse(qtdController.text.replaceAll(',', '.')) ?? 1.0;
                    if (qtd <= 0) {
                      setDialogState(() => erro = 'A quantidade de baixa deve ser maior que zero.');
                      return;
                    }
                    final preco = double.tryParse(precoController.text.replaceAll(',', '.')) ?? 0.0;
                    final nomeFinal = nomeController.text.trim().isEmpty
                        ? (produtoSelecionadoNome ?? 'Opção')
                        : nomeController.text.trim();
                    setState(() {
                      final pergunta = _perguntasSelecao[perguntaIdx];
                      final opcoes = List<OpcaoPerguntaSelecao>.from(pergunta.opcoes);
                      if (opcaoEdicao != null) {
                        final oIdx = opcoes.indexWhere((o) => o.id == opcaoEdicao.id);
                        if (oIdx >= 0) {
                          opcoes[oIdx] = OpcaoPerguntaSelecao(
                            id: opcaoEdicao.id,
                            produtoId: produtoSelecionadoId!,
                            nome: nomeFinal,
                            precoAdicional: preco,
                            quantidadeBaixa: qtd,
                          );
                        }
                      } else {
                        opcoes.add(OpcaoPerguntaSelecao(
                          id: _uuid.v4(),
                          produtoId: produtoSelecionadoId!,
                          nome: nomeFinal,
                          precoAdicional: preco,
                          quantidadeBaixa: qtd,
                        ));
                      }
                      _perguntasSelecao[perguntaIdx] = PerguntaSelecao(
                        id: pergunta.id,
                        titulo: pergunta.titulo,
                        obrigatorio: pergunta.obrigatorio,
                        minimo: pergunta.minimo,
                        maximo: pergunta.maximo,
                        opcoes: opcoes,
                      );
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _exibirDialogoAdicionarComposicao({ItemComposicao? itemEdicao}) {
    final pageContext = context;
    final dataService = Provider.of<DataService>(pageContext, listen: false);
    String? produtoSelecionadoId = itemEdicao?.produtoId;
    String? produtoSelecionadoNome;

    if (itemEdicao != null) {
      final pOrigem = dataService.produtos.cast<Produto?>().firstWhere(
        (p) => p?.id == itemEdicao.produtoId,
        orElse: () => null,
      );
      if (pOrigem != null) {
        produtoSelecionadoNome = pOrigem.nome;
      }
    }

    final qtdController = TextEditingController(
      text: itemEdicao != null ? itemEdicao.quantidade.toString() : '1',
    );
    final totalSacoController = TextEditingController(
      text: itemEdicao?.pesoTotalSaco != null ? itemEdicao!.pesoTotalSaco!.toString() : '',
    );
    final usoController = TextEditingController(
      text: itemEdicao?.fracaoBase != null ? itemEdicao!.fracaoBase!.toString() : '1',
    );
    // Unidades digitáveis livremente (autonomia total na baixa).
    // Padrão sensato: unidade do produto VENDIDO = unidade do próprio produto;
    // unidade BAIXADA = unidade do ingrediente selecionado (atualizada ao selecionar).
    String? unidadeVendaPadrao = (widget.item?.unidade ?? '').trim().isNotEmpty
        ? widget.item!.unidade
        : 'UN';
    String? unidadeBaixaPadrao = 'UN';
    if (produtoSelecionadoId != null) {
      final pSel = dataService.produtos.cast<Produto?>().firstWhere(
        (p) => p?.id == produtoSelecionadoId,
        orElse: () => null,
      );
      if (pSel != null) {
        unidadeBaixaPadrao = pSel.unidade.trim().isNotEmpty ? pSel.unidade : 'UN';
      }
    }
    final unidadeVendaCtrl = TextEditingController(
      text: (itemEdicao?.unidadeVenda ?? '').trim().isNotEmpty
          ? itemEdicao!.unidadeVenda!
          : unidadeVendaPadrao!,
    );
    final unidadeBaixaCtrl = TextEditingController(
      text: (itemEdicao?.unidadeBaixa ?? '').trim().isNotEmpty
          ? itemEdicao!.unidadeBaixa!
          : unidadeBaixaPadrao!,
    );
    // true  = vender fracionado com conversão (ex.: 1000 ml → baixa 1 litro)
    // false = fluxo comum (vende 15 unidades → baixa 15 unidades)
    bool modoConversao = itemEdicao?.pesoTotalSaco != null;
    String erro = '';

    // Valor do modo direto para restaurar ao alternar de volta (nao apaga baixa fracionaria legitima)
    String? valorDiretoSalvo;
    if (itemEdicao == null || itemEdicao.pesoTotalSaco == null) {
      valorDiretoSalvo = qtdController.text;
    }

    void recalcularQtd() {
      final total = double.tryParse(totalSacoController.text.trim().replaceAll(',', '.')) ?? 0.0;
      final uso = double.tryParse(usoController.text.trim().replaceAll(',', '.')) ?? 0.0;
      if (total > 0 && uso > 0) {
        qtdController.text = (uso / total).toStringAsFixed(6);
      }
    }

    String exemploConversao() {
      final total = double.tryParse(totalSacoController.text.trim().replaceAll(',', '.')) ?? 0.0;
      final usoVal = double.tryParse(usoController.text.trim().replaceAll(',', '.'));
      if (total <= 0) return 'Informe "Ao vender quantos?" para ver o exemplo.';
      final u = (usoVal == null || usoVal <= 0) ? 1.0 : usoVal;
      String fmt(double v) =>
          v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
      final p1 = total / 2;
      final p2 = total;
      final p3 = total * 2;
      final unV = rotuloUnidade(unidadeVendaCtrl.text.isEmpty ? 'UN' : unidadeVendaCtrl.text);
      final unB = rotuloUnidade(unidadeBaixaCtrl.text.isEmpty ? 'UN' : unidadeBaixaCtrl.text);
      final v1 = (u / total * p1);
      final v2 = (u / total * p2);
      final v3 = (u / total * p3);
      return 'Exemplo: vender ${fmt(p1)} $unV → baixa ${fmt(v1)} $unB  ·  '
          'vender ${fmt(p2)} $unV → baixa ${fmt(v2)} $unB  ·  '
          'vender ${fmt(p3)} $unV → baixa ${fmt(v3)} $unB';
    }

    showDialog(
      context: pageContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget modoCard({
              required bool selecionado,
              required IconData icone,
              required Color cor,
              required String titulo,
              required String descricao,
              required VoidCallback onTap,
              Widget? extra,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selecionado ? cor.withOpacity(0.08) : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selecionado ? cor.withOpacity(0.6) : Colors.white12,
                          width: selecionado ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selecionado ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18,
                            color: selecionado ? cor : Colors.white30,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  descricao,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          Icon(icone, size: 16, color: cor.withOpacity(0.7)),
                        ],
                      ),
                    ),
                  ),
                  if (selecionado && extra != null) ...[
                    const SizedBox(height: 8),
                    extra,
                  ],
                ],
              );
            }

            final campoDireto = TextField(
              controller: qtdController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setDialogState(() => erro = ''),
              decoration: InputDecoration(
                labelText: 'Qtd. de baixa por unidade vendida',
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                hintText: '1.0',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            );

            // Campo de unidade digitável livremente (autonomia total na baixa).
            // O operador escreve qualquer unidade (ml, litro, cm, metro, saco, caixa...)
            // ou toca num preset abaixo.
            Widget campoUnidade(TextEditingController ctrl, String label, String hint) {
              return TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                  hintText: hint,
                  hintStyle: const TextStyle(color: Colors.white24),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => setDialogState(() {
                  recalcularQtd();
                  erro = '';
                }),
              );
            }

            // Presets de um toque: preenchem os campos e o exemplo
            void aplicarPreset(String vendaQtd, String vendaUn, String baixaQtd, String baixaUn) {
              totalSacoController.text = vendaQtd;
              unidadeVendaCtrl.text = vendaUn;
              usoController.text = baixaQtd;
              unidadeBaixaCtrl.text = baixaUn;
              setDialogState(() {
                recalcularQtd();
                erro = '';
              });
            }

            final presets = [
              (label: '1000 ml → 1 litro', v: '1000', vu: 'ml', b: '1', bu: 'litro'),
              (label: '100 cm → 1 metro', v: '100', vu: 'cm', b: '1', bu: 'metro'),
              (label: '1000 g → 1 kg', v: '1000', vu: 'g', b: '1', bu: 'kg'),
              (label: '15 kg → 1 saco', v: '15', vu: 'kg', b: '1', bu: 'saco'),
              (label: '1 un → 1 un', v: '1', vu: 'un', b: '1', bu: 'un'),
            ];

            final campoConversao = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Quando vender...',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: totalSacoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Ao vender quantos?',
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                          hintText: 'Ex.: 1000',
                          hintStyle: const TextStyle(color: Colors.white24),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setDialogState(() {
                          recalcularQtd();
                          erro = '';
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: campoUnidade(unidadeVendaCtrl, 'Unidade', 'ml, cm, kg...'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '...baixar do estoque:',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: usoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Baixa de quanto?',
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                          hintText: 'Ex.: 1',
                          hintStyle: const TextStyle(color: Colors.white24),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setDialogState(() {
                          recalcularQtd();
                          erro = '';
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: campoUnidade(unidadeBaixaCtrl, 'Unidade', 'litro, saco, m...'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '⚡ Toque num exemplo para preencher:',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: presets
                      .map((p) => ActionChip(
                            label: Text(p.label, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                            backgroundColor: Colors.amber.withOpacity(0.12),
                            side: BorderSide(color: Colors.amber.withOpacity(0.35)),
                            onPressed: () => aplicarPreset(p.v, p.vu, p.b, p.bu),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.25)),
                  ),
                  child: Text(
                    exemploConversao(),
                    style: const TextStyle(color: Colors.amber, fontSize: 10.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '💡 A baixa é proporcional: vende 500 ml → baixa 0,5 litro (metade). '
                  'No PDV o operador pode alternar para "baixa direta" em cada venda, sem mudar este cadastro.',
                  style: TextStyle(color: Colors.white30, fontSize: 9.5, height: 1.35),
                ),
              ],
            );

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text(
                itemEdicao != null ? 'Editar Ingrediente' : 'Adicionar Ingrediente',
                style: const TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchAnchor(
                      builder: (BuildContext context, SearchController controller) {
                        return SearchBar(
                          controller: controller,
                          hintText: 'Buscar Produto/Matéria-prima',
                          hintStyle: MaterialStateProperty.all(const TextStyle(color: Colors.white38, fontSize: 13)),
                          textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.white, fontSize: 13)),
                          backgroundColor: MaterialStateProperty.all(Colors.white.withOpacity(0.05)),
                          padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
                          leading: const Icon(Icons.search, color: Colors.blueAccent),
                          onTap: () {
                            controller.openView();
                          },
                          onChanged: (_) {
                            controller.openView();
                          },
                        );
                      },
                      suggestionsBuilder: (BuildContext context, SearchController controller) {
                        final String query = controller.text.toLowerCase();
                        if (query.trim().isEmpty) {
                          return [
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text(
                                  'Digite algo para buscar...',
                                  style: TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ),
                            )
                          ];
                        }

                        final filtrados = dataService.produtos.where((p) {
                          if (p.id == widget.item?.id) return false;
                          return p.nome.toLowerCase().contains(query) ||
                              (p.codigo ?? '').toLowerCase().contains(query);
                        }).take(15).toList();

                        if (filtrados.isEmpty) {
                          return [
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text(
                                  'Nenhum produto encontrado.',
                                  style: TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ),
                            )
                          ];
                        }

                        return filtrados.map((p) {
                          return ListTile(
                            title: Text(p.nome, style: const TextStyle(color: Colors.white)),
                            subtitle: p.codigo != null
                                ? Text('Código: ${p.codigo}', style: const TextStyle(color: Colors.white30, fontSize: 10))
                                : null,
                            onTap: () {
                              setDialogState(() {
                                // Ao selecionar o ingrediente, se a unidade baixada ainda não
                                // foi editada pelo usuário (vazio ou ainda no default 'UN'),
                                // preenche com a unidade do ingrediente.
                                final unBx = unidadeBaixaCtrl.text.trim().toLowerCase();
                                if ((itemEdicao == null || (itemEdicao.unidadeBaixa ?? '').trim().isEmpty) &&
                                    (unBx.isEmpty || unBx == 'un')) {
                                  final pIng = p.unidade.trim();
                                  if (pIng.isNotEmpty) {
                                    unidadeBaixaCtrl.text = pIng;
                                  }
                                }
                                produtoSelecionadoId = p.id;
                                produtoSelecionadoNome = p.nome;
                              });
                              controller.closeView(p.nome);
                            },
                          );
                        }).toList();
                      },
                    ),
                    if (produtoSelecionadoNome != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.layers, size: 16, color: Colors.blueAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selecionado: $produtoSelecionadoNome',
                                style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      '⚖️ Como deve ser a baixa no estoque?',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Escolha como este ingrediente sai do estoque quando o produto é vendido.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    modoCard(
                      selecionado: !modoConversao,
                      icone: Icons.speed,
                      cor: Colors.blueAccent,
                      titulo: 'Fluxo comum — baixa direta',
                      descricao: 'Vende 15 unidades → baixa 15 unidades. Simples, sem conversão.',
                      onTap: () => setDialogState(() {
                        modoConversao = false;
                        if (valorDiretoSalvo != null) {
                          qtdController.text = valorDiretoSalvo!;
                        } else {
                          final q = double.tryParse(qtdController.text.trim().replaceAll(',', '.'));
                          if (q == null || q <= 0) {
                            qtdController.text = '1';
                          }
                        }
                        erro = '';
                      }),
                      extra: campoDireto,
                    ),
                    const SizedBox(height: 10),
                    modoCard(
                      selecionado: modoConversao,
                      icone: Icons.scale_outlined,
                      cor: Colors.amber,
                      titulo: 'Vender fracionado — conversão (ml, kg, metro...)',
                      descricao: 'Ex.: vende 1000 ml de chopp → baixa 1 litro no barril. Funciona com kg, ml, metro, unidade e mais.',
                      onTap: () => setDialogState(() {
                        modoConversao = true;
                        valorDiretoSalvo = qtdController.text.trim().isEmpty ? '1' : qtdController.text;
                        if (totalSacoController.text.trim().isEmpty) {
                          totalSacoController.text = '1000';
                          if (usoController.text.trim().isEmpty) {
                            usoController.text = '1';
                          }
                        }
                        recalcularQtd();
                        erro = '';
                      }),
                      extra: campoConversao,
                    ),
                    if (erro.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(erro, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (produtoSelecionadoId == null || produtoSelecionadoId!.isEmpty) {
                      setDialogState(() => erro = 'Selecione o produto/matéria-prima que sofre a baixa no estoque.');
                      return;
                    }
                    double qtd;
                    double? pesoTotalSaco;
                    double? fracaoBase;
                    if (modoConversao) {
                      final total = double.tryParse(totalSacoController.text.trim().replaceAll(',', '.'));
                      if (total == null || total <= 0) {
                        setDialogState(() => erro = 'Informe "A cada quantos vendidos?" (ex.: 15) para a conversão.');
                        return;
                      }
                      final usoVal = double.tryParse(usoController.text.trim().replaceAll(',', '.'));
                      final u = (usoVal == null || usoVal <= 0) ? 1.0 : usoVal;
                      pesoTotalSaco = total;
                      fracaoBase = u;
                      qtd = u / total;
                    } else {
                      final qtdParsed = double.tryParse(qtdController.text.trim().replaceAll(',', '.'));
                      if (qtdParsed == null || qtdParsed <= 0) {
                        setDialogState(() => erro = 'A quantidade de baixa deve ser maior que zero.');
                        return;
                      }
                      qtd = qtdParsed;
                      pesoTotalSaco = null;
                      fracaoBase = null;
                    }

                    setState(() {
                      if (itemEdicao != null) {
                        // Se o produto selecionado mudou durante a edicao, removemos o ID antigo
                        if (itemEdicao.produtoId != produtoSelecionadoId) {
                          _composicao.removeWhere((c) => c.produtoId == itemEdicao.produtoId);
                        }
                      }

                      // Verifica se já existe o novo produto selecionado na lista, se sim atualiza, senao adiciona
                      final idx = _composicao.indexWhere((c) => c.produtoId == produtoSelecionadoId);
                      final novoItem = ItemComposicao(
                        produtoId: produtoSelecionadoId!,
                        quantidade: qtd,
                        pesoTotalSaco: pesoTotalSaco,
                        fracaoBase: fracaoBase,
                        unidadeVenda: modoConversao
                            ? (unidadeVendaCtrl.text.trim().isEmpty ? null : unidadeVendaCtrl.text.trim())
                            : null,
                        unidadeBaixa: modoConversao
                            ? (unidadeBaixaCtrl.text.trim().isEmpty ? null : unidadeBaixaCtrl.text.trim())
                            : null,
                      );
                      if (idx >= 0) {
                        _composicao[idx] = novoItem;
                      } else {
                        _composicao.add(novoItem);
                      }
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: Text(itemEdicao != null ? 'SALVAR' : 'ADICIONAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  /// Diálogo para montar um combo SEM perguntas: seleciona vários produtos
  /// (com quantidade) e monta o kit na hora. O produto vira composto com
  /// baixa automática em todos os itens e 1 item só no carrinho do PDV.
  void _exibirDialogoCriarCombo() {
    final pageContext = context;
    final dataService = Provider.of<DataService>(pageContext, listen: false);
    final buscaController = TextEditingController();
    final qtdControllers = <String, TextEditingController>{};
    final selecionados = <String, double>{};
    // Itens já no kit (modo simples, sem conversão) vêm pré-marcados
    final idsKitInicial = <String>{};
    for (final c in _composicao) {
      if (c.pesoTotalSaco == null) {
        selecionados[c.produtoId] = c.quantidade;
        idsKitInicial.add(c.produtoId);
      }
    }
    String busca = '';

    showDialog(
      context: pageContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final lista = dataService.produtos.where((p) {
              if (p.id == widget.item?.id) return false;
              if (p.ehComposto) return false;
              final q = busca.trim().toLowerCase();
              if (q.isEmpty) return true;
              return p.nome.toLowerCase().contains(q) ||
                  (p.codigo ?? '').toLowerCase().contains(q);
            }).toList();

            double somaItens = 0;
            for (final p in lista) {
              final q = selecionados[p.id];
              if (q != null && q > 0) {
                somaItens += p.precoAtual * q;
              }
            }

            Widget stepper(Produto p) {
              final ctrl = qtdControllers.putIfAbsent(p.id, () {
                final q = selecionados[p.id] ?? 1.0;
                final txt = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
                return TextEditingController(text: txt);
              });
              void definirQtd(double v) {
                setDialogState(() {
                  if (v <= 0) {
                    selecionados.remove(p.id);
                    ctrl.text = '';
                  } else {
                    selecionados[p.id] = v;
                    ctrl.text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
                  }
                });
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => definirQtd((selecionados[p.id] ?? 1.0) - 1),
                    ),
                    SizedBox(
                      width: 42,
                      child: TextField(
                        controller: ctrl,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                          setDialogState(() {
                            if (parsed != null && parsed > 0) {
                              selecionados[p.id] = parsed;
                            } else if (v.trim().isEmpty) {
                              selecionados.remove(p.id);
                            }
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => definirQtd((selecionados[p.id] ?? 1.0) + 1),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Row(
                children: [
                  Icon(Icons.fastfood_rounded, color: Colors.tealAccent, size: 22),
                  SizedBox(width: 8),
                  Text('Criar Combo', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 460,
                height: 430,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Selecione os itens do kit e a quantidade de cada um. Na venda entra 1 item '
                      'no carrinho e a baixa acontece em todos os itens.',
                      style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: buscaController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar produto...',
                        hintStyle: const TextStyle(color: Colors.white24),
                        prefixIcon: const Icon(Icons.search, color: Colors.tealAccent, size: 20),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => busca = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(
                              child: Text('Nenhum produto encontrado.', style: TextStyle(color: Colors.white38)),
                            )
                          : ListView.separated(
                              itemCount: lista.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (context, index) {
                                final p = lista[index];
                                final selecionado = selecionados.containsKey(p.id);
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Checkbox(
                                    value: selecionado,
                                    activeColor: Colors.tealAccent,
                                    onChanged: (v) => setDialogState(() {
                                      if (v == true) {
                                        selecionados[p.id] = 1.0;
                                        qtdControllers.remove(p.id);
                                      } else {
                                        selecionados.remove(p.id);
                                        qtdControllers.remove(p.id);
                                      }
                                    }),
                                  ),
                                  title: Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                                  subtitle: Text(
                                    'R\$ ${p.precoAtual.toStringAsFixed(2)}${p.codigo != null ? ' · ${p.codigo}' : ''}',
                                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                                  ),
                                  trailing: selecionado ? stepper(p) : null,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧮 Soma dos itens (referência): R\$ ${somaItens.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'O preço de venda do combo é o preço deste produto (definido nos dados do produto). '
                            'Dica: coloque um valor abaixo da soma dos itens.',
                            style: TextStyle(color: Colors.white30, fontSize: 9.5, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: (selecionados.isEmpty && idsKitInicial.isEmpty)
                      ? null
                      : () {
                          setState(() {
                            _ehComposto = true;
                            _exibirComposicaoPdv = true;
                            final idsKitFinal = <String>{};
                            for (final e in selecionados.entries) {
                              if (e.value > 0) {
                                idsKitFinal.add(e.key);
                                final idx = _composicao.indexWhere((c) => c.produtoId == e.key);
                                // Ingrediente com conversao configurada nao e sobrescrito
                                if (idx >= 0 && _composicao[idx].pesoTotalSaco != null) continue;
                                final novoItem = ItemComposicao(produtoId: e.key, quantidade: e.value);
                                if (idx >= 0) {
                                  _composicao[idx] = novoItem;
                                } else {
                                  _composicao.add(novoItem);
                                }
                              }
                            }
                            // Remove só itens do kit simples que foram desmarcados
                            // (itens com conversão configurada não são tocados)
                            _composicao.removeWhere(
                              (c) => idsKitInicial.contains(c.produtoId) && !idsKitFinal.contains(c.produtoId),
                            );
                          });
                          final nItens = selecionados.length;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.tealAccent,
                              content: Text(
                                nItens > 0
                                    ? 'Kit montado com $nItens ${nItens == 1 ? 'item' : 'itens'} — salve o produto para aplicar.'
                                    : 'Kit limpo.',
                                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black87),
                  child: Text(
                    selecionados.isEmpty ? 'LIMPAR KIT' : 'MONTAR COMBO (${selecionados.length})',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  Widget _buildAbaAdicionais() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gerenciar Adicionais',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Configure acompanhamentos extras para este produto',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _exibirDialogoImportarAdicionais,
                  icon: const Icon(Icons.download_rounded, size: 18, color: Colors.cyanAccent),
                  label: const Text('IMPORTAR'),
                  style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _exibirDialogoAdicional,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('ADICIONAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    foregroundColor: Colors.blueAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.blueAccent, width: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_adicionais.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.add_task_rounded, size: 48, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhum adicional cadastrado',
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adicionais.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final adicional = _adicionais[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.playlist_add_rounded, color: Colors.blueAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            adicional.nome,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Preço: R\$ ${adicional.preco.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: adicional.ativo,
                      onChanged: (value) {
                        setState(() {
                          _adicionais[index] = adicional.copyWith(ativo: value);
                        });
                      },
                      activeColor: Colors.blueAccent,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => _exibirDialogoAdicional(index: index),
                      icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _adicionais.removeAt(index);
                        });
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  void _exibirDialogoAdicional({int? index}) {
    final nomeController = TextEditingController(text: index != null ? _adicionais[index].nome : '');
    final precoController = TextEditingController(text: index != null ? _adicionais[index].preco.toString() : '0.00');
    final formKey = GlobalKey<FormState>();
    bool salvarComoModelo = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            index == null ? 'Novo Adicional' : 'Editar Adicional',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nomeController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nome do Adicional',
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: 'Ex: Leite Ninho',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: precoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Preço Adicional (R\$)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.greenAccent),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o preço';
                    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                    return null;
                  },
                ),
                if (index == null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                    ),
                    child: CheckboxListTile(
                      title: const Text(
                        'Deseja que outros produtos usem esse adicional?', 
                        style: TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)
                      ),
                      subtitle: const Text(
                        'Isso salvará este item como um modelo global para reutilização.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      value: salvarComoModelo,
                      onChanged: (val) => setDialogState(() => salvarComoModelo = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.blueAccent,
                      dense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final novoAdicional = AdicionalProduto(
                    id: index != null ? _adicionais[index].id : _uuid.v4(),
                    nome: nomeController.text.trim(),
                    preco: double.parse(precoController.text.replaceAll(',', '.')),
                    ativo: index != null ? _adicionais[index].ativo : true,
                  );
                  
                  setState(() {
                    if (index != null) {
                      _adicionais[index] = novoAdicional;
                    } else {
                      _adicionais.add(novoAdicional);
                    }
                  });

                  // Salvar como modelo global se solicitado
                  if (salvarComoModelo) {
                    final dataService = Provider.of<DataService>(context, listen: false);
                    final empresa = dataService.empresaAtual;
                    if (empresa != null) {
                      // Evitar duplicados pelo nome no global
                      if (!empresa.modelosAdicionais.any((m) => m.nome.toLowerCase() == novoAdicional.nome.toLowerCase())) {
                        debugPrint('>>> [CENTRALIZAR] Salvando novo modelo global: ${novoAdicional.nome}');
                        final novosModelos = List<AdicionalProduto>.from(empresa.modelosAdicionais)..add(novoAdicional);
                        debugPrint('>>> [CENTRALIZAR] Total de modelos agora: ${novosModelos.length}');
                        
                        final authService = Provider.of<AuthService>(context, listen: false);
                        authService.atualizarEmpresa(empresa.copyWith(
                          modelosAdicionais: novosModelos,
                          updatedAt: DateTime.now(),
                        ));

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Adicional salvo na biblioteca global!'),
                            backgroundColor: Colors.blueAccent,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } else {
                        debugPrint('>>> [CENTRALIZAR] Modelo ${novoAdicional.nome} já existe no global.');
                      }
                    }
                  }

                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('SALVAR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _exibirDialogoImportarAdicionais() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    final modelos = empresa?.modelosAdicionais ?? [];
    
    debugPrint('>>> [IMPORT] Abrindo diálogo. Modelos globais encontrados: ${modelos.length}');
    for (var m in modelos) debugPrint('>>> [IMPORT] Modelo disponível: ${m.nome}');

    if (modelos.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Biblioteca Vazia', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Você ainda não salvou nenhum adicional como modelo global.', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Text('Dica: Ao criar um adicional comum, marque "Deseja que outros produtos usem esse adicional?" para salvá-lo aqui.', 
                style: TextStyle(color: Colors.blueAccent.withOpacity(0.7), fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ENTENDIDO', style: TextStyle(color: Colors.blueAccent))),
          ],
        ),
      );
      return;
    }

    List<AdicionalProduto> selecionados = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Importar Modelos', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: modelos.map((modelo) {
                  final estaSelecionado = selecionados.contains(modelo);
                  return CheckboxListTile(
                    title: Text(modelo.nome, style: const TextStyle(color: Colors.white)),
                    subtitle: Text('R\$ ${modelo.preco.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent)),
                    value: estaSelecionado,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          selecionados.add(modelo);
                        } else {
                          selecionados.remove(modelo);
                        }
                      });
                    },
                    activeColor: Colors.blueAccent,
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: selecionados.isEmpty ? null : () {
                setState(() {
                  for (var s in selecionados) {
                    if (!_adicionais.any((a) => a.nome.toLowerCase() == s.nome.toLowerCase())) {
                       _adicionais.add(s.copyWith(id: _uuid.v4()));
                    }
                  }
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
              child: Text('IMPORTAR (${selecionados.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget customizado para autocomplete de grupos com ability de criar novo
class _CampoGrupoAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onChanged;

  const _CampoGrupoAutocomplete({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_CampoGrupoAutocomplete> createState() =>
      _CampoGrupoAutocompleteState();
}

class _CampoGrupoAutocompleteState extends State<_CampoGrupoAutocomplete> {
  late FocusNode _focusNode;
  List<String> _sugestoes = [];
  bool _mostrarSugestoes = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _atualizarSugestoes(widget.controller.text);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _atualizarSugestoes(String query) {
    final gruposManager = GruposManager();
    setState(() {
      _sugestoes = gruposManager.obterSugestoes(query);
      _mostrarSugestoes = query.isNotEmpty && _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Grupo/Categoria',
            prefixIcon: const Icon(Icons.category),
            hintText: 'Ex: Periféricos, Hardware, Serviços',
            suffixIcon: _sugestoes.isNotEmpty && _mostrarSugestoes
                ? const Icon(Icons.arrow_drop_down)
                : null,
            helperText: 'Digite para buscar ou criar novo grupo',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Informe o grupo';
            }
            return null;
          },
          onChanged: (value) {
            widget.onChanged(value);
            _atualizarSugestoes(value);
          },
          onTap: () {
            _atualizarSugestoes(widget.controller.text);
          },
          textInputAction: TextInputAction.next,
        ),
        // Lista de sugestões
        if (_mostrarSugestoes && _sugestoes.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _sugestoes.length,
              itemBuilder: (context, index) {
                final sugestao = _sugestoes[index];
                return ListTile(
                  leading: const Icon(Icons.label),
                  title: Text(sugestao),
                  onTap: () {
                    widget.controller.text = sugestao;
                    widget.onChanged(sugestao);
                    _focusNode.unfocus();
                    setState(() => _mostrarSugestoes = false);
                  },
                );
              },
            ),
          ),
        // Botão para criar novo grupo
        if (widget.controller.text.isNotEmpty &&
            !_sugestoes.contains(widget.controller.text) &&
            _focusNode.hasFocus)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text('➕ Criar grupo "${widget.controller.text}"'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () {
                final novoGrupo = widget.controller.text.trim();
                if (novoGrupo.isNotEmpty) {
                  final gruposManager = GruposManager();
                  gruposManager.adicionarGrupo(novoGrupo);
                  _atualizarSugestoes(novoGrupo);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Grupo "$novoGrupo" criado!'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
      ],
    );
  }

}

class _CustomAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final List<String> sugestoes;
  final Function(String)? onChanged;

  const _CustomAutocompleteField({
    required this.controller,
    required this.hint,
    required this.sugestoes,
    this.onChanged,
  });

  @override
  State<_CustomAutocompleteField> createState() => _CustomAutocompleteFieldState();
}

class _CustomAutocompleteFieldState extends State<_CustomAutocompleteField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focusNode,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return widget.sugestoes;
          }
          return widget.sugestoes.where((String option) {
            return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
          });
        },
        onSelected: (String selection) {
          widget.controller.text = selection;
          if (widget.onChanged != null) widget.onChanged!(selection);
          setState(() {});
        },
        fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
            FocusNode focusNode, VoidCallback onFieldSubmitted) {
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
            ),
            onChanged: (v) {
              if (widget.onChanged != null) widget.onChanged!(v);
              setState(() {});
            },
          );
        },
        optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected,
            Iterable<String> options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: const Color(0xFF1E293B),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: SizedBox(
                width: constraints.biggest.width,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String option = options.elementAt(index);
                    return ListTile(
                      title: Text(option, style: const TextStyle(color: Colors.white70)),
                      onTap: () {
                        onSelected(option);
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


/// Diálogo de busca de produto para vincular a uma opção de combo
/// Prévia interativa do popup de combo que aparece no PDV — permite testar a configuração
class _PreviewPopupCombo extends StatefulWidget {
  final List<PerguntaSelecao> perguntas;
  final String nomeProduto;

  const _PreviewPopupCombo({required this.perguntas, required this.nomeProduto});

  @override
  State<_PreviewPopupCombo> createState() => _PreviewPopupComboState();
}

class _PreviewPopupComboState extends State<_PreviewPopupCombo> {
  final Map<String, List<OpcaoPerguntaSelecao>> _selecoes = {};

  /// Seleções atuais da pergunta, filtrando opções que não existem mais (comparação por id)
  List<OpcaoPerguntaSelecao> _selDa(PerguntaSelecao pergunta) =>
      (_selecoes[pergunta.id] ?? const [])
          .where((o) => pergunta.opcoes.any((p) => p.id == o.id))
          .toList();

  bool _estaSelecionada(PerguntaSelecao pergunta, OpcaoPerguntaSelecao opcao) =>
      _selDa(pergunta).any((o) => o.id == opcao.id);

  void _toggle(PerguntaSelecao pergunta, OpcaoPerguntaSelecao opcao) {
    setState(() {
      final atuais = _selDa(pergunta);
      final jaSelecionada = atuais.any((o) => o.id == opcao.id);
      final selecionados = atuais.where((o) => o.id != opcao.id).toList();
      if (!jaSelecionada) {
        if (pergunta.maximo == 1) {
          selecionados.clear();
          selecionados.add(opcao);
        } else if (selecionados.length < pergunta.maximo) {
          selecionados.add(opcao);
        }
      }
      _selecoes[pergunta.id] = selecionados;
    });
  }

  bool _podeConfirmar() {
    for (final p in widget.perguntas) {
      final n = _selDa(p).length;
      if (p.obrigatorio && n < p.minimo) return false;
      if (n > p.maximo) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    // Remove seleções de perguntas que foram excluídas do formulário
    _selecoes.removeWhere((k, _) => !widget.perguntas.any((p) => p.id == k));
    for (final p in widget.perguntas) {
      _selecoes.putIfAbsent(p.id, () => []);
    }
    final todasSelecionadas = widget.perguntas.expand((p) => _selDa(p)).toList();
    final totalAdicional = todasSelecionadas.fold<double>(0, (s, o) => s + o.precoAdicional);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text('Prévia no PDV', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white38),
                onPressed: () => setState(() => _selecoes.clear()),
                tooltip: 'Limpar seleção',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Teste aqui como o popup vai aparecer na hora da venda.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 10),
          if (widget.perguntas.isEmpty)
            const Text('Adicione perguntas para ver a prévia.', style: TextStyle(color: Colors.white24, fontSize: 11))
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.nomeProduto.isEmpty ? 'Nome do Produto' : widget.nomeProduto,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            ...widget.perguntas.map((pergunta) {
              final selecionados = _selDa(pergunta);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pergunta.titulo,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pergunta.obrigatorio ? 'Obrigatório' : 'Opcional'} · de ${pergunta.minimo} a ${pergunta.maximo} (${selecionados.length} selecionada(s))',
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                    const SizedBox(height: 6),
                    ...pergunta.opcoes.map((opcao) {
                      final sel = _estaSelecionada(pergunta, opcao);
                      return InkWell(
                        onTap: () => _toggle(pergunta, opcao),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? Colors.blueAccent.withOpacity(0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? Colors.blueAccent : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                pergunta.maximo == 1
                                    ? (sel ? Icons.radio_button_checked : Icons.radio_button_off)
                                    : (sel ? Icons.check_box : Icons.check_box_outline_blank),
                                size: 16,
                                color: sel ? Colors.blueAccent : Colors.white30,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  opcao.nome.isEmpty
                                      ? (dataService.produtos.cast<Produto?>().firstWhere((p) => p?.id == opcao.produtoId, orElse: () => null)?.nome ?? 'Opção')
                                      : opcao.nome,
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                              if (opcao.precoAdicional > 0)
                                Text(
                                  '+R\$ ${opcao.precoAdicional.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
              ),
              child: Text(
                todasSelecionadas.isEmpty
                    ? 'Nada selecionado ainda.'
                    : '${todasSelecionadas.length} item(ns) selecionado(s) · +R\$ ${totalAdicional.toStringAsFixed(2)} em adicionais',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _podeConfirmar() ? () {} : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  disabledBackgroundColor: Colors.white10,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  _podeConfirmar() ? 'Confirmar (prévia válida)' : 'Complete as seleções obrigatórias',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DialogoBuscarProduto extends StatefulWidget {
  final DataService dataService;
  const _DialogoBuscarProduto({required this.dataService});

  @override
  State<_DialogoBuscarProduto> createState() => _DialogoBuscarProdutoState();
}

class _DialogoBuscarProdutoState extends State<_DialogoBuscarProduto> {
  final TextEditingController _busca = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = _query.trim().isEmpty
        ? widget.dataService.produtos.take(20).toList()
        : widget.dataService.produtos.where((p) {
            return p.nome.toLowerCase().contains(_query.toLowerCase()) ||
                (p.codigo ?? '').toLowerCase().contains(_query.toLowerCase());
          }).take(20).toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text('Buscar Produto', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Digite o nome ou código...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtrados.length,
                itemBuilder: (context, index) {
                  final p = filtrados[index];
                  return ListTile(
                    dense: true,
                    title: Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: p.codigo != null
                        ? Text('Código: ${p.codigo} · Estoque: ${p.estoque}', style: const TextStyle(color: Colors.white38, fontSize: 11))
                        : Text('Estoque: ${p.estoque}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }
}

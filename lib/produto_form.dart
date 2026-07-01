import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/codigo_service.dart';
import 'package:sistema_exodo_novo/services/grupos_manager.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/produto_historico.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/services/image_storage_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/item_composicao.dart';
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
  final _precoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _precoPromocionalController = TextEditingController();
  final _fornecedorNomeController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  final _observacaoPadraoController = TextEditingController();
  
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
  late String _nome;
  late String _descricao;
  late String _unidade;
  late String _grupo;
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
  bool _enviaBalanca = false;
  List<String> _codigosFornecedor = [];
  
  // Campos para Adicionais
  List<AdicionalProduto> _adicionais = [];
  bool _temAdicionais = false;
  final _uuid = const Uuid();
  
  // Campos para Composição
  bool _ehComposto = false;
  List<ItemComposicao> _composicao = [];
  
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
      _preco = widget.item?.preco ?? 0.0;
      _precoCusto = widget.item?.precoCusto;
      _estoque = widget.item?.estoque ?? 0.0;
      _codigoController.text = _codigo;
      _codigoBarrasController.text = _codigoBarras;
      _descricaoController.text = _descricao;
      _unidadeController.text = _unidade;
      _grupoController.text = _grupo;
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
      
      // Carregar campos de preparação
      _paraCozinha = widget.item?.paraCozinha ?? false;
      _paraBar = widget.item?.paraBar ?? false;
      _enviaBalanca = widget.item?.enviaBalanca ?? false;
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
      _composicao = widget.item is Produto 
          ? List<ItemComposicao>.from((widget.item as Produto).composicao)
          : [];
    } else {
      // Novo produto
      _nome = '';
      _descricao = '';
      _unidade = '';
      _preco = 0.0;
      _precoCusto = null;
      _estoque = 0.0;
      _codigoBarras = '';
      _grupo = 'Sem Grupo';
      _codigoEditavel = true; // Código é editável para novos produtos
      _temPromocao = false;
      _precoPromocional = null;
      _promocaoInicio = null;
      _promocaoFim = null;
      
      // Inicializar campos de impostos
      _ncm = '22011000';
      _icmsAliquota = null;
      _icmsCst = '500';
      _ipiAliquota = null;
      _ipiCst = null;
      _pisAliquota = null;
      _pisCst = null;
      _cofinsAliquota = null;
      _cofinsCst = null;
      _issAliquota = null;
      _origem = null;
      _cfop = '5405';
      _cest = null;
      _csosn = '500';
      _simplesNacionalAliquota = null;
      _paraCozinha = false;
      _paraBar = false;
      _enviaBalanca = false;
      _codigosFornecedor = [];
      _observacaoPadraoController.text = '';
      _ehComposto = false;
      _composicao = [];
      
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
    _descricaoController.dispose();
    _unidadeController.dispose();
    _grupoController.dispose();
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

    final produto = Produto(
      id: (widget.item?.id != null && widget.item!.id.isNotEmpty)
          ? widget.item!.id
          : _uuid.v4(),
      codigo: _codigo,
      codigoBarras: _codigoBarras.isNotEmpty
          ? _codigoBarras
          : null,
      nome: _nome,
      descricao: _descricao,
      unidade: (_unidadeController.text.trim().isNotEmpty ? _unidadeController.text.trim() : 'peça'),
      grupo: (_grupo.isNotEmpty ? _grupo : 'Sem Grupo'),
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
      enviaBalanca: _enviaBalanca,
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
      composicao: _composicao,
      observacaoPadrao: _observacaoPadraoController.text.trim().isNotEmpty ? _observacaoPadraoController.text.trim() : null,
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
    );
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
            child: TextFormField(
              controller: _codigoBarrasController,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
              decoration: _minimalInput('Ex: 789000...'),
              onChanged: (v) => _codigoBarras = v,
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

        _buildSection('Configurações de Preparação e Balança', [
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Preparar na Cozinha', style: TextStyle(color: Colors.white, fontSize: 12)),
                  value: _paraCozinha,
                  activeColor: Colors.orangeAccent,
                  checkColor: Colors.black,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _paraCozinha = v ?? false),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Preparar no Bar', style: TextStyle(color: Colors.white, fontSize: 12)),
                  value: _paraBar,
                  activeColor: Colors.blueAccent,
                  checkColor: Colors.black,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _paraBar = v ?? false),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Enviar para Balança', style: TextStyle(color: Colors.white, fontSize: 12)),
                  value: _enviaBalanca,
                  activeColor: Colors.tealAccent,
                  checkColor: Colors.black,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _enviaBalanca = v ?? false),
                ),
              ),
            ],
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
            label: 'Unidade de Medida',
            last: true,
            child: _buildAutocomplete(
              controller: _unidadeController,
              hint: 'Ex: UN, KG, LT',
              sugestoes: _obterUnidadesUnicas(),
              onChanged: (v) => setState(() => _unidade = v),
            ),
          ),
        ]),

        _buildSection('Promoção', [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              const Text('Habilitar Promoção', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
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
              label: 'Preço Promocional',
              last: true,
              child: TextFormField(
                controller: _precoPromocionalController,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold),
                decoration: _minimalInput('0.00'),
                onChanged: (v) => _precoPromocional = double.tryParse(v.replaceAll(',', '.')),
              ),
            ),
          ],
        ]),
      ],
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
    final cor = isEntrada ? Colors.greenAccent : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.03))),
      child: Row(
        children: [
          Icon(isEntrada ? Icons.arrow_downward : Icons.arrow_upward, color: cor.withOpacity(0.5), size: 16),
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
                if (h.observacao != null && h.observacao!.isNotEmpty)
                  Text(h.observacao!, style: TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic), maxLines: 2),
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
                onChanged: (v) => setState(() => _ehComposto = v),
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
                    subtitle: Text('${item.quantidade} $unidade', style: const TextStyle(color: Colors.blueAccent)),
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
          ],
        ]),
      ],
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

    final searchController = TextEditingController();
    final qtdController = TextEditingController(
      text: itemEdicao != null ? itemEdicao.quantidade.toString() : '',
    );
    final totalSacoController = TextEditingController();
    final usoController = TextEditingController(text: '1');
    bool mostrarCalculadora = false;

    showDialog(
      context: pageContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text(itemEdicao != null ? 'Editar Ingrediente' : 'Adicionar Ingrediente', style: const TextStyle(color: Colors.white)),
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
                    TextField(
                      controller: qtdController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Quantidade/Fração',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          mostrarCalculadora = !mostrarCalculadora;
                        });
                      },
                      icon: Icon(
                        mostrarCalculadora ? Icons.keyboard_arrow_up : Icons.calculate_outlined,
                        color: Colors.blueAccent,
                        size: 16,
                      ),
                      label: Text(
                        mostrarCalculadora ? 'Ocultar Calculadora' : 'Calcular Proporção (Saco, Ração, etc.)',
                        style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
                      ),
                    ),
                    if (mostrarCalculadora) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Defina o peso total do saco fechado para baixa automática:',
                              style: TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: totalSacoController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Peso do Saco Inteiro (Ex: 15)',
                                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (v) {
                                      final total = double.tryParse(totalSacoController.text.replaceAll(',', '.')) ?? 0.0;
                                      final uso = double.tryParse(usoController.text.isEmpty ? '1' : usoController.text.replaceAll(',', '.')) ?? 1.0;
                                      if (total > 0) {
                                        final resultado = uso / total;
                                        qtdController.text = resultado.toStringAsFixed(6);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: usoController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Fração Base (Ex: 1 Kg)',
                                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (v) {
                                      final total = double.tryParse(totalSacoController.text.replaceAll(',', '.')) ?? 0.0;
                                      final uso = double.tryParse(usoController.text.replaceAll(',', '.')) ?? 1.0;
                                      if (total > 0) {
                                        final resultado = uso / total;
                                        qtdController.text = resultado.toStringAsFixed(6);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '💡 Dica: Deixe a Fração Base como "1". O sistema fará a conta para 1 Kg. \n'
                              'No PDV você poderá vender qualquer quantidade fracionada livre (ex: 0.5 Kg, 2.3 Kg, 15 Kg) e a baixa no saco de ração ocorrerá perfeitamente na proporção correta.',
                              style: TextStyle(color: Colors.white30, fontSize: 9, height: 1.3),
                            ),
                          ],
                        ),
                      ),
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
                    if (produtoSelecionadoId == null) return;
                    final qtdStr = qtdController.text.trim().replaceAll(',', '.');
                    final qtd = double.tryParse(qtdStr) ?? 0.0;
                    if (qtd <= 0) return;

                    setState(() {
                      if (itemEdicao != null) {
                        // Se o produto selecionado mudou durante a edicao, removemos o ID antigo
                        if (itemEdicao.produtoId != produtoSelecionadoId) {
                          _composicao.removeWhere((c) => c.produtoId == itemEdicao.produtoId);
                        }
                      }
                      
                      // Verifica se já existe o novo produto selecionado na lista, se sim atualiza, senao adiciona
                      final idx = _composicao.indexWhere((c) => c.produtoId == produtoSelecionadoId);
                      if (idx >= 0) {
                        _composicao[idx] = ItemComposicao(produtoId: produtoSelecionadoId!, quantidade: qtd);
                      } else {
                        _composicao.add(ItemComposicao(produtoId: produtoSelecionadoId!, quantidade: qtd));
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: Text(itemEdicao != null ? 'SALVAR' : 'ADICIONAR'),
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


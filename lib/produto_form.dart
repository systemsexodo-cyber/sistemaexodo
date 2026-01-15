import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/codigo_service.dart';
import 'package:sistema_exodo_novo/services/grupos_manager.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/services/image_storage_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io';

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
  late int _estoque;
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
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Adicionar listener para atualizar contador de caracteres
    _descricaoController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    if (widget.item != null) {
      // Editando produto existente
      _codigo = widget.item?.codigo ?? '';
      _codigoEditavel = false; // Código não é editável em edição
      _codigoBarras = widget.item?.codigoBarras ?? '';
      _nome = widget.item?.nome ?? '';
      _descricao = widget.item?.descricao ?? '';
      _unidade = (widget.item?.unidade ?? '').isNotEmpty
          ? widget.item!.unidade
          : 'peça';
      _grupo = widget.item?.grupo ?? 'Sem Grupo';
      _preco = widget.item?.preco ?? 0.0;
      _precoCusto = widget.item?.precoCusto;
      _estoque = widget.item?.estoque ?? 0;
      _codigoController.text = _codigo;
      _codigoBarrasController.text = _codigoBarras;
      _descricaoController.text = _descricao;
      _unidadeController.text = _unidade;
      _grupoController.text = _grupo;
      _precoController.text = _preco.toString();
      _precoCustoController.text = _precoCusto?.toString() ?? '';
      _estoqueController.text = _estoque.toString();

      // Carregar dados de promoção
      _precoPromocional = widget.item?.precoPromocional;
      _promocaoInicio = widget.item?.promocaoInicio;
      _promocaoFim = widget.item?.promocaoFim;
      _temPromocao = _precoPromocional != null;
      if (_precoPromocional != null) {
        _precoPromocionalController.text = _precoPromocional.toString();
      }
    } else {
      // Novo produto
      _nome = '';
      _descricao = '';
      _unidade = '';
      _preco = 0.0;
      _precoCusto = null;
      _estoque = 0;
      _codigoBarras = '';
      _grupo = 'Sem Grupo';
      _codigoEditavel = true; // Código é editável para novos produtos
      _temPromocao = false;
      _precoPromocional = null;
      _promocaoInicio = null;
      _promocaoFim = null;
      
      // Inicializar campos de impostos
      _ncm = null;
      _icmsAliquota = null;
      _icmsCst = null;
      _ipiAliquota = null;
      _ipiCst = null;
      _pisAliquota = null;
      _pisCst = null;
      _cofinsAliquota = null;
      _cofinsCst = null;
      _issAliquota = null;
      _origem = null;
      _cfop = null;
      _cest = null;
      _csosn = null;
      _simplesNacionalAliquota = null;
      
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
    super.dispose();
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
    final service = Provider.of<DataService>(context, listen: false);
    List historico = [];
    if (widget.item != null) {
      historico = service.estoqueHistorico
          .where((h) => h.produtoId == widget.item.id)
          .toList();
      historico.sort((a, b) => b.data.compareTo(a.data));
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header melhorado com gradiente e design minimalista
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade700,
                    Colors.purple.shade700,
                    Colors.indigo.shade800,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      widget.item == null ? Icons.add_circle_outline : Icons.edit_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item == null ? 'NOVO PRODUTO' : 'EDITAR PRODUTO',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Preencha as informações abaixo',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botão Salvar compacto no header
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade500,
                          Colors.green.shade700,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.shade700.withOpacity(0.6),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          if (_formKey.currentState?.validate() ?? false) {
                            _salvarProduto();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Text(
                                widget.item == null ? 'SALVAR' : 'ATUALIZAR',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 1,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // TabBar melhorado
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.2),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                    width: 2,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.blue.shade400,
                indicatorWeight: 4,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.info_outline, size: 24),
                    text: 'Informações',
                  ),
                  Tab(
                    icon: Icon(Icons.receipt_long, size: 24),
                    text: 'Impostos',
                  ),
                  Tab(
                    icon: Icon(Icons.shopping_cart, size: 24),
                    text: 'E-commerce',
                  ),
                ],
              ),
            ),
            // Conteúdo das abas
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Aba 1: Informações
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildAbaInformacoes(),
                  ),
                  // Aba 2: Impostos
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildAbaImpostos(),
                  ),
                  // Aba 3: E-commerce
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildAbaEcommerce(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Método para salvar o produto (extraído para reutilização)
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
      id: widget.item?.id ?? UniqueKey().toString(),
      codigo: _codigo,
      codigoBarras: _codigoBarras.isNotEmpty
          ? _codigoBarras
          : null,
      nome: _nome,
      descricao: _descricao,
      unidade: (_unidade.isNotEmpty ? _unidade : 'peça'),
      grupo: (_grupo.isNotEmpty ? _grupo : 'Sem Grupo'),
      preco: _preco,
      precoCusto: _precoCusto,
      estoque: _estoque,
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
    
    widget.onSave(produto);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Produto cadastrado com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Widget auxiliar para criar cards visuais minimalistas
  Widget _buildCardCampo({
    required String titulo,
    required IconData icone,
    required MaterialColor cor,
    required Widget child,
    String? subtitulo,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cor.withOpacity(0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cor.shade600,
                      cor.shade800,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: cor.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icone,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  /// Widget auxiliar para botões de ícone compactos
  Widget _buildBotaoIcone({
    required IconData icone,
    required MaterialColor cor,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(
              icone,
              color: cor.shade300,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAbaInformacoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card de Código - Design minimalista e visual
        _buildCardCampo(
          titulo: 'Código do Produto',
          icone: Icons.qr_code_2,
          cor: Colors.blue,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _codigoController,
                  decoration: InputDecoration(
                    hintText: 'Ex: PRD-0001',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 16,
                    ),
                  ),
                  readOnly: !_codigoEditavel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  onChanged: (value) => _codigo = value,
                  validator: _codigoEditavel
                      ? (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o código';
                          }
                          return null;
                        }
                      : null,
                ),
              ),
              if (_codigoEditavel) ...[
                const SizedBox(width: 8),
                _buildBotaoIcone(
                  icone: Icons.auto_fix_high,
                  cor: Colors.orange,
                  tooltip: 'Preencher furos',
                  onPressed: _gerarProximoCodigo,
                ),
                const SizedBox(width: 8),
                _buildBotaoIcone(
                  icone: Icons.arrow_forward,
                  cor: Colors.blue,
                  tooltip: 'Próximo código',
                  onPressed: _gerarProximoUltimo,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Card de Código de Barras
        _buildCardCampo(
          titulo: 'Código de Barras',
          icone: Icons.qr_code,
          cor: Colors.purple,
          subtitulo: 'Opcional - EAN/UPC',
          child: TextFormField(
            controller: _codigoBarrasController,
            decoration: InputDecoration(
              hintText: 'Ex: 5901234123457',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) => _codigoBarras = value,
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: 20),
        // Card de Nome
        _buildCardCampo(
          titulo: 'Nome do Produto',
          icone: Icons.inventory_2_outlined,
          cor: Colors.green,
          child: TextFormField(
            initialValue: _nome,
            decoration: InputDecoration(
              hintText: 'Ex: Camiseta Manga Curta Preta',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe o nome';
              }
              return null;
            },
            onChanged: (value) => _nome = value,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
        ),
        const SizedBox(height: 20),
        // Card de Descrição
        _buildCardCampo(
          titulo: 'Descrição',
          icone: Icons.description_outlined,
          cor: Colors.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _descricaoController,
                decoration: InputDecoration(
                  hintText: 'Descreva detalhadamente o produto...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 16,
                  ),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.7,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 5,
                minLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a descrição';
                  }
                  return null;
                },
                onChanged: (value) => _descricao = value,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_descricaoController.text.length} caracteres',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Card de Informações Básicas (Unidade, Estoque, Grupo)
        Row(
          children: [
            Expanded(
              child: _buildCardCampo(
                titulo: 'Unidade',
                icone: Icons.straighten,
                cor: Colors.indigo,
                child: TextFormField(
                  controller: _unidadeController,
                  decoration: InputDecoration(
                    hintText: 'Ex: UN, KG, LT',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 16,
                    ),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe a unidade';
                    }
                    return null;
                  },
                  onChanged: (value) => _unidade = value,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardCampo(
                titulo: 'Estoque',
                icone: Icons.inventory,
                cor: Colors.teal,
                child: TextFormField(
                  controller: _estoqueController,
                  decoration: InputDecoration(
                    hintText: 'Quantidade',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 16,
                    ),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o estoque';
                    }
                    final estoque = int.tryParse(value);
                    if (estoque == null || estoque < 0) {
                      return 'Estoque inválido';
                    }
                    return null;
                  },
                  onChanged: (value) => _estoque = int.tryParse(value) ?? 0,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Card de Grupo
        _buildCardCampo(
          titulo: 'Grupo',
          icone: Icons.category,
          cor: Colors.pink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _grupoController,
            decoration: InputDecoration(
              hintText: 'Ex: Periféricos, Hardware, Serviços',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe o grupo';
                  }
                  return null;
                },
                onChanged: (value) {
                  _grupo = value;
                },
                textInputAction: TextInputAction.next,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Card de Preço de Venda
        _buildCardCampo(
          titulo: 'Preço de Venda',
          icone: Icons.attach_money,
          cor: Colors.green,
          subtitulo: 'Valor de venda do produto',
          child: TextFormField(
            controller: _precoController,
            decoration: InputDecoration(
              hintText: 'Ex: 99.90',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe o preço';
              }
              final preco = double.tryParse(value.replaceAll(',', '.'));
              if (preco == null || preco < 0) {
                return 'Preço inválido';
              }
              return null;
            },
            onChanged: (value) {
              _preco = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
              setState(() {}); // Atualizar margem de lucro
            },
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: 20),
        // Card de Preço de Custo
        _buildCardCampo(
          titulo: 'Preço de Custo',
          icone: Icons.shopping_cart,
          cor: Colors.orange,
          subtitulo: _precoCusto != null && _precoCusto! > 0 && _preco > 0
              ? _calcularMargemLucro()
              : 'Opcional - Informe para calcular margem',
          child: TextFormField(
            controller: _precoCustoController,
            decoration: InputDecoration(
              hintText: 'Ex: 50.00',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                final custo = double.tryParse(value.replaceAll(',', '.'));
                if (custo == null || custo < 0) {
                  return 'Custo inválido';
                }
              }
              return null;
            },
            onChanged: (value) {
              _precoCusto = value.isEmpty
                  ? null
                  : double.tryParse(value.replaceAll(',', '.'));
              setState(() {}); // Atualizar margem de lucro
            },
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: 20),

              // ========== SEÇÃO DE PROMOÇÃO ==========
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _temPromocao
                      ? Colors.red.shade900.withOpacity(0.3)
                      : Colors.grey.shade800.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _temPromocao
                        ? Colors.red.shade400
                        : Colors.grey.shade600,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_offer,
                          color: _temPromocao
                              ? Colors.red.shade300
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PROMOÇÃO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _temPromocao
                                ? Colors.red.shade300
                                : Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: _temPromocao,
                          activeThumbColor: Colors.red,
                          onChanged: (value) {
                            setState(() {
                              _temPromocao = value;
                              if (!value) {
                                _precoPromocional = null;
                                _promocaoInicio = null;
                                _promocaoFim = null;
                                _precoPromocionalController.clear();
                              } else {
                                _promocaoInicio = DateTime.now();
                                _promocaoFim = DateTime.now().add(
                                  const Duration(days: 7),
                                );
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (_temPromocao) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _precoPromocionalController,
                        decoration: InputDecoration(
                          labelText: 'Preço Promocional',
                          prefixIcon: Icon(
                            Icons.sell,
                            color: Colors.red.shade300,
                          ),
                          hintText: 'Ex: 79.90',
                          filled: true,
                          fillColor: Colors.red.shade900.withOpacity(0.2),
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        validator: _temPromocao
                            ? (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Informe o preço promocional';
                                }
                                final preco = double.tryParse(
                                  value.replaceAll(',', '.'),
                                );
                                if (preco == null || preco < 0) {
                                  return 'Preço inválido';
                                }
                                if (preco >= _preco) {
                                  return 'Deve ser menor que o preço normal';
                                }
                                return null;
                              }
                            : null,
                        onChanged: (value) => _precoPromocional =
                            double.tryParse(value.replaceAll(',', '.')),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final data = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _promocaoInicio ?? DateTime.now(),
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 30),
                                  ),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (data != null) {
                                  setState(() => _promocaoInicio = data);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade900.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade400,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'INÍCIO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                      ),
                                    ),
                                    Text(
                                      _promocaoInicio != null
                                          ? '${_promocaoInicio!.day.toString().padLeft(2, '0')}/${_promocaoInicio!.month.toString().padLeft(2, '0')}/${_promocaoInicio!.year}'
                                          : 'Selecionar',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.arrow_forward,
                              color: Colors.grey,
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final data = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _promocaoFim ??
                                      DateTime.now().add(
                                        const Duration(days: 7),
                                      ),
                                  firstDate: _promocaoInicio ?? DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (data != null) {
                                  setState(() => _promocaoFim = data);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade400,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.event,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'FIM',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                      ),
                                    ),
                                    Text(
                                      _promocaoFim != null
                                          ? '${_promocaoFim!.day.toString().padLeft(2, '0')}/${_promocaoFim!.month.toString().padLeft(2, '0')}/${_promocaoFim!.year}'
                                          : 'Selecionar',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_precoPromocional != null && _preco > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.trending_down,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Desconto: ${((_preco - _precoPromocional!) / _preco * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ],
    );
  }
  
  Widget _buildAbaEcommerce() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Título da seção
        Row(
          children: [
            Icon(Icons.shopping_cart, color: Colors.purple.shade300),
            const SizedBox(width: 8),
            const Text(
              'Configurações de E-commerce',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Checkbox para exibir na loja
        Card(
          color: const Color(0xFF23272A),
          child: CheckboxListTile(
            title: const Text(
              'Exibir na Loja Online',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Quando ativado, este produto aparecerá na loja pública',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
            value: _exibirNaLoja,
            onChanged: (value) {
              setState(() {
                _exibirNaLoja = value ?? false;
                // Se desativar "Exibir na Loja", também desativa "Em Destaque"
                if (!_exibirNaLoja) {
                  _emDestaque = false;
                }
              });
            },
            activeColor: Colors.purple,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF23272A),
          child: CheckboxListTile(
            title: const Text(
              'Produto em Destaque',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Quando ativado, este produto aparecerá no topo da loja em destaque',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
            value: _emDestaque,
            onChanged: _exibirNaLoja ? (value) {
              setState(() {
                _emDestaque = value ?? false;
              });
            } : null, // Desabilitado se "Exibir na Loja" estiver desativado
            activeColor: Colors.orange,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 24),
        
        // Seção de Variações
        _buildSecaoVariacoes(),
        const SizedBox(height: 24),
        
        // Seção de Fotos
        const Text(
          '📸 Fotos do Produto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Adicione fotos para exibir na loja. A primeira foto será a principal.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        
        // Grid de fotos
        if (_fotosUrls.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: _fotosUrls.length,
            itemBuilder: (context, index) {
              final fotoUrl = _fotosUrls[index];
              final isPrincipal = index == 0;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      fotoUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.broken_image, color: Colors.white54),
                        );
                      },
                    ),
                  ),
                  if (isPrincipal)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Principal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.8),
                        padding: const EdgeInsets.all(4),
                        minimumSize: const Size(24, 24),
                      ),
                      onPressed: () {
                        setState(() {
                          _fotosUrls.removeAt(index);
                        });
                      },
                    ),
                  ),
                  if (index > 0)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: IconButton(
                        icon: const Icon(Icons.star, color: Colors.white, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.8),
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(24, 24),
                        ),
                        onPressed: () {
                          setState(() {
                            final foto = _fotosUrls.removeAt(index);
                            _fotosUrls.insert(0, foto);
                          });
                        },
                        tooltip: 'Definir como principal',
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 12),
        
        // Botões de upload
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploadingFotos ? null : _adicionarFotos,
                icon: _uploadingFotos
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate),
                label: Text(_uploadingFotos ? 'Enviando...' : 'Adicionar Fotos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (_fotosUrls.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _fotosUrls.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover Todas'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        
        // Descrição para E-commerce
        TextFormField(
          controller: _descricaoEcommerceController,
          decoration: const InputDecoration(
            labelText: 'Descrição para E-commerce',
            hintText: 'Descrição detalhada que aparecerá na loja online',
            prefixIcon: Icon(Icons.description),
            helperText: 'Esta descrição será exibida na loja. Se vazio, usa a descrição padrão.',
          ),
          maxLines: 4,
          onChanged: (value) => _descricaoEcommerce = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 24),
        
        // Dimensões e Peso
        const Text(
          '📦 Dimensões e Peso (para cálculo de frete)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _pesoGramasController,
                decoration: const InputDecoration(
                  labelText: 'Peso (gramas)',
                  prefixIcon: Icon(Icons.scale),
                  hintText: 'Ex: 500',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _pesoGramas = value.isEmpty ? null : int.tryParse(value);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _alturaCmController,
                decoration: const InputDecoration(
                  labelText: 'Altura (cm)',
                  prefixIcon: Icon(Icons.height),
                  hintText: 'Ex: 10.5',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  _alturaCm = value.isEmpty
                      ? null
                      : double.tryParse(value.replaceAll(',', '.'));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _larguraCmController,
                decoration: const InputDecoration(
                  labelText: 'Largura (cm)',
                  prefixIcon: Icon(Icons.width_wide),
                  hintText: 'Ex: 15.0',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  _larguraCm = value.isEmpty
                      ? null
                      : double.tryParse(value.replaceAll(',', '.'));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _profundidadeCmController,
                decoration: const InputDecoration(
                  labelText: 'Profundidade (cm)',
                  prefixIcon: Icon(Icons.straighten),
                  hintText: 'Ex: 20.0',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  _profundidadeCm = value.isEmpty
                      ? null
                      : double.tryParse(value.replaceAll(',', '.'));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Tags
        TextFormField(
          controller: _tagsController,
          decoration: const InputDecoration(
            labelText: 'Tags (separadas por vírgula)',
            hintText: 'Ex: promocao, destaque, novo, pet',
            prefixIcon: Icon(Icons.label),
            helperText: 'Tags ajudam na busca e categorização na loja',
          ),
          onChanged: (value) {
            _tags = value
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();
          },
        ),
        const SizedBox(height: 24),
        
        // Informações sobre e-commerce
        Card(
          color: Colors.blue.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Dicas para E-commerce',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Adicione pelo menos uma foto de boa qualidade\n'
                  '• A primeira foto será exibida como principal\n'
                  '• Use tags relevantes para facilitar a busca\n'
                  '• Dimensões e peso ajudam no cálculo de frete\n'
                  '• Produtos com "Exibir na Loja" aparecerão na loja pública',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  
  Widget _buildAbaImpostos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // NCM
        TextFormField(
          controller: _ncmController,
          decoration: const InputDecoration(
            labelText: 'NCM (Nomenclatura Comum do Mercosul)',
            prefixIcon: Icon(Icons.qr_code_scanner),
            hintText: 'Ex: 85171200',
            helperText: 'Código de 8 dígitos obrigatório para produtos',
          ),
          keyboardType: TextInputType.number,
          maxLength: 8,
          onChanged: (value) => _ncm = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 16),
        
        // Origem
        TextFormField(
          controller: _origemController,
          decoration: const InputDecoration(
            labelText: 'Origem da Mercadoria',
            prefixIcon: Icon(Icons.flag),
            hintText: '0-Nacional, 1-Estrangeira, etc',
            helperText: 'Código de origem conforme legislação',
          ),
          keyboardType: TextInputType.number,
          maxLength: 1,
          onChanged: (value) => _origem = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 16),
        
        // CFOP
        TextFormField(
          controller: _cfopController,
          decoration: const InputDecoration(
            labelText: 'CFOP (Código Fiscal de Operações)',
            prefixIcon: Icon(Icons.receipt),
            hintText: 'Ex: 5102',
            helperText: 'Código de 4 dígitos',
          ),
          keyboardType: TextInputType.number,
          maxLength: 4,
          onChanged: (value) => _cfop = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 24),
        
        // Divisor Simples Nacional
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.account_balance, color: Colors.orange.shade300),
            const SizedBox(width: 8),
            const Text(
              'Simples Nacional',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // CSOSN (Código de Situação da Operação - Simples Nacional)
        TextFormField(
          controller: _csosnController,
          decoration: const InputDecoration(
            labelText: 'CSOSN',
            prefixIcon: Icon(Icons.numbers),
            hintText: 'Ex: 101, 102, 201, 202, etc',
            helperText: 'Código de Situação da Operação - Simples Nacional',
          ),
          keyboardType: TextInputType.number,
          maxLength: 3,
          onChanged: (value) => _csosn = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 8),
        
        // Alíquota Simples Nacional
        TextFormField(
          controller: _simplesNacionalAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota Simples Nacional (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 6.00, 12.00, 15.00',
            helperText: 'Percentual da alíquota do Simples Nacional',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _simplesNacionalAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 24),
        
        // CEST
        TextFormField(
          controller: _cestController,
          decoration: const InputDecoration(
            labelText: 'CEST (Código Especificador da Substituição Tributária)',
            prefixIcon: const Icon(Icons.qr_code),
            hintText: 'Ex: 0100100',
            helperText: 'Opcional - Apenas para produtos com ST',
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) => _cest = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 24),
        
        // Divisor ICMS
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.account_balance, color: Colors.blue.shade300),
            const SizedBox(width: 8),
            const Text(
              'ICMS (Imposto sobre Circulação de Mercadorias)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // ICMS CST
        TextFormField(
          controller: _icmsCstController,
          decoration: const InputDecoration(
            labelText: 'CST ICMS',
            prefixIcon: Icon(Icons.numbers),
            hintText: 'Ex: 00, 10, 20, 30, etc',
            helperText: 'Código de Situação Tributária do ICMS',
          ),
          keyboardType: TextInputType.text,
          maxLength: 3,
          onChanged: (value) => _icmsCst = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 8),
        
        // ICMS Alíquota
        TextFormField(
          controller: _icmsAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota ICMS (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 18.00',
            helperText: 'Percentual da alíquota do ICMS',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _icmsAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 24),
        
        // Divisor IPI
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.factory, color: Colors.orange.shade300),
            const SizedBox(width: 8),
            const Text(
              'IPI (Imposto sobre Produtos Industrializados)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // IPI CST
        TextFormField(
          controller: _ipiCstController,
          decoration: const InputDecoration(
            labelText: 'CST IPI',
            prefixIcon: Icon(Icons.numbers),
            hintText: 'Ex: 00, 01, 02, etc',
            helperText: 'Código de Situação Tributária do IPI',
          ),
          keyboardType: TextInputType.text,
          maxLength: 3,
          onChanged: (value) => _ipiCst = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 8),
        
        // IPI Alíquota
        TextFormField(
          controller: _ipiAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota IPI (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 5.00',
            helperText: 'Percentual da alíquota do IPI',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _ipiAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 24),
        
        // Divisor PIS
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.green.shade300),
            const SizedBox(width: 8),
            const Text(
              'PIS (Programa de Integração Social)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // PIS CST
        TextFormField(
          controller: _pisCstController,
          decoration: const InputDecoration(
            labelText: 'CST PIS',
            prefixIcon: Icon(Icons.numbers),
            hintText: 'Ex: 01, 02, 03, etc',
            helperText: 'Código de Situação Tributária do PIS',
          ),
          keyboardType: TextInputType.text,
          maxLength: 3,
          onChanged: (value) => _pisCst = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 8),
        
        // PIS Alíquota
        TextFormField(
          controller: _pisAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota PIS (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 1.65',
            helperText: 'Percentual da alíquota do PIS',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _pisAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 24),
        
        // Divisor COFINS
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.savings, color: Colors.purple.shade300),
            const SizedBox(width: 8),
            const Text(
              'COFINS (Contribuição para o Financiamento da Seguridade Social)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // COFINS CST
        TextFormField(
          controller: _cofinsCstController,
          decoration: const InputDecoration(
            labelText: 'CST COFINS',
            prefixIcon: Icon(Icons.numbers),
            hintText: 'Ex: 01, 02, 03, etc',
            helperText: 'Código de Situação Tributária do COFINS',
          ),
          keyboardType: TextInputType.text,
          maxLength: 3,
          onChanged: (value) => _cofinsCst = value.isEmpty ? null : value,
        ),
        const SizedBox(height: 8),
        
        // COFINS Alíquota
        TextFormField(
          controller: _cofinsAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota COFINS (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 7.60',
            helperText: 'Percentual da alíquota do COFINS',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _cofinsAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 24),
        
        // Divisor ISS
        const Divider(color: Colors.white24),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.business, color: Colors.teal.shade300),
            const SizedBox(width: 8),
            const Text(
              'ISS (Imposto sobre Serviços)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // ISS Alíquota
        TextFormField(
          controller: _issAliquotaController,
          decoration: const InputDecoration(
            labelText: 'Alíquota ISS (%)',
            prefixIcon: Icon(Icons.percent),
            hintText: 'Ex: 5.00',
            helperText: 'Percentual da alíquota do ISS (para serviços)',
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            _issAliquota = value.isEmpty
                ? null
                : double.tryParse(value.replaceAll(',', '.'));
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }
  
  // Seção de Variações de Produto
  Widget _buildSecaoVariacoes() {
    return Card(
      color: const Color(0xFF23272A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            title: const Text(
              'Produto com Variações',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Ative para adicionar variações como tamanhos, cores, sabores, etc.',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
            value: _temVariacoes,
            onChanged: (value) {
              setState(() {
                _temVariacoes = value ?? false;
                if (!_temVariacoes) {
                  _variacoes.clear();
                }
              });
            },
            activeColor: Colors.blue,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_temVariacoes) ...[
            const Divider(color: Colors.white24),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Variações Configuradas',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _adicionarVariacao,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_variacoes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[800]?.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Nenhuma variação adicionada. Clique em "Adicionar" para criar.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._variacoes.asMap().entries.map((entry) {
                      final index = entry.key;
                      final variacao = entry.value;
                      return _buildCardVariacao(variacao, index);
                    }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildCardVariacao(VariacaoProduto variacao, int index) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${variacao.nomeAtributo}: ${variacao.valor}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (variacao.precoAdicional != null)
              Text(
                'Preço adicional: R\$ ${variacao.precoAdicional!.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            Text(
              'Estoque: ${variacao.estoque}',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              variacao.ativo ? '✓ Ativo' : '✗ Inativo',
              style: TextStyle(
                color: variacao.ativo ? Colors.green : Colors.red,
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
              onPressed: () => _editarVariacao(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: () => _removerVariacao(index),
            ),
          ],
        ),
      ),
    );
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
    final precoAdicionalController = TextEditingController(
      text: variacao?.precoAdicional?.toString() ?? '',
    );
    final estoqueController = TextEditingController(
      text: variacao?.estoque.toString() ?? '0',
    );
    final codigoBarrasController = TextEditingController(text: variacao?.codigoBarras ?? '');
    final skuController = TextEditingController(text: variacao?.sku ?? '');
    bool ativo = variacao?.ativo ?? true;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF23272A),
          title: Text(
            variacao == null ? 'Adicionar Variação' : 'Editar Variação',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeAtributoController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Atributo',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'Ex: Tamanho, Cor, Sabor',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valorController,
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'Ex: P, Azul, Morango',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: precoAdicionalController,
                  decoration: const InputDecoration(
                    labelText: 'Preço Adicional (R\$)',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: '0.00 (deixe vazio para usar preço base)',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: estoqueController,
                  decoration: const InputDecoration(
                    labelText: 'Estoque',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codigoBarrasController,
                  decoration: const InputDecoration(
                    labelText: 'Código de Barras (opcional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: skuController,
                  decoration: const InputDecoration(
                    labelText: 'SKU (opcional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text(
                    'Ativo',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: ativo,
                  onChanged: (value) {
                    setDialogState(() {
                      ativo = value ?? true;
                    });
                  },
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nomeAtributoController.text.isEmpty || valorController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Preencha o nome do atributo e o valor'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                final novaVariacao = VariacaoProduto(
                  id: variacao?.id ?? UniqueKey().toString(),
                  nomeAtributo: nomeAtributoController.text.trim(),
                  valor: valorController.text.trim(),
                  precoAdicional: precoAdicionalController.text.isNotEmpty
                      ? double.tryParse(precoAdicionalController.text.replaceAll(',', '.'))
                      : null,
                  estoque: int.tryParse(estoqueController.text) ?? 0,
                  codigoBarras: codigoBarrasController.text.isNotEmpty
                      ? codigoBarrasController.text.trim()
                      : null,
                  sku: skuController.text.isNotEmpty ? skuController.text.trim() : null,
                  ativo: ativo,
                );
                
                setState(() {
                  if (index != null) {
                    _variacoes[index] = novaVariacao;
                  } else {
                    _variacoes.add(novaVariacao);
                  }
                });
                
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Salvar'),
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

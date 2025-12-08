import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/codigo_service.dart';
import 'package:sistema_exodo_novo/services/grupos_manager.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'pages/estoque_historico_page.dart';

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
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
            const SizedBox(height: 16),
            Text(
              widget.item == null ? 'Cadastro de Produto' : 'Editar Produto',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // TabBar
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.greenAccent,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline), text: 'Informações'),
                Tab(icon: Icon(Icons.receipt_long), text: 'Impostos'),
              ],
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAbaInformacoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
              // Campo de código editável com botão para gerar novo
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codigoController,
                      decoration: InputDecoration(
                        labelText: 'Código do Produto',
                        prefixIcon: Icon(Icons.qr_code_2),
                        helperText: widget.item == null
                            ? 'Editar ou gerar novo'
                            : 'Código não editável',
                      ),
                      readOnly: !_codigoEditavel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _codigoEditavel
                            ? Colors.white
                            : Colors.blue.shade700,
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
                  if (_codigoEditavel)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 8),
                          child: Tooltip(
                            message: 'Preencher furos (PRD-0003, etc)',
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: _gerarProximoCodigo,
                              child: const Icon(Icons.build),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Tooltip(
                            message: 'Próximo do último (PRD-0006)',
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: _gerarProximoUltimo,
                              child: const Icon(Icons.arrow_forward),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // ...campos do produto...
              // Botão para abrir histórico de estoque
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.history, size: 20),
                  label: const Text('Movimentação de Estoque'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.item == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  EstoqueHistoricoPage(produto: widget.item),
                            ),
                          );
                        },
                ),
              ),
              TextFormField(
                controller: _codigoBarrasController,
                decoration: InputDecoration(
                  labelText: 'Código de Barras (EAN/UPC)',
                  prefixIcon: Icon(Icons.qr_code),
                  hintText: 'Ex: 5901234123457',
                  helperText: 'Opcional - Código de barras do produto',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => _codigoBarras = value,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _nome,
                decoration: InputDecoration(
                  labelText: 'Nome do Produto',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
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
              const SizedBox(height: 8),
              TextFormField(
                controller: _descricaoController,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  prefixIcon: Icon(Icons.description_outlined),
                  hintText: 'Ex: Produto novo, com garantia, cor preta',
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a descrição';
                  }
                  return null;
                },
                onChanged: (value) => _descricao = value,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _unidadeController,
                decoration: InputDecoration(
                  labelText: 'Unidade',
                  prefixIcon: Icon(Icons.straighten),
                  helperText: 'Unidade de medida do produto',
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
              const SizedBox(height: 8),
              _CampoGrupoAutocomplete(
                controller: _grupoController,
                onChanged: (value) => _grupo = value,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _estoqueController,
                decoration: InputDecoration(
                  labelText: 'Estoque',
                  prefixIcon: Icon(Icons.storage),
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
              const SizedBox(height: 8),
              TextFormField(
                controller: _precoController,
                decoration: InputDecoration(
                  labelText: 'Preço',
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: 'Ex: 99.90',
                  helperText: 'Valor do produto ou serviço',
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
              const SizedBox(height: 16),

              // Campo de Preço de Custo
              TextFormField(
                controller: _precoCustoController,
                decoration: InputDecoration(
                  labelText: 'Preço de Custo (R\$)',
                  prefixIcon: Icon(Icons.shopping_cart),
                  hintText: 'Ex: 50.00',
                  helperText: _precoCusto != null && _precoCusto! > 0 && _preco > 0
                      ? _calcularMargemLucro()
                      : 'Informe o custo para calcular a margem de lucro',
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
              const SizedBox(height: 16),

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
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 28),
            label: Text(
              widget.item == null ? 'Cadastrar' : 'Salvar Alterações',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
              padding: WidgetStateProperty.all<EdgeInsets>(
                const EdgeInsets.symmetric(vertical: 8),
              ),
              textStyle: WidgetStateProperty.all<TextStyle>(
                const TextStyle(fontSize: 20),
              ),
            ),
            onPressed: () {
                    if (_formKey.currentState?.validate() ?? false) {
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
                      );
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
                  },
                ),
              ),
      ],
    );
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

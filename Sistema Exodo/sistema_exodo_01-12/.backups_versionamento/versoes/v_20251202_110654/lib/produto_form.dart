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

class _ProdutoServicoFormState extends State<ProdutoServicoForm> {
  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _unidadeController = TextEditingController();
  final _grupoController = TextEditingController();
  final _precoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _precoPromocionalController = TextEditingController();
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
  String? _codigoOriginal; // Guardar código original para edição

  // Campos de promoção
  bool _temPromocao = false;
  double? _precoPromocional;
  DateTime? _promocaoInicio;
  DateTime? _promocaoFim;
  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      // Editando produto existente
      _codigo = widget.item?.codigo ?? '';
      _codigoOriginal = _codigo;
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
      _codigoOriginal = null;
      _temPromocao = false;
      _precoPromocional = null;
      _promocaoInicio = null;
      _promocaoFim = null;
      // Gerar código automaticamente para novo produto
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gerarProximoCodigo();
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
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                widget.item == null ? 'Cadastro de Produto' : 'Editar Produto',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
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
                  icon: Icon(Icons.save, size: 28),
                  label: Text(
                    widget.item == null ? 'Cadastrar' : 'Salvar Alterações',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    padding: WidgetStateProperty.all<EdgeInsets>(
                      EdgeInsets.symmetric(vertical: 8),
                    ),
                    textStyle: WidgetStateProperty.all<TextStyle>(
                      TextStyle(fontSize: 20),
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
          ),
        ),
      ),
      // ...existing code...
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

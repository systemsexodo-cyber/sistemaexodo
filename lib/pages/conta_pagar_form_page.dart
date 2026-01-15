import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/nota_entrada.dart';
import '../theme.dart';

class ContaPagarFormPage extends StatefulWidget {
  final ContaPagar? contaPagar;

  const ContaPagarFormPage({super.key, this.contaPagar});

  @override
  State<ContaPagarFormPage> createState() => _ContaPagarFormPageState();
}

class _ContaPagarFormPageState extends State<ContaPagarFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _descricaoController = TextEditingController();
  final _valorController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _fornecedorController = TextEditingController();
  final _observacoesController = TextEditingController();
  
  TipoContaPagar _tipoSelecionado = TipoContaPagar.despesaVariavel;
  DateTime _dataVencimento = DateTime.now().add(const Duration(days: 30));
  NotaEntrada? _notaSelecionada;
  bool _recorrente = false;
  int? _intervaloRecorrencia;
  List<String> _categoriasExistentes = [];
  bool _mostrarCampoCategoria = false;

  @override
  void initState() {
    super.initState();
    _carregarCategoriasExistentes();
    if (widget.contaPagar != null) {
      final conta = widget.contaPagar!;
      _descricaoController.text = conta.descricao;
      _valorController.text = conta.valor.toStringAsFixed(2);
      _categoriaController.text = conta.categoria ?? '';
      _fornecedorController.text = conta.fornecedorNome ?? '';
      _observacoesController.text = conta.observacoes ?? '';
      _tipoSelecionado = conta.tipo;
      _dataVencimento = conta.dataVencimento;
      _recorrente = conta.recorrente;
      _intervaloRecorrencia = conta.intervaloRecorrencia;
      if (conta.categoria != null && !_categoriasExistentes.contains(conta.categoria)) {
        _categoriasExistentes.add(conta.categoria!);
        _categoriasExistentes.sort();
      }
    }
  }

  void _carregarCategoriasExistentes() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final categorias = dataService.contasPagar
        .where((c) => c.categoria != null && c.categoria!.isNotEmpty)
        .map((c) => c.categoria!)
        .toSet()
        .toList();
    categorias.sort();
    setState(() {
      _categoriasExistentes = categorias;
    });
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _categoriaController.dispose();
    _fornecedorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final dataService = Provider.of<DataService>(context, listen: false);
    final uuid = const Uuid();
    final valor = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0.0;

    if (valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O valor deve ser maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final conta = ContaPagar(
      id: widget.contaPagar?.id ?? uuid.v4(),
      numero: widget.contaPagar?.numero ?? dataService.getProximoNumeroContaPagar(),
      tipo: _tipoSelecionado,
      categoria: _categoriaController.text.isEmpty ? null : _categoriaController.text,
      descricao: _descricaoController.text,
      observacoes: _observacoesController.text.isEmpty ? null : _observacoesController.text,
      valor: valor,
      dataVencimento: _dataVencimento,
      notaEntradaId: _notaSelecionada?.id,
      notaEntradaNumero: _notaSelecionada?.numeroNota,
      fornecedorNome: _fornecedorController.text.isEmpty ? null : _fornecedorController.text,
      recorrente: _recorrente,
      intervaloRecorrencia: _recorrente ? (_intervaloRecorrencia ?? 30) : null,
      proximaDataRecorrencia: _recorrente && _intervaloRecorrencia != null
          ? _dataVencimento.add(Duration(days: _intervaloRecorrencia!))
          : null,
      status: widget.contaPagar?.status ?? StatusContaPagar.pendente,
      valorPago: widget.contaPagar?.valorPago,
      dataPagamento: widget.contaPagar?.dataPagamento,
      formaPagamento: widget.contaPagar?.formaPagamento,
    );

    if (widget.contaPagar != null) {
      dataService.updateContaPagar(conta);
    } else {
      await dataService.addContaPagar(conta);
    }

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.contaPagar != null 
              ? 'Conta atualizada com sucesso!' 
              : 'Conta cadastrada com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _selecionarNotaEntrada() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final notasDisponiveis = dataService.notasEntrada
        .where((n) => n.status == 'processada')
        .toList();

    if (notasDisponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma nota de entrada processada encontrada'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final notaSelecionada = await showDialog<NotaEntrada>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Selecionar Nota de Entrada', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: notasDisponiveis.length,
            itemBuilder: (context, index) {
              final nota = notasDisponiveis[index];
              return ListTile(
                title: Text(
                  nota.numeroNota,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Fornecedor: ${nota.fornecedorNome ?? "N/A"}\n'
                  'Valor: R\$ ${nota.valorTotal?.toStringAsFixed(2) ?? "0.00"}',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () => Navigator.pop(context, nota),
              );
            },
          ),
        ),
      ),
    );

    if (notaSelecionada != null) {
      setState(() {
        _notaSelecionada = notaSelecionada;
        _fornecedorController.text = notaSelecionada.fornecedorNome ?? '';
        if (notaSelecionada.valorTotal != null) {
          _valorController.text = notaSelecionada.valorTotal!.toStringAsFixed(2);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoData = DateFormat('dd/MM/yyyy');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.contaPagar != null ? 'Editar Conta' : 'Nova Conta a Pagar'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Tipo de conta
              _buildSeletorTipo(),
              const SizedBox(height: 16),

              // Se for nota de entrada, mostrar seletor
              if (_tipoSelecionado == TipoContaPagar.notaEntrada) ...[
                _buildSeletorNotaEntrada(),
                const SizedBox(height: 16),
              ],

              // Descrição
              _buildTextField(
                controller: _descricaoController,
                label: 'Descrição *',
                icon: Icons.description,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a descrição';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Categoria
              _buildSeletorCategoria(),
              const SizedBox(height: 16),

              // Fornecedor
              _buildTextField(
                controller: _fornecedorController,
                label: 'Fornecedor',
                icon: Icons.business,
                enabled: _tipoSelecionado != TipoContaPagar.notaEntrada || _notaSelecionada == null,
              ),
              const SizedBox(height: 16),

              // Valor
              _buildTextField(
                controller: _valorController,
                label: 'Valor *',
                icon: Icons.attach_money,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe o valor';
                  }
                  final valor = double.tryParse(value.replaceAll(',', '.'));
                  if (valor == null || valor <= 0) {
                    return 'Valor inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Data de vencimento
              _buildSeletorData(formatoData),
              const SizedBox(height: 16),

              // Recorrência (apenas para despesas fixas)
              if (_tipoSelecionado == TipoContaPagar.despesaFixa) ...[
                _buildRecorrencia(),
                const SizedBox(height: 16),
              ],

              // Observações
              _buildTextField(
                controller: _observacoesController,
                label: 'Observações',
                icon: Icons.note,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // Botão salvar
              ElevatedButton(
                onPressed: _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Salvar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeletorTipo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipo de Conta *',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TipoContaPagar.values.map((tipo) {
              final isSelected = _tipoSelecionado == tipo;
              return ChoiceChip(
                label: Text(tipo.nome),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _tipoSelecionado = tipo;
                      if (tipo != TipoContaPagar.notaEntrada) {
                        _notaSelecionada = null;
                      }
                    });
                  }
                },
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSeletorNotaEntrada() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nota de Entrada',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selecionarNotaEntrada,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _notaSelecionada?.numeroNota ?? 'Selecione uma nota de entrada',
                      style: TextStyle(
                        color: _notaSelecionada != null ? Colors.white : Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.blue, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeletorData(DateFormat formatoData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data de Vencimento *',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final data = await showDatePicker(
                context: context,
                initialDate: _dataVencimento,
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Colors.orange,
                        onPrimary: Colors.white,
                        surface: Color(0xFF1E1E2E),
                        onSurface: Colors.white,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (data != null) {
                setState(() => _dataVencimento = data);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.orange),
                  const SizedBox(width: 12),
                  Text(
                    formatoData.format(_dataVencimento),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecorrencia() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _recorrente,
                onChanged: (value) {
                  setState(() {
                    _recorrente = value ?? false;
                    if (!_recorrente) {
                      _intervaloRecorrencia = null;
                    } else {
                      _intervaloRecorrencia = 30;
                    }
                  });
                },
                activeColor: Colors.orange,
              ),
              const Text(
                'Conta Recorrente',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          if (_recorrente) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _intervaloRecorrencia,
              decoration: InputDecoration(
                labelText: 'Intervalo',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.repeat, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 7, child: Text('Semanal (7 dias)')),
                DropdownMenuItem(value: 15, child: Text('Quinzenal (15 dias)')),
                DropdownMenuItem(value: 30, child: Text('Mensal (30 dias)')),
                DropdownMenuItem(value: 60, child: Text('Bimestral (60 dias)')),
                DropdownMenuItem(value: 90, child: Text('Trimestral (90 dias)')),
              ],
              onChanged: (value) {
                setState(() => _intervaloRecorrencia = value);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeletorCategoria() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.category, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Categoria',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _mostrarCampoCategoria ? Icons.close : Icons.add,
                  color: Colors.orange,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _mostrarCampoCategoria = !_mostrarCampoCategoria;
                    if (!_mostrarCampoCategoria) {
                      _categoriaController.clear();
                    }
                  });
                },
                tooltip: _mostrarCampoCategoria ? 'Usar categoria existente' : 'Criar nova categoria',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mostrarCampoCategoria)
            // Campo de texto para criar nova categoria
            _buildTextField(
              controller: _categoriaController,
              label: 'Nova Categoria',
              icon: Icons.add_circle_outline,
              hint: 'Digite o nome da nova categoria...',
            )
          else
            // Dropdown com categorias existentes + opção de criar nova
            DropdownButtonFormField<String>(
              value: _categoriaController.text.isEmpty ? null : _categoriaController.text,
              decoration: InputDecoration(
                labelText: 'Selecione ou crie uma categoria',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.category, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.orange, width: 2),
                ),
              ),
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Nenhuma categoria'),
                ),
                ..._categoriasExistentes.map((cat) => DropdownMenuItem<String>(
                      value: cat,
                      child: Text(cat),
                    )),
                const DropdownMenuItem<String>(
                  value: '__nova__',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text('+ Criar Nova Categoria', style: TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == '__nova__') {
                  setState(() {
                    _mostrarCampoCategoria = true;
                    _categoriaController.clear();
                  });
                } else {
                  setState(() {
                    _categoriaController.text = value ?? '';
                  });
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
      ),
      validator: validator,
    );
  }
}


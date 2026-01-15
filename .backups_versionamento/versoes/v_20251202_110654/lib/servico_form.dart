import 'package:flutter/material.dart';
import 'package:sistema_exodo_novo/models/servico.dart';

class ServicoForm extends StatefulWidget {
  final Servico? servico;
  final Function(Servico) onSave;

  const ServicoForm({super.key, this.servico, required this.onSave});

  @override
  State<ServicoForm> createState() => _ServicoFormState();
}

class _ServicoFormState extends State<ServicoForm> {
  final _formKey = GlobalKey<FormState>();
  late String _nome;
  late String _descricao;
  late double _preco;
  late double _valorAdicional;
  late String _descricaoAdicional;
  late double _desconto;
  late String _descricaoDesconto;
  late DateTime? _dataInicio;
  late DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    _nome = widget.servico?.nome ?? '';
    _descricao = widget.servico?.descricao ?? '';
    _preco = widget.servico?.preco ?? 0.0;
    _valorAdicional = widget.servico?.valorAdicional ?? 0.0;
    _descricaoAdicional = widget.servico?.descricaoAdicional ?? '';
    _desconto = widget.servico?.desconto ?? 0.0;
    _descricaoDesconto = widget.servico?.descricaoDesconto ?? '';
    _dataInicio = widget.servico?.dataInicio;
    _dataFim = widget.servico?.dataFim;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final newServico = Servico(
        id: widget.servico?.id ?? '',
        nome: _nome,
        descricao: _descricao,
        preco: _preco,
        valorAdicional: _valorAdicional,
        descricaoAdicional: _descricaoAdicional,
        desconto: _desconto,
        descricaoDesconto: _descricaoDesconto,
        dataInicio: _dataInicio,
        dataFim: _dataFim,
        createdAt: widget.servico?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      widget.onSave(newServico);
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectDate(
    BuildContext context,
    DateTime? initialDate,
    Function(DateTime?) onDateSelected,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != initialDate) {
      onDateSelected(picked);
    }
  }

  Widget _buildDatePicker(
    BuildContext context,
    String label,
    DateTime? date,
    Function(DateTime?) onDateSelected,
  ) {
    return InkWell(
      onTap: () => _selectDate(context, date, onDateSelected),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              date == null
                  ? 'Selecione a data'
                  : '${date.day}/${date.month}/${date.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Icon(Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              initialValue: _nome,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor, insira o nome.';
                }
                return null;
              },
              onSaved: (value) => _nome = value!,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _descricao,
              decoration: const InputDecoration(labelText: 'Descrição'),
              maxLines: 3,
              onSaved: (value) => _descricao = value ?? '',
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _preco.toStringAsFixed(2),
              decoration: const InputDecoration(labelText: 'Preço Base'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || double.tryParse(value) == null) {
                  return 'Por favor, insira um preço válido.';
                }
                return null;
              },
              onSaved: (value) => _preco = double.parse(value!),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _valorAdicional.toStringAsFixed(2),
              decoration: const InputDecoration(
                labelText: 'Valor Adicional (Opcional)',
              ),
              keyboardType: TextInputType.number,
              onSaved: (value) =>
                  _valorAdicional = double.tryParse(value ?? '0.0') ?? 0.0,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _descricaoAdicional,
              decoration: const InputDecoration(
                labelText: 'Descrição do Valor Adicional',
              ),
              onSaved: (value) => _descricaoAdicional = value ?? '',
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _desconto.toStringAsFixed(2),
              decoration: const InputDecoration(
                labelText: 'Desconto Aplicado (Opcional)',
              ),
              keyboardType: TextInputType.number,
              onSaved: (value) =>
                  _desconto = double.tryParse(value ?? '0.0') ?? 0.0,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _descricaoDesconto,
              decoration: const InputDecoration(
                labelText: 'Descrição do Desconto',
              ),
              onSaved: (value) => _descricaoDesconto = value ?? '',
            ),
            const SizedBox(height: 10),
            _buildDatePicker(
              context,
              'Data de Início',
              _dataInicio,
              (date) => setState(() => _dataInicio = date),
            ),
            const SizedBox(height: 10),
            _buildDatePicker(
              context,
              'Data de Fim',
              _dataFim,
              (date) => setState(() => _dataFim = date),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submit,
              child: Text(
                widget.servico == null ? 'Cadastrar' : 'Salvar Alterações',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

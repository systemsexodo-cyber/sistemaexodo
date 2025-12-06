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

  @override
  void initState() {
    super.initState();
    _nome = widget.servico?.nome ?? '';
    _descricao = widget.servico?.descricao ?? '';
    _preco = widget.servico?.preco ?? 0.0;
    _valorAdicional = widget.servico?.valorAdicional ?? 0.0;
    _descricaoAdicional = widget.servico?.descricaoAdicional ?? '';
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
        descricaoAdicional: _descricaoAdicional.isEmpty ? null : _descricaoAdicional,
        createdAt: widget.servico?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      widget.onSave(newServico);
      Navigator.of(context).pop();
    }
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
              initialValue: _preco > 0 ? _preco.toStringAsFixed(2).replaceAll('.', ',') : '',
              decoration: const InputDecoration(labelText: 'Preço Base'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor, insira um preço válido.';
                }
                final parsed = double.tryParse(value.replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  return 'Por favor, insira um preço válido.';
                }
                return null;
              },
              onSaved: (value) {
                if (value != null && value.isNotEmpty) {
                  _preco = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                } else {
                  _preco = 0.0;
                }
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _valorAdicional > 0 ? _valorAdicional.toStringAsFixed(2).replaceAll('.', ',') : '',
              decoration: const InputDecoration(
                labelText: 'Valor Adicional (Opcional)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSaved: (value) {
                if (value != null && value.isNotEmpty) {
                  _valorAdicional = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                } else {
                  _valorAdicional = 0.0;
                }
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _descricaoAdicional,
              decoration: const InputDecoration(
                labelText: 'Descrição do Valor Adicional',
              ),
              onSaved: (value) => _descricaoAdicional = value ?? '',
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

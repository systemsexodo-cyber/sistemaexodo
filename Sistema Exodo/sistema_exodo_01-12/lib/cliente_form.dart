import 'package:flutter/material.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';

class ClienteForm extends StatefulWidget {
  final Cliente? cliente;
  final Function(Cliente) onSave;

  const ClienteForm({super.key, this.cliente, required this.onSave});

  @override
  State<ClienteForm> createState() => _ClienteFormState();
}

class _ClienteFormState extends State<ClienteForm> {
  final _formKey = GlobalKey<FormState>();
  late String _nome;
  late String _email;
  late String _telefone;
  late String _endereco;

  @override
  void initState() {
    super.initState();
    _nome = widget.cliente?.nome ?? '';
    _email = widget.cliente?.email ?? '';
    _telefone = widget.cliente?.telefone ?? '';
    _endereco = widget.cliente?.endereco ?? '';
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final newCliente = Cliente(
        id: widget.cliente?.id ?? '',
        nome: _nome,
        email: _email,
        telefone: _telefone,
        endereco: _endereco,
        createdAt: widget.cliente?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      widget.onSave(newCliente);
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
              initialValue: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor, insira o email.';
                }
                return null;
              },
              onSaved: (value) => _email = value!,
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _telefone,
              decoration: const InputDecoration(labelText: 'Telefone'),
              keyboardType: TextInputType.phone,
              onSaved: (value) => _telefone = value ?? '',
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _endereco,
              decoration: const InputDecoration(labelText: 'Endereço'),
              onSaved: (value) => _endereco = value ?? '',
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submit,
              child: Text(
                widget.cliente == null ? 'Cadastrar' : 'Salvar Alterações',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

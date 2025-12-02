import 'package:flutter/material.dart';
import '../models/cliente.dart';

class SelecionaClienteModal extends StatefulWidget {
  final List<Cliente> clientes;
  final Cliente? clienteAtual;
  const SelecionaClienteModal({super.key, required this.clientes, this.clienteAtual});

  @override
  State<SelecionaClienteModal> createState() => _SelecionaClienteModalState();
}

class _SelecionaClienteModalState extends State<SelecionaClienteModal> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final clientesFiltrados = widget.clientes.where((c) {
      if (_busca.isEmpty) return true;
      final termo = _busca.toLowerCase();
      return c.nome.toLowerCase().contains(termo) ||
          (c.telefone.contains(termo)) ||
          (c.cpfCnpj?.contains(termo) ?? false) ||
          (c.email?.toLowerCase().contains(termo) ?? false);
    }).toList();

    return Container(
      padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              hintStyle: TextStyle(color: Colors.white54),
              prefixIcon: Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _busca = v),
          ),
          SizedBox(height: 16),
          Expanded(
            child: clientesFiltrados.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum cliente encontrado',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: clientesFiltrados.length,
                    itemBuilder: (context, idx) {
                      final cliente = clientesFiltrados[idx];
                      final selecionado = widget.clienteAtual == cliente;
                      return ListTile(
                        leading: Icon(
                          cliente.tipoPessoa == TipoPessoa.juridica
                              ? Icons.business
                              : Icons.person,
                          color: Colors.white,
                        ),
                        title: Text(
                          cliente.nome,
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          cliente.telefone,
                          style: TextStyle(color: Colors.white54),
                        ),
                        selected: selecionado,
                        selectedTileColor: Colors.green.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onTap: () => Navigator.pop(context, cliente),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

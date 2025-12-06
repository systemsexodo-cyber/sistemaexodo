import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/widgets/pedido_form.dart';
import 'package:sistema_exodo_novo/widgets/custom_app_bar.dart';
import 'package:sistema_exodo_novo/theme.dart';

class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  void _showForm(BuildContext context, {Pedido? pedido}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: PedidoForm(
            pedido: pedido,
            onSave: (newPedido) {
              final service = p.Provider.of<DataService>(context, listen: false);
              if (pedido == null) {
                service.addPedido(newPedido);
              } else {
                service.updatePedido(newPedido);
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = p.Provider.of<DataService>(context);
    final pedidos = service.pedidos;
    return AppTheme.appBackground(
      child: Scaffold(
      appBar: CustomAppBar(
        title: 'Pedidos',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showForm(context),
          ),
        ],
      ),
      body: pedidos.isEmpty
          ? const Center(
              child: Text(
                'Nenhum pedido cadastrado.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.builder(
              itemCount: pedidos.length,
              itemBuilder: (context, index) {
                final pedido = pedidos[index];
                // Busca o cliente pelo ID para exibir o nome
                final cliente = service.clientes.firstWhere((c) => c.id == pedido.clienteId, orElse: () => service.clientes.first);
                return Card(
                  color: Theme.of(context).cardColor.withOpacity(0.8),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text('Pedido #${pedido.id.substring(0, 4)} - ${cliente.nome}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Total: R\$ ${pedido.total.toStringAsFixed(2)} | Itens: ${pedido.servicos.length}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showForm(context, pedido: pedido),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            p.Provider.of<DataService>(context, listen: false).deletePedido(pedido.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}

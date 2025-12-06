import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

class PedidoForm extends StatefulWidget {
  final Pedido? pedido;
  final Function(Pedido) onSave;

  const PedidoForm({super.key, this.pedido, required this.onSave});

  @override
  State<PedidoForm> createState() => _PedidoFormState();
}

class _PedidoFormState extends State<PedidoForm> {
  final _formKey = GlobalKey<FormState>();
  Cliente? _selectedCliente;
  String _status = 'Pendente';
  String _observacoes = '';
  List<ItemServico> _servicosSelecionados = [];

  @override
  void initState() {
    super.initState();
    if (widget.pedido != null) {
      // Lógica de edição: buscar cliente e serviços
      final service = p.Provider.of<DataService>(context, listen: false);
      _selectedCliente = service.clientes.firstWhere(
        (c) => c.id == widget.pedido!.clienteId,
      );
      _status = widget.pedido!.status;
      _observacoes = widget.pedido!.observacoes ?? '';
      _servicosSelecionados = widget.pedido!.servicos;
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate() && _selectedCliente != null) {
      _formKey.currentState!.save();

      // Cálculo do total (apenas serviços por enquanto)
      double total = _servicosSelecionados.fold(
        0.0,
        (sum, item) => sum + item.valor + item.valorAdicional,
      );

      final newPedido = Pedido(
        id: widget.pedido?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        numero: widget.pedido?.numero ?? 'PED-${DateTime.now().millisecondsSinceEpoch}',
        clienteId: _selectedCliente!.id,
        clienteNome: _selectedCliente!.nome,
        dataPedido: widget.pedido?.dataPedido ?? DateTime.now(),
        status: _status,
        total: total,
        observacoes: _observacoes,
        produtos: [], // Implementação de produtos omitida por enquanto
        servicos: _servicosSelecionados,
        createdAt: widget.pedido?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      widget.onSave(newPedido);
      Navigator.of(context).pop();
    }
  }

  void _editarValorAdicional(ItemServico item) {
    final valorAdicionalController = TextEditingController(
      text: item.valorAdicional > 0
          ? item.valorAdicional.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final descricaoAdicionalController = TextEditingController(
      text: item.descricaoAdicional ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Editar Valor Adicional - ${item.descricao}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: valorAdicionalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Valor Adicional (R\$)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descricaoAdicionalController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do Adicional (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  autofocus: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final novoValorAdicional = double.tryParse(
                      valorAdicionalController.text.trim().replaceAll(',', '.'),
                    ) ??
                    0.0;
                setState(() {
                  final index = _servicosSelecionados.indexOf(item);
                  if (index != -1) {
                    _servicosSelecionados[index] = ItemServico(
                      id: item.id,
                      descricao: item.descricao,
                      valor: item.valor,
                      valorAdicional: novoValorAdicional,
                      descricaoAdicional: descricaoAdicionalController.text.trim().isEmpty
                          ? null
                          : descricaoAdicionalController.text.trim(),
                    );
                  }
                });
                Navigator.of(context).pop();
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _addServico() {
    final service = p.Provider.of<DataService>(context, listen: false);
    final todosServicos = service.servicos;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Adicionar Serviço'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: todosServicos.length,
              itemBuilder: (context, index) {
                final servico = todosServicos[index];
                return ListTile(
                  title: Text(servico.nome),
                  subtitle: Text('R\$ ${servico.preco.toStringAsFixed(2)}'),
                  onTap: () {
                    setState(() {
                      _servicosSelecionados.add(
                        ItemServico(
                          id: servico.id,
                          descricao: servico.nome,
                          valor: servico.preco,
                          valorAdicional: 0.0,
                        ),
                      );
                    });
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = p.Provider.of<DataService>(context);
    final clientes = service.clientes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Seleção de Cliente
            DropdownButtonFormField<Cliente>(
              decoration: const InputDecoration(labelText: 'Cliente'),
              initialValue: _selectedCliente,
              items: clientes.map((cliente) {
                return DropdownMenuItem(
                  value: cliente,
                  child: Text(cliente.nome),
                );
              }).toList(),
              onChanged: (Cliente? newValue) {
                setState(() {
                  _selectedCliente = newValue;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'Selecione um cliente.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Serviços
            Text(
              'Serviços Lançados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ..._servicosSelecionados.map(
              (item) => ListTile(
                title: Text(item.descricao),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.descricaoAdicional != null && item.descricaoAdicional!.isNotEmpty) ...[
                      Text(
                        item.descricaoAdicional!,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      item.valorAdicional > 0
                          ? 'Preço: R\$ ${item.valor.toStringAsFixed(2)} + Adicional: R\$ ${item.valorAdicional.toStringAsFixed(2)} = R\$ ${(item.valor + item.valorAdicional).toStringAsFixed(2)}'
                          : 'Preço: R\$ ${item.valor.toStringAsFixed(2)}',
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _editarValorAdicional(item),
                      tooltip: 'Editar valor adicional',
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        setState(() {
                          _servicosSelecionados.remove(item);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _addServico,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Serviço'),
            ),
            const SizedBox(height: 20),

            // Status
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Status'),
              initialValue: _status,
              items: ['Pendente', 'Em Andamento', 'Concluído', 'Cancelado'].map(
                (status) {
                  return DropdownMenuItem(value: status, child: Text(status));
                },
              ).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _status = newValue!;
                });
              },
            ),
            const SizedBox(height: 10),

            // Observações
            TextFormField(
              initialValue: _observacoes,
              decoration: const InputDecoration(labelText: 'Observações'),
              maxLines: 3,
              onSaved: (value) => _observacoes = value ?? '',
            ),
            const SizedBox(height: 20),

            // Botão de Submissão
            Center(
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(
                  widget.pedido == null ? 'Criar Pedido' : 'Salvar Pedido',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

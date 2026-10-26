import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/pedido.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/servico.dart';
import 'package:sistema_exodo_novo/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

class LancamentoServicoForm extends StatefulWidget {
  final Pedido? pedido;
  final Function(Pedido) onSave;

  const LancamentoServicoForm({super.key, this.pedido, required this.onSave});

  @override
  State<LancamentoServicoForm> createState() => _LancamentoServicoFormState();
}

class _LancamentoServicoFormState extends State<LancamentoServicoForm> {
  final _formKey = GlobalKey<FormState>();
  Cliente? _clienteSelecionado;
  DateTime? _dataPedido;
  List<Servico> _servicosSelecionados = [];
  List<Produto> _produtosSelecionados = [];

  @override
  void initState() {
    super.initState();
    _clienteSelecionado = widget.pedido != null
        ? Cliente(
            id: widget.pedido!.clienteId,
            nome: widget.pedido!.clienteNome,
            email: '',
            telefone: '',
            endereco: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )
        : null;
    _dataPedido = widget.pedido?.dataPedido ?? DateTime.now();
    _servicosSelecionados =
        widget.pedido?.servicos
            .map(
              (s) => Servico(
                id: s.id,
                nome: s.descricao,
                preco: s.valor,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            )
            .toList() ??
        [];
    _produtosSelecionados =
        widget.pedido?.produtos
            .map(
              (p) => Produto(
                id: p.id,
                nome: p.nome,
                preco: p.preco,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            )
            .toList() ??
        [];
  }

  Future<void> _selectDate(
    BuildContext context,
    DateTime? initialDate,
    Function(DateTime) onDateSelected,
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

  void _submit() {
    if (_formKey.currentState!.validate() && _clienteSelecionado != null) {
      _formKey.currentState!.save();

      // Cálculo do valor total (serviços + produtos)
      final valorServicos = _servicosSelecionados.fold(
        0.0,
        (sum, s) => sum + s.preco + s.valorAdicional - s.desconto,
      );
      final valorProdutos = _produtosSelecionados.fold(
        0.0,
        (sum, p) => sum + p.preco,
      );
      final valorTotal = valorServicos + valorProdutos;

      // Monta lista de ItemPedido e ItemServico
      final itensProdutos = _produtosSelecionados
          .map(
            (p) => ItemPedido(
              id: p.id,
              nome: p.nome,
              quantidade: 1,
              preco: p.preco,
            ),
          )
          .toList();
      final itensServicos = _servicosSelecionados
          .map((s) => ItemServico(id: s.id, descricao: s.nome, valor: s.preco))
          .toList();

      final newPedido = Pedido(
        id:
            widget.pedido?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        clienteId: _clienteSelecionado!.id,
        clienteNome: _clienteSelecionado!.nome,
        dataPedido: _dataPedido ?? DateTime.now(),
        status: widget.pedido?.status ?? 'Pendente',
        total: valorTotal,
        observacoes: widget.pedido?.observacoes,
        produtos: itensProdutos,
        servicos: itensServicos,
        createdAt: widget.pedido?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      widget.onSave(newPedido);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = p.Provider.of<DataService>(context);
    final clientes = service.clientes;
    final produtos = service.produtos;
    final tiposServico = service.tiposServico;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 1. Seleção de Cliente (CORRETO)
            DropdownButtonFormField<Cliente>(
              decoration: const InputDecoration(labelText: 'Cliente'),
              initialValue: _clienteSelecionado,
              items: clientes.map((cliente) {
                return DropdownMenuItem(
                  value: cliente,
                  child: Text(cliente.nome),
                );
              }).toList(),
              onChanged: (Cliente? newValue) {
                setState(() {
                  _clienteSelecionado = newValue;
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

            // 2. Seleção de Data do Pedido
            InkWell(
              onTap: () => _selectDate(
                context,
                _dataPedido,
                (date) => setState(() => _dataPedido = date),
              ),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data do Pedido',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _dataPedido == null
                      ? 'Selecione a data'
                      : '${_dataPedido!.day}/${_dataPedido!.month}/${_dataPedido!.year}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Seleção de Serviços (usando tiposServico)
            Text(
              'Serviços a serem lançados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...tiposServico.map((servico) {
              final isSelected = _servicosSelecionados.any(
                (s) => s.id == servico.id,
              );
              return CheckboxListTile(
                title: Text(servico.nome),
                subtitle: Text('R\$ ${servico.preco.toStringAsFixed(2)}'),
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _servicosSelecionados.add(servico);
                    } else {
                      _servicosSelecionados.removeWhere(
                        (s) => s.id == servico.id,
                      );
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 20),

            // 3b. Seleção de Produtos
            Text(
              'Produtos a serem lançados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...produtos.map((produto) {
              final isSelected = _produtosSelecionados.contains(produto);
              return CheckboxListTile(
                title: Text(produto.nome),
                subtitle: Text('R\$ ${produto.preco.toStringAsFixed(2)}'),
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _produtosSelecionados.add(produto);
                    } else {
                      _produtosSelecionados.remove(produto);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 20),

            // 4. Botão de Submissão
            Center(
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(
                  widget.pedido == null ? 'Lançar Pedido' : 'Salvar Alterações',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

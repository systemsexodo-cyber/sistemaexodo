import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../produto.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/item_pedido.dart';

class AdicionarOrdemServicoPage extends StatefulWidget {
  const AdicionarOrdemServicoPage({super.key});

  @override
  State<AdicionarOrdemServicoPage> createState() =>
      _AdicionarOrdemServicoPageState();
}

class _AdicionarOrdemServicoPageState extends State<AdicionarOrdemServicoPage> {
  Cliente? _clienteSelecionado;
  final List<Produto> _produtosSelecionados = [];

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final clientes = service.clientes;
    final produtos = service.produtos;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Adicionar Ordem de Serviço'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Busca/Seleção de Cliente
                Autocomplete<Cliente>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return clientes;
                    }
                    return clientes.where(
                      (Cliente c) => c.nome.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      ),
                    );
                  },
                  displayStringForOption: (Cliente c) => c.nome,
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Cliente',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF181A1B),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white38,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        );
                      },
                  onSelected: (Cliente selection) {
                    setState(() {
                      _clienteSelecionado = selection;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Seleção de Produtos
                Text(
                  'Produtos:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                const SizedBox(height: 16),

                // Campos antigos
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Nome da Ordem',
                    prefixIcon: Icon(Icons.assignment),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    prefixIcon: Icon(Icons.description),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    if (_clienteSelecionado == null) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Atenção'),
                          content: const Text(
                            'Selecione um cliente antes de salvar.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    // Monta lista de ItemPedido
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

                    // Calcula total
                    final total = _produtosSelecionados.fold(
                      0.0,
                      (sum, p) => sum + p.preco,
                    );

                    // Cria Pedido
                    final pedido = Pedido(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      produtos: itensProdutos,
                      servicos: [],
                    );

                    // Salva Pedido
                    await Provider.of<DataService>(
                      context,
                      listen: false,
                    ).addPedido(pedido);

                    // Fecha tela
                    Navigator.of(context).pop();
                  },
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

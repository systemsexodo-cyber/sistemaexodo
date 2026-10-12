import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/cliente.dart';
import '../models/forma_pagamento.dart';
import '../models/produto.dart';
import '../models/venda_balcao.dart';
import '../services/data_service.dart';

class ConsumoEstoquePage extends StatefulWidget {
  const ConsumoEstoquePage({super.key});

  @override
  State<ConsumoEstoquePage> createState() => _ConsumoEstoquePageState();
}

class _ConsumoEstoquePageState extends State<ConsumoEstoquePage> {
  static const _tipos = [
    'Consumo da Loja',
    'Consumo de Funcionário',
    'Brinde',
  ];

  final _buscaController = TextEditingController();
  final _beneficiarioController = TextEditingController();
  final Map<String, double> _quantidades = {};
  String _tipo = _tipos.first;
  String _busca = '';
  Cliente? _cliente;
  bool _salvando = false;

  @override
  void dispose() {
    _buscaController.dispose();
    _beneficiarioController.dispose();
    super.dispose();
  }

  Future<void> _selecionarCliente(DataService dataService) async {
    final buscaController = TextEditingController();
    var alterouSelecao = false;
    final cliente = await showDialog<Cliente>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final termo = buscaController.text.trim().toLowerCase();
          final clientes = dataService.clientes.where((cliente) {
            return cliente.ativo &&
                (termo.isEmpty ||
                    cliente.nome.toLowerCase().contains(termo) ||
                    cliente.telefone.toLowerCase().contains(termo));
          }).take(100).toList();

          return AlertDialog(
            title: const Text('Vincular cliente'),
            content: SizedBox(
              width: 420,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: buscaController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar cliente',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_off_outlined),
                          title: const Text('Sem cliente'),
                          onTap: () {
                            alterouSelecao = true;
                            Navigator.pop(dialogContext);
                          },
                        ),
                        ...clientes.map(
                          (cliente) => ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(cliente.nome),
                            subtitle: Text(cliente.telefone),
                            onTap: () {
                              alterouSelecao = true;
                              Navigator.pop(dialogContext, cliente);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
    buscaController.dispose();
    if (!mounted || !alterouSelecao) return;
    setState(() => _cliente = cliente);
  }

  void _adicionarProduto(Produto produto) {
    setState(() {
      _quantidades.update(produto.id, (quantidade) => quantidade + 1,
          ifAbsent: () => 1);
    });
  }

  void _alterarQuantidade(String produtoId, double delta) {
    setState(() {
      final proxima = (_quantidades[produtoId] ?? 0) + delta;
      if (proxima <= 0) {
        _quantidades.remove(produtoId);
      } else {
        _quantidades[produtoId] = proxima;
      }
    });
  }

  Future<void> _registrar(DataService dataService) async {
    if (_quantidades.isEmpty || _salvando) return;
    if (_tipo == 'Consumo de Funcionário' &&
        _beneficiarioController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o funcionário/beneficiário.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final produtos = {
        for (final produto in dataService.produtos) produto.id: produto,
      };
      final itens = _quantidades.entries.map((entry) {
        final produto = produtos[entry.key]!;
        return ItemVendaBalcao(
          id: produto.id,
          nome: produto.nome,
          precoUnitario: 0,
          quantidade: entry.value,
          unidadeVenda: produto.unidadeVenda,
          quantidadeBaixa: produto.fatorBaixaEstoque,
        );
      }).toList();
      final observacoes = _beneficiarioController.text.trim().isEmpty
          ? null
          : 'Funcionário/beneficiário: ${_beneficiarioController.text.trim()}';
      final agora = DateTime.now();
      final venda = VendaBalcao(
        id: const Uuid().v4(),
        numero: await dataService.getProximoNumeroVendaSeguro(),
        dataVenda: agora,
        clienteId: _cliente?.id,
        clienteNome: _cliente?.nome,
        clienteTelefone: _cliente?.telefone,
        itens: itens,
        tipoPagamento: TipoPagamento.outro,
        pagamentos: [
          PagamentoPedido(
            id: const Uuid().v4(),
            tipo: TipoPagamento.outro,
            nomeForma: 'Bônus consumo',
            valor: 0,
            recebido: true,
            dataRecebimento: agora,
            observacao: _tipo,
          ),
        ],
        valorTotal: 0,
        valorRecebido: 0,
        operador: dataService.responsavelAtivo,
        origem: _tipo,
        observacoes: observacoes,
      );

      await dataService.addVendaBalcao(venda);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível registrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _buildProdutos(DataService dataService) {
    final termo = _busca.trim().toLowerCase();
    final produtos = dataService.produtos
        .where((produto) => produto.ativo && produto.nome.toLowerCase().contains(termo))
        .take(200)
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _buscaController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar produto',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _busca = value),
            ),
          ),
          Expanded(
            child: produtos.isEmpty
                ? const Center(child: Text('Nenhum produto encontrado.'))
                : ListView.builder(
                    itemCount: produtos.length,
                    itemBuilder: (context, index) {
                      final produto = produtos[index];
                      return ListTile(
                        dense: true,
                        title: Text(produto.nome),
                        subtitle: Text(
                          'Estoque: ${produto.estoque.toStringAsFixed(2)} ${produto.unidade}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Adicionar item',
                          onPressed: () => _adicionarProduto(produto),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        onTap: () => _adicionarProduto(produto),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarrinho(DataService dataService) {
    final produtos = {
      for (final produto in dataService.produtos) produto.id: produto,
    };
    final itens = _quantidades.entries.toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Itens para baixar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text('${itens.length} produto(s)'),
              ],
            ),
          ),
          Expanded(
            child: itens.isEmpty
                ? const Center(child: Text('Adicione produtos à lista.'))
                : ListView.builder(
                    itemCount: itens.length,
                    itemBuilder: (context, index) {
                      final entry = itens[index];
                      final produto = produtos[entry.key];
                      if (produto == null) return const SizedBox.shrink();
                      return ListTile(
                        dense: true,
                        title: Text(produto.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Quantidade: ${entry.value}'),
                        trailing: SizedBox(
                          width: 112,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Diminuir quantidade',
                                onPressed: () => _alterarQuantidade(entry.key, -1),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              IconButton(
                                tooltip: 'Aumentar quantidade',
                                onPressed: () => _alterarQuantidade(entry.key, 1),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: itens.isEmpty || _salvando ? null : () => _registrar(dataService),
              icon: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.inventory_2_outlined),
              label: Text(_salvando ? 'Registrando...' : 'Registrar baixa de estoque'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataService = context.watch<DataService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Consumo e brindes')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      value: _tipo,
                      decoration: const InputDecoration(labelText: 'Tipo de saída'),
                      items: _tipos
                          .map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo)))
                          .toList(),
                      onChanged: (tipo) => setState(() => _tipo = tipo ?? _tipo),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _selecionarCliente(dataService),
                    icon: const Icon(Icons.person_search_outlined),
                    label: Text(_cliente?.nome ?? 'Vincular cliente'),
                  ),
                  if (_cliente != null)
                    IconButton(
                      tooltip: 'Remover cliente',
                      onPressed: () => setState(() => _cliente = null),
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _beneficiarioController,
                      decoration: InputDecoration(
                        labelText: _tipo == 'Consumo de Funcionário'
                            ? 'Funcionário (obrigatório)'
                            : 'Funcionário/beneficiário (opcional)',
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 850) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: _buildProdutos(dataService)),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: _buildCarrinho(dataService)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(child: _buildProdutos(dataService)),
                        const SizedBox(height: 8),
                        SizedBox(height: 260, child: _buildCarrinho(dataService)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

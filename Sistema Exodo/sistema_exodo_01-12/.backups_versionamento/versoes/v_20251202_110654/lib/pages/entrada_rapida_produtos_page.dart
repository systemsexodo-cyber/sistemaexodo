import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../services/codigo_service.dart';
import '../custom_app_bar.dart';
import '../theme.dart';

class EntradaRapidaProdutosPage extends StatefulWidget {
  const EntradaRapidaProdutosPage({super.key});

  @override
  State<EntradaRapidaProdutosPage> createState() =>
      _EntradaRapidaProdutosPageState();
}

class _EntradaRapidaProdutosPageState extends State<EntradaRapidaProdutosPage> {
  final List<_ProdutoRapido> _produtos = [];
  final ScrollController _scrollController = ScrollController();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    // Iniciar com 3 linhas vazias
    _adicionarLinhas(3);
  }

  void _adicionarLinhas(int quantidade) {
    final service = Provider.of<DataService>(context, listen: false);
    final codigosExistentes = service.produtos.map((p) => p.codigo).toList();

    // Adicionar códigos já na lista
    for (var p in _produtos) {
      if (p.codigo.isNotEmpty) {
        codigosExistentes.add(p.codigo);
      }
    }

    for (int i = 0; i < quantidade; i++) {
      final proximoCodigo = CodigoService.gerarProximoUltimo(codigosExistentes);
      codigosExistentes.add(proximoCodigo);

      _produtos.add(
        _ProdutoRapido(
          codigo: proximoCodigo,
          nomeController: TextEditingController(),
          precoController: TextEditingController(),
          estoqueController: TextEditingController(text: '0'),
          unidade: 'UN',
          grupo: 'Sem Grupo',
        ),
      );
    }
    setState(() {});

    // Scroll para o final
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removerLinha(int index) {
    setState(() {
      _produtos[index].nomeController.dispose();
      _produtos[index].precoController.dispose();
      _produtos[index].estoqueController.dispose();
      _produtos.removeAt(index);
    });
  }

  void _limparTudo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Limpar tudo?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Isso vai remover todos os produtos não salvos.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                for (var p in _produtos) {
                  p.nomeController.dispose();
                  p.precoController.dispose();
                  p.estoqueController.dispose();
                }
                _produtos.clear();
              });
              _adicionarLinhas(3);
            },
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  Future<void> _salvarTodos() async {
    // Filtrar apenas produtos com nome preenchido
    final produtosValidos = _produtos
        .where((p) => p.nomeController.text.trim().isNotEmpty)
        .toList();

    if (produtosValidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum produto para salvar. Preencha pelo menos o nome.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    final service = Provider.of<DataService>(context, listen: false);
    int salvos = 0;
    int erros = 0;

    for (var p in produtosValidos) {
      try {
        final preco =
            double.tryParse(p.precoController.text.replaceAll(',', '.')) ?? 0.0;
        final estoque = int.tryParse(p.estoqueController.text) ?? 0;

        final produto = Produto(
          id: UniqueKey().toString(),
          codigo: p.codigo,
          nome: p.nomeController.text.trim(),
          descricao: '',
          unidade: p.unidade,
          grupo: p.grupo,
          preco: preco,
          estoque: estoque,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await service.addProduto(produto);
        salvos++;
      } catch (e) {
        erros++;
      }
    }

    setState(() => _salvando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ $salvos produtos salvos${erros > 0 ? ' ($erros erros)' : ''}',
          ),
          backgroundColor: erros > 0 ? Colors.orange : Colors.green,
        ),
      );

      if (salvos > 0) {
        // Limpar produtos salvos e adicionar novas linhas
        setState(() {
          for (var p in produtosValidos) {
            final index = _produtos.indexOf(p);
            if (index != -1) {
              p.nomeController.dispose();
              p.precoController.dispose();
              p.estoqueController.dispose();
              _produtos.removeAt(index);
            }
          }
        });

        if (_produtos.isEmpty) {
          _adicionarLinhas(3);
        }
      }
    }
  }

  @override
  void dispose() {
    for (var p in _produtos) {
      p.nomeController.dispose();
      p.precoController.dispose();
      p.estoqueController.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final produtosPreenchidos = _produtos
        .where((p) => p.nomeController.text.trim().isNotEmpty)
        .length;

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Entrada Rápida',
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              tooltip: 'Limpar tudo',
              onPressed: _limparTudo,
            ),
          ],
        ),
        body: Column(
          children: [
            // Cabeçalho com instruções
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade600],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cadastro Rápido de Produtos',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Preencha nome e preço. Código gerado automaticamente.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$produtosPreenchidos itens',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cabeçalho da tabela
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text('Código', style: _headerStyle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text('Nome do Produto', style: _headerStyle),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Text('Preço', style: _headerStyle),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: Text('Estoque', style: _headerStyle),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Lista de produtos
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900.withOpacity(0.5),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _produtos.length,
                  itemBuilder: (context, index) {
                    final produto = _produtos[index];
                    final temNome = produto.nomeController.text
                        .trim()
                        .isNotEmpty;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: temNome
                            ? Colors.green.withOpacity(0.1)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade700,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Código (readonly)
                          Container(
                            width: 70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade900.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              produto.codigo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nome
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: produto.nomeController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Digite o nome...',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Preço
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: produto.precoController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d,.]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                                prefixText: 'R\$ ',
                                prefixStyle: TextStyle(
                                  color: Colors.green.shade300,
                                  fontSize: 12,
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Estoque
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: produto.estoqueController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Botão remover
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Colors.red.shade300,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: () => _removerLinha(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Botões de ação
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Botão adicionar linhas
                  OutlinedButton.icon(
                    onPressed: () => _adicionarLinhas(5),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('+5 linhas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _adicionarLinhas(10),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('+10'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Botão salvar
                  ElevatedButton.icon(
                    onPressed: _salvando ? null : _salvarTodos,
                    icon: _salvando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 22),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : 'SALVAR TODOS ($produtosPreenchidos)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: produtosPreenchidos > 0
                          ? Colors.green.shade700
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _headerStyle => TextStyle(
    color: Colors.grey.shade300,
    fontWeight: FontWeight.bold,
    fontSize: 11,
  );
}

class _ProdutoRapido {
  String codigo;
  final TextEditingController nomeController;
  final TextEditingController precoController;
  final TextEditingController estoqueController;
  String unidade;
  String grupo;

  _ProdutoRapido({
    required this.codigo,
    required this.nomeController,
    required this.precoController,
    required this.estoqueController,
    required this.unidade,
    required this.grupo,
  });
}

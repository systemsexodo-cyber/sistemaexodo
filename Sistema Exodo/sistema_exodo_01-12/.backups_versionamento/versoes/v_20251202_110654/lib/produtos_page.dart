import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/produto.dart';
import '../services/data_service.dart';
import '../produto_form.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  String _busca = '';
  final _buscaController = TextEditingController();

  /// BUSCA INTELIGENTE - encontra APENAS palavras que COMEÇAM com o termo digitado
  List<Produto> _filtrarProdutos(List<Produto> produtos) {
    if (_busca.isEmpty) return produtos;

    final buscaLower = _busca.toLowerCase().trim();

    // Se a busca tem menos de 2 caracteres, não filtra
    if (buscaLower.length < 2) return produtos;

    // Se busca é só números
    if (RegExp(r'^[0-9]+$').hasMatch(buscaLower)) {
      return produtos.where((p) {
        if (p.codigo != null) {
          final num = p.codigo!.replaceAll(RegExp(r'[^0-9]'), '');
          if (num == buscaLower) return true;
        }
        if (p.codigoBarras != null && p.codigoBarras!.startsWith(buscaLower)) {
          return true;
        }
        return false;
      }).toList();
    }

    // Se começa com "prd"
    if (buscaLower.startsWith('prd')) {
      return produtos.where((p) {
        return p.codigo != null &&
            p.codigo!.toLowerCase().startsWith(buscaLower);
      }).toList();
    }

    // BUSCA POR NOME - SOMENTE palavras que COMEÇAM com o termo
    return produtos.where((p) {
      // Pega só as palavras do nome (sem números)
      final palavras = p.nome
          .toLowerCase()
          .replaceAll(RegExp(r'[0-9]+'), ' ') // Remove números
          .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç\s]'), ' ') // Remove símbolos
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 2)
          .toList();

      // Verifica se ALGUMA palavra COMEÇA com a busca
      return palavras.any((palavra) => palavra.startsWith(buscaLower));
    }).toList();
  }

  // Função para destacar texto buscado
  Widget _highlightText(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontWeight: FontWeight.w500));
    }

    final queryLower = query.toLowerCase();

    // Encontra onde a busca aparece no início de uma palavra
    final palavras = text.split(RegExp(r'(\s+)'));
    final resultado = <TextSpan>[];

    for (int i = 0; i < palavras.length; i++) {
      final palavra = palavras[i];
      if (palavra.toLowerCase().startsWith(queryLower)) {
        // Destaca a parte que corresponde
        resultado.add(
          TextSpan(
            text: palavra.substring(0, query.length),
            style: const TextStyle(
              backgroundColor: Colors.yellow,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        );
        resultado.add(TextSpan(text: palavra.substring(query.length)));
      } else {
        resultado.add(TextSpan(text: palavra));
      }
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        children: resultado,
      ),
    );
  }

  void _showForm(BuildContext context, {Produto? produto}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ProdutoServicoForm(
            item: produto,
            onSave: (newProduto) {
              final service = Provider.of<DataService>(context, listen: false);
              if (produto == null) {
                service.addProduto(newProduto);
              } else {
                service.updateProduto(newProduto);
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final produtos = _filtrarProdutos(service.produtos);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 28),
            onPressed: () => _showForm(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Campo de busca com lupa
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16, right: 12),
                  child: Icon(Icons.search, color: Colors.blue, size: 24),
                ),
                Expanded(
                  child: TextField(
                    controller: _buscaController,
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'Buscar produtos...',
                      hintStyle: TextStyle(color: Colors.black54, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _busca = value;
                      });
                    },
                  ),
                ),
                if (_buscaController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.black54),
                    onPressed: () {
                      _buscaController.clear();
                      setState(() {
                        _busca = '';
                      });
                    },
                  ),
              ],
            ),
          ),
          // Lista de produtos
          Expanded(
            child: produtos.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum produto cadastrado.',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: produtos.length,
                    itemBuilder: (context, index) {
                      final produto = produtos[index];
                      return Card(
                        color: Theme.of(context).cardColor.withOpacity(0.8),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: _highlightText(produto.nome, _busca),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (produto.codigo != null &&
                                  produto.codigo!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade700,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '📦 CÓDIGO: ${produto.codigo}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (produto.codigoBarras != null &&
                                  produto.codigoBarras!.isNotEmpty)
                                Text(
                                  '🔖 Barras: ${produto.codigoBarras}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              Text(
                                'R\$ ${produto.preco.toStringAsFixed(2)} | Estoque: ${produto.estoque}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _showForm(context, produto: produto),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  Provider.of<DataService>(
                                    context,
                                    listen: false,
                                  ).deleteProduto(produto.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

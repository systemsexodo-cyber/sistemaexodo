import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/produto.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../produto_form.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  String _busca = '';
  final _buscaController = TextEditingController();
  int _updateCounter = 0; // Forçar rebuild quando mudar

  /// BUSCA INTELIGENTE - encontra APENAS palavras que COMEÇAM com o termo digitado
  List<Produto> _filtrarProdutos(List<Produto> produtos) {
    // Sempre retornar uma NOVA lista para garantir que o Flutter detecte mudanças
    final produtosList = List<Produto>.from(produtos);
    
    if (_busca.isEmpty) return produtosList;

    final buscaLower = _busca.toLowerCase().trim();

    // Se a busca tem menos de 2 caracteres, não filtra
    if (buscaLower.length < 2) return produtosList;

    // Se busca é só números
    if (RegExp(r'^[0-9]+$').hasMatch(buscaLower)) {
      return produtosList.where((p) {
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
      return produtosList.where((p) {
        return p.codigo != null &&
            p.codigo!.toLowerCase().startsWith(buscaLower);
      }).toList();
    }

    // BUSCA POR NOME - SOMENTE palavras que COMEÇAM com o termo
    return produtosList.where((p) {
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
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final produtoOriginal = produto;

    // Obter usuário atual para auditoria
    final usuario = authService.usuarioAtual;
    final usuarioId = usuario?.id;
    final usuarioNome = usuario?.nome ?? 'Sistema';
    final usuarioEmail = usuario?.email;

    // Callback assíncrono: aguarda a persistência antes de rebuildar
    Future<void> onProdutoSalvo(Produto newProduto) async {
      debugPrint('>>> [ProdutosPage] CALLBACK: Produto salvo - ${newProduto.nome}: R\$ ${newProduto.preco}');

      // Atualizar no DataService e AGUARDAR para garantir que _produtos já foi atualizado
      if (produtoOriginal == null) {
        await dataService.addProduto(
          newProduto,
          usuarioId: usuarioId,
          usuarioNome: usuarioNome,
          usuarioEmail: usuarioEmail,
        );
      } else {
        await dataService.updateProduto(
          newProduto,
          usuarioId: usuarioId,
          usuarioNome: usuarioNome,
          usuarioEmail: usuarioEmail,
        );
      }

      // Rebuild único após a operação completar
      if (mounted) {
        setState(() {
          _updateCounter++;
          debugPrint('>>> [ProdutosPage] REBUILD após save - counter: $_updateCounter');
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ProdutoServicoForm(
            item: produto,
            onSave: (newProduto) {
              // Fechar modal primeiro
              Navigator.of(ctx).pop();

              // Chamar callback após o frame de fechamento do modal
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onProdutoSalvo(newProduto);
              });
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
    
    // Log para debug - mostrar primeiro produto
    if (produtos.isNotEmpty) {
      final p = produtos.first;
      debugPrint('>>> [ProdutosPage BUILD] counter:$_updateCounter | Total: ${produtos.length} | Primeiro: ${p.nome} (R\$ ${p.preco})');
    }
    
    return Scaffold(
      key: ValueKey('produtos_page_$_updateCounter'), // Forçar reconstrução completa
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
                    key: ValueKey('lista_$_updateCounter'), // Forçar reconstrução completa quando counter mudar
                    itemCount: produtos.length,
                    itemBuilder: (context, index) {
                      final produto = produtos[index];
                      // Buscar produto atualizado direto do DataService (garante preço mais recente)
                      final produtoAtualizado = service.produtos.firstWhere(
                        (p) => p.id == produto.id,
                        orElse: () => produto,
                      );
                      
                      // Log especial para produto "Banho"
                      if (produtoAtualizado.nome == 'Banho') {
                        debugPrint('>>> [BANHO-UI] Card #$index rebuild: R\$ ${produtoAtualizado.preco} (counter: $_updateCounter)');
                      }
                      
                      debugPrint('>>> [ProdutosPage ITEM $index] ${produtoAtualizado.nome}: R\$ ${produtoAtualizado.preco}');
                      return Card(
                        key: ValueKey('${produtoAtualizado.id}_${produtoAtualizado.preco}'), // Key muda quando preço muda
                        color: Theme.of(context).cardColor.withOpacity(0.8),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: _highlightText(produtoAtualizado.nome, _busca),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (produtoAtualizado.codigo != null &&
                                  produtoAtualizado.codigo!.isNotEmpty)
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
                                    '📦 CÓDIGO: ${produtoAtualizado.codigo}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (produtoAtualizado.codigoBarras != null &&
                                  produtoAtualizado.codigoBarras!.isNotEmpty)
                                Text(
                                  '🔖 Barras: ${produtoAtualizado.codigoBarras}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              Row(
                                children: [
                                  Text(
                                    'R\$ ${produtoAtualizado.preco.toStringAsFixed(2)} | Estoque: ${produtoAtualizado.estoque}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: (produtoAtualizado.estoque <= produtoAtualizado.estoqueMinimo && produtoAtualizado.estoqueMinimo > 0) 
                                          ? Colors.redAccent 
                                          : Colors.white70,
                                      fontWeight: (produtoAtualizado.estoque <= produtoAtualizado.estoqueMinimo && produtoAtualizado.estoqueMinimo > 0)
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (produtoAtualizado.estoque <= produtoAtualizado.estoqueMinimo && produtoAtualizado.estoqueMinimo > 0)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _showForm(context, produto: produtoAtualizado),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () async {
                                  final confirmar = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Confirmar Exclusão'),
                                      content: Text('Tem certeza que deseja excluir o produto "${produtoAtualizado.nome}"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancelar'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Excluir'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true && mounted) {
                                    final authService = Provider.of<AuthService>(context, listen: false);
                                    final usuario = authService.usuarioAtual;
                                    
                                    await Provider.of<DataService>(
                                      context,
                                      listen: false,
                                    ).deleteProduto(
                                      produtoAtualizado.id,
                                      usuarioId: usuario?.id,
                                      usuarioNome: usuario?.nome ?? 'Sistema',
                                      usuarioEmail: usuario?.email,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Produto "${produtoAtualizado.nome}" excluído'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
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

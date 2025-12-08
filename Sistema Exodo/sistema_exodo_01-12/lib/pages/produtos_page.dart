import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../produto_form.dart' as produto_form;
import '../custom_app_bar.dart';
import '../theme.dart';
import 'entrada_rapida_produtos_page.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  String _busca = '';
  final _buscaController = TextEditingController();

  // Para edição rápida
  String? _editandoId;
  final _precoController = TextEditingController();
  final _estoqueController = TextEditingController();

  // Filtro de estoque
  int? _filtroEstoque; // null = todos, 10, 20, 30

  // ==================== PAGINAÇÃO INTELIGENTE ====================
  static const int _itensPorPagina = 20; // Quantidade por vez
  int _itensVisiveis = 20; // Total visível atual
  final ScrollController _scrollController = ScrollController();
  bool _carregando = false;

  // Modos de visualização
  final bool _modoCompacto = false; // true = lista compacta, false = cards

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _buscaController.dispose();
    _precoController.dispose();
    _estoqueController.dispose();
    super.dispose();
  }

  // Lazy loading - carrega mais quando chega perto do fim
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _carregarMais();
    }
  }

  void _carregarMais() {
    if (!_carregando) {
      setState(() {
        _carregando = true;
      });

      // Simula um pequeno delay para não travar a UI
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _itensVisiveis += _itensPorPagina;
            _carregando = false;
          });
        }
      });
    }
  }

  // Reset paginação quando busca/filtro muda
  void _resetPaginacao() {
    _itensVisiveis = _itensPorPagina;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _iniciarEdicaoRapida(Produto produto) {
    setState(() {
      _editandoId = produto.id;
      _precoController.text = produto.preco.toStringAsFixed(2);
      _estoqueController.text = produto.estoque.toString();
    });
  }

  void _salvarEdicaoRapida(Produto produto) {
    final service = Provider.of<DataService>(context, listen: false);

    final novoPreco =
        double.tryParse(_precoController.text.replaceAll(',', '.')) ??
        produto.preco;
    final novoEstoque =
        int.tryParse(_estoqueController.text) ?? produto.estoque;

    final produtoAtualizado = Produto(
      id: produto.id,
      codigo: produto.codigo,
      codigoBarras: produto.codigoBarras,
      nome: produto.nome,
      descricao: produto.descricao,
      unidade: produto.unidade,
      grupo: produto.grupo,
      preco: novoPreco,
      estoque: novoEstoque,
      createdAt: produto.createdAt,
      updatedAt: DateTime.now(),
      // Preservar dados de promoção
      precoPromocional: produto.precoPromocional,
      promocaoInicio: produto.promocaoInicio,
      promocaoFim: produto.promocaoFim,
    );

    service.updateProduto(produtoAtualizado);

    setState(() {
      _editandoId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${produto.nome} atualizado!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _cancelarEdicao() {
    setState(() {
      _editandoId = null;
    });
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
          child: produto_form.ProdutoServicoForm(
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
    // Usar listen: true para atualizar automaticamente quando os dados mudarem
    final service = Provider.of<DataService>(context, listen: true);

    // Filtrar produtos baseado na busca e estoque
    List<Produto> produtosFiltrados = service.produtos.where((p) {
      // Primeiro aplicar filtro de estoque
      if (_filtroEstoque != null && p.estoque >= _filtroEstoque!) {
        return false;
      }

      if (_busca.isEmpty) return true;

      final buscaLower = _busca.toLowerCase().trim();
      final ehNumero = RegExp(r'^[0-9]+$').hasMatch(buscaLower);

      // Se for número, permite busca com 1 caractere
      // Se for texto, mínimo 2 caracteres
      if (!ehNumero && buscaLower.length < 2) return true;

      // BUSCA POR NÚMERO DO CÓDIGO - EXATA (ex: "1" encontra APENAS COD-1, não COD-10)
      if (ehNumero && p.codigo != null) {
        final numCodigo = p.codigo!.replaceAll(RegExp(r'[^0-9]'), '');
        if (numCodigo == buscaLower) return true;
        // Não continua buscando em outros lugares se for número
        return false;
      }

      // BUSCA POR CÓDIGO COMPLETO (cod-1, cod-2, etc) - só para texto
      if (!ehNumero && p.codigo != null) {
        final codigoLower = p.codigo!.toLowerCase();
        if (codigoLower.startsWith(buscaLower)) return true;
      }

      // BUSCA POR NOME - SOMENTE palavras que COMEÇAM com o termo
      if (!ehNumero) {
        final palavras = p.nome
            .toLowerCase()
            .replaceAll(RegExp(r'[0-9]+'), ' ')
            .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 2)
            .toList();

        return palavras.any((palavra) => palavra.startsWith(buscaLower));
      }

      return false;
    }).toList();

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Produtos',
          actions: [
            // Botão entrada rápida
            IconButton(
              icon: Icon(
                Icons.playlist_add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              tooltip: 'Entrada Rápida',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EntradaRapidaProdutosPage(),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () => _showForm(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // Campo de busca com lupa - tema azul
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D47A1).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 20, right: 12),
                    child: Icon(Icons.search, color: Colors.white, size: 28),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar: código, número, grupo, nome...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
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
                      icon: Icon(
                        Icons.clear,
                        color: Colors.white.withOpacity(0.8),
                        size: 24,
                      ),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {
                          _busca = '';
                        });
                      },
                    )
                  else
                    const SizedBox(width: 12),
                  // Botão de filtro de estoque (dropdown)
                  PopupMenuButton<int?>(
                    icon: Icon(
                      Icons.filter_list,
                      color: _filtroEstoque != null
                          ? Colors.amber
                          : Colors.white,
                      size: 24,
                    ),
                    tooltip: 'Filtrar por estoque',
                    color: Colors.grey.shade900,
                    onSelected: (valor) {
                      setState(() {
                        _filtroEstoque = valor;
                      });
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: null,
                        child: Row(
                          children: [
                            Icon(
                              Icons.all_inclusive,
                              color: _filtroEstoque == null
                                  ? Colors.blue
                                  : Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Todos',
                              style: TextStyle(
                                color: _filtroEstoque == null
                                    ? Colors.blue
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 10,
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning,
                              color: _filtroEstoque == 10
                                  ? Colors.red
                                  : Colors.red.shade300,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estoque < 10',
                              style: TextStyle(
                                color: _filtroEstoque == 10
                                    ? Colors.red
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 20,
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: _filtroEstoque == 20
                                  ? Colors.orange
                                  : Colors.orange.shade300,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estoque < 20',
                              style: TextStyle(
                                color: _filtroEstoque == 20
                                    ? Colors.orange
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 30,
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: _filtroEstoque == 30
                                  ? Colors.amber
                                  : Colors.amber.shade300,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estoque < 30',
                              style: TextStyle(
                                color: _filtroEstoque == 30
                                    ? Colors.amber
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Indicador de filtro ativo
            if (_filtroEstoque != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _filtroEstoque == 10
                      ? Colors.red.shade900
                      : _filtroEstoque == 20
                      ? Colors.orange.shade900
                      : Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Estoque < $_filtroEstoque',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _filtroEstoque = null),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // Lista de produtos
            Expanded(
              child: produtosFiltrados.isEmpty
                  ? Center(
                      child: Text(
                        _filtroEstoque != null
                            ? 'Nenhum produto com estoque menor que $_filtroEstoque'
                            : 'Nenhum produto encontrado.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: produtosFiltrados.length,
                      itemBuilder: (context, index) {
                        final produto = produtosFiltrados[index];
                        final estaEditando = _editandoId == produto.id;
                        final service = Provider.of<DataService>(
                          context,
                          listen: false,
                        );
                        final historico =
                            service.estoqueHistorico
                                .where((h) => h.produtoId == produto.id)
                                .toList()
                              ..sort((a, b) => b.data.compareTo(a.data));

                        return InkWell(
                          onTap: () => _iniciarEdicaoRapida(produto),
                          onDoubleTap: () =>
                              _showForm(context, produto: produto),
                          child: Card(
                            color: estaEditando
                                ? Colors.blue.shade900.withOpacity(0.9)
                                : Theme.of(context).cardColor.withOpacity(0.8),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Linha superior: Código + Nome
                                  Row(
                                    children: [
                                      if (produto.codigo != null &&
                                          produto.codigo!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade700,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            produto.codigo!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          produto.nome,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                        ),
                                      ),
                                      // Botões de ação
                                      if (!estaEditando) ...[
                                        IconButton(
                                          icon: Icon(
                                            Icons.edit,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                                .withOpacity(0.7),
                                            size: 20,
                                          ),
                                          onPressed: () => _showForm(
                                            context,
                                            produto: produto,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            final confirmar = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Confirmar Exclusão'),
                                                content: Text('Tem certeza que deseja excluir o produto "${produto.nome}"?'),
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
                                              Provider.of<DataService>(
                                                context,
                                                listen: false,
                                              ).deleteProduto(produto.id);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Produto "${produto.nome}" excluído'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Linha inferior: Preço e Estoque (editáveis ou não)
                                  if (estaEditando) ...[
                                    // MODO EDIÇÃO RÁPIDA - Layout compacto
                                    const SizedBox(height: 4),
                                    // Campo Preço
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.attach_money,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'R\$',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2D2D2D),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.orange.shade600,
                                                  width: 1,
                                                ),
                                              ),
                                              child: TextField(
                                                controller: _precoController,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 8,
                                                          ),
                                                    ),
                                                autofocus: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Campo Estoque
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.inventory_2,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Est:',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2D2D2D),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.orange.shade600,
                                                  width: 1,
                                                ),
                                              ),
                                              child: TextField(
                                                controller: _estoqueController,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 8,
                                                          ),
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Botões Salvar e Cancelar
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: _cancelarEdicao,
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Cancelar',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.grey.shade600,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                _salvarEdicaoRapida(produto),
                                            icon: const Icon(
                                              Icons.check,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'SALVAR',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    // MODO VISUALIZAÇÃO - clique para editar
                                    Row(
                                      children: [
                                        // Preço com indicador de promoção
                                        if (produto.promocaoAtiva) ...[
                                          // Preço original riscado
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade600,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'R\$ ${produto.preco.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.normal,
                                                fontSize: 12,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Preço promocional
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.purple.shade700,
                                                  Colors.purple.shade500,
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.purple
                                                      .withOpacity(0.4),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.local_offer,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'R\$ ${produto.precoAtual.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // Badge de desconto
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade600,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '-${produto.percentualDesconto.toStringAsFixed(0)}%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          // Preço normal (sem promoção)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade700,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'R\$ ${produto.preco.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: produto.estoque < 10
                                                ? Colors.red.shade700
                                                : Colors.orange.shade700,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Estoque: ${produto.estoque}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Exibir preço de custo e margem de lucro (se disponível)
                                    if (produto.precoCusto != null && produto.precoCusto! > 0) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade700.withOpacity(0.3),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.blue.shade400,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.shopping_cart,
                                                  color: Colors.blueAccent,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Custo: R\$ ${produto.precoCusto!.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    color: Colors.blueAccent,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: produto.temLucro
                                                  ? Colors.green.shade700.withOpacity(0.3)
                                                  : Colors.red.shade700.withOpacity(0.3),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: produto.temLucro
                                                    ? Colors.greenAccent
                                                    : Colors.redAccent,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  produto.temLucro
                                                      ? Icons.trending_up
                                                      : Icons.trending_down,
                                                  color: produto.temLucro
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Margem: ${produto.margemLucroPercentual.toStringAsFixed(1)}%',
                                                  style: TextStyle(
                                                    color: produto.temLucro
                                                        ? Colors.greenAccent
                                                        : Colors.redAccent,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

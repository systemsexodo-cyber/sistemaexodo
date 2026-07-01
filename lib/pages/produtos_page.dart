import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../produto_form.dart' as produto_form;
import '../services/excel_export_service.dart';
import '../custom_app_bar.dart';
import '../theme.dart';
import '../widgets/permission_widget.dart';
import '../models/permissao.dart';
import 'entrada_rapida_produtos_page.dart';
import 'estoque_relatorio_geral_page.dart';
import 'estoque_reposicao_page.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

enum SortOption { codigo, nome, recentes, grupo, unidade }

class _ProdutosPageState extends State<ProdutosPage> {
  String _busca = '';
  final _buscaController = TextEditingController();
  SortOption _sortOption = SortOption.codigo;
  int _selectedIndex = -1; // Índice para navegação por teclado

  // Para edição rápida
  String? _editandoId;
  final _precoController = TextEditingController();
  final _estoqueController = TextEditingController();

  // Filtro de estoque e grupo
  int? _filtroEstoque; // null = todos, 10, 20, 30
  String? _filtroGrupo; 
  String? _filtroUnidade; // Novo: Filtro por unidade (UN, KG, etc)

  // Seleção para edição em massa
  final Set<String> _selecionados = {};
  bool _modoSelecao = false;

  // ==================== PAGINAÇÃO INTELIGENTE ====================
  static const int _itensPorPagina = 50; // Aumentado para 50 para reduzir rebuilds ao rolar
  int _itensVisiveis = 200; // Aumentado de 50 para 200 para carregar um catálogo maior inicialmente
  final ScrollController _scrollController = ScrollController();
  bool _carregando = false;
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  
  // Cache de resultados filtrados para performance
  List<Produto> _cacheFiltrados = [];
  String _cacheBusca = "";
  int? _cacheEstoque;
  String? _cacheGrupo;
  String? _cacheUnidade;
  SortOption _cacheSort = SortOption.codigo;
  int _cacheTotalService = 0;
  // Hash baseado no updatedAt do produto mais recente — invalida cache após qualquer edição
  int _cacheUpdateHash = 0;


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
    _selectedIndex = -1; // Reseta seleção ao filtrar
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _scrollToSelectedIndex() {
    if (!_scrollController.hasClients || _selectedIndex < 0) return;

    const double itemHeight = 110.0; // Altura calibrada para o cadastro
    final scrollPosition = _selectedIndex * itemHeight;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    // Se o item estiver fora da visão ou muito perto da borda (margem 10px)
    const margin = 10.0;
    if (scrollPosition < (currentOffset + margin) || 
        (scrollPosition + itemHeight) > (currentOffset + viewportHeight - margin)) {
      
      final targetScroll = (scrollPosition - (viewportHeight / 2) + (itemHeight / 2))
          .clamp(0.0, _scrollController.position.maxScrollExtent);
          
      _scrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
      );
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
        double.tryParse(_estoqueController.text.replaceAll(',', '.')) ?? produto.estoque;

    // Usar copyWith para preservar TODOS os campos, incluindo e-commerce
    final produtoAtualizado = produto.copyWith(
      preco: novoPreco,
      estoque: novoEstoque,
      updatedAt: DateTime.now(),
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

  void _gerarInventario({required bool isRetroativo, DateTime? dataAlvo}) {
    final service = Provider.of<DataService>(context, listen: false);
    try {
      debugPrint('>>> [ProdutosPage] Gerando inventário (Retroativo: $isRetroativo)...');
      
      // Pegar todos os produtos para garantir o inventário completo
      final todosProdutos = service.produtos;
      
      if (todosProdutos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum produto cadastrado para o inventário')),
        );
        return;
      }

      if (isRetroativo && dataAlvo != null) {
        // Enviar os produtos e o histórico completo para a reconstrução lógica
        ExcelExportService.exportarInventarioRetroativo(todosProdutos, service.estoqueHistorico, dataAlvo);
      } else {
        // Inventário atual (apenas produtos ativos com estoque > 0)
        final ativos = todosProdutos.where((p) => p.estoque > 0).toList();
        ExcelExportService.exportarInventarioContabilidade(ativos);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Inventário ${isRetroativo ? "Retroativo" : "Atual"} exportado! Verifique a pasta DOWNLOADS'),
          backgroundColor: isRetroativo ? Colors.amber.shade800 : Colors.amber,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro no inventário: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
  
  void _copiarDescricao(Produto produto) {
    final texto = [
      'Produto: ${produto.nome}',
      if (produto.descricao != null && produto.descricao!.isNotEmpty) 'Descrição: ${produto.descricao}',
      'Preço: ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(produto.precoAtual)}',
      if (produto.codigo != null && produto.codigo!.isNotEmpty) 'Código: ${produto.codigo}',
      if (produto.codigoBarras != null && produto.codigoBarras!.isNotEmpty) 'Barras: ${produto.codigoBarras}',
    ].join('\n');
    
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Informações copiadas para a área de transferência!'),
        backgroundColor: Colors.blueAccent,
        duration: Duration(seconds: 2),
      )
    );
  }

  void _clonarProduto(Produto produto) {
    // Criar um clone com ID vazio para que o DataService gere um novo
    final clone = produto.copyWith(
      id: '', 
      codigo: '', // Importante para que o Form saiba que deve gerar o PRÓXIMO disponível
      nome: '${produto.nome} (Cópia)',
      estoque: 0,
      updatedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    
    // Abrir o formulário com o clone, marcando como clone para usar addProduto no onSave
    _showForm(context, produto: clone, isClone: true);
  }

  void _showForm(BuildContext context, {Produto? produto, bool isClone = false}) {
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
            onSave: (newProduto) async {
              final service = Provider.of<DataService>(context, listen: false);
              if (produto == null || isClone) {
                await service.addProduto(newProduto);
              } else {
                await service.updateProduto(newProduto);
              }
              // Invalidar cache após salvar
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
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

    // Hash para detectar edições de preço/estoque (updatedAt do produto mais recente)
    final currentUpdateHash = service.produtos.isEmpty
        ? 0
        : service.produtos
            .map((p) => p.updatedAt?.millisecondsSinceEpoch ?? p.createdAt?.millisecondsSinceEpoch ?? 0)
            .reduce((a, b) => a > b ? a : b);

    // Lógica de cache para evitar re-filtrar e re-ordenar 6 mil itens em cada frame
    if (_cacheFiltrados.isEmpty || 
        _cacheBusca != _busca || 
        _cacheEstoque != _filtroEstoque || 
        _cacheGrupo != _filtroGrupo || 
        _cacheUnidade != _filtroUnidade || 
        _cacheSort != _sortOption ||
        _cacheTotalService != service.produtos.length ||
        _cacheUpdateHash != currentUpdateHash) {
      
      _cacheFiltrados = service.produtos.where((p) {
        if (_filtroEstoque != null && p.estoque >= _filtroEstoque!) return false;
        if (_filtroGrupo != null && p.grupo != _filtroGrupo) return false;
        if (_filtroUnidade != null && p.unidade != _filtroUnidade) return false;
        
        if (_busca.isEmpty) return true;

        final buscaLower = _busca.toLowerCase().trim();
        final ehNumero = RegExp(r'^[0-9]+$').hasMatch(buscaLower);

        if (!ehNumero && buscaLower.length < 2) return true;

        if (ehNumero && p.codigo != null) {
          final numCodigo = p.codigo!.replaceAll(RegExp(r'[^0-9]'), '');
          if (numCodigo == buscaLower) return true;
          return false;
        }

        if (!ehNumero && p.codigo != null) {
          final codigoLower = p.codigo!.toLowerCase();
          if (codigoLower.startsWith(buscaLower)) return true;
        }

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

      // Ordenação
      _cacheFiltrados.sort((a, b) {
        switch (_sortOption) {
          case SortOption.nome:
            return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
          case SortOption.recentes:
            final dateA = a.updatedAt ?? a.createdAt ?? DateTime(2000);
            final dateB = b.updatedAt ?? b.createdAt ?? DateTime(2000);
            return dateB.compareTo(dateA); 
          case SortOption.grupo:
            final grupoCompare = a.grupo.toLowerCase().compareTo(b.grupo.toLowerCase());
            if (grupoCompare != 0) return grupoCompare;
            return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
          case SortOption.unidade:
            final unidadeCompare = a.unidade.toLowerCase().compareTo(b.unidade.toLowerCase());
            if (unidadeCompare != 0) return unidadeCompare;
            return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
          case SortOption.codigo:
          default:
            final numA = int.tryParse(a.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
            final numB = int.tryParse(b.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
            return numA.compareTo(numB);
        }
      });

      // Atualizar chaves de cache
      _cacheBusca = _busca;
      _cacheEstoque = _filtroEstoque;
      _cacheGrupo = _filtroGrupo;
      _cacheUnidade = _filtroUnidade;
      _cacheSort = _sortOption;
      _cacheTotalService = service.produtos.length;
      _cacheUpdateHash = currentUpdateHash;
    }

    final produtosFiltrados = _cacheFiltrados;

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Produtos • ${service.empresaAtual?.nomeExibicao ?? 'Catálogo'}',
          actions: [
            // Botão Sincronizar e Diagnóstico
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: Colors.blueAccent),
              tooltip: 'Diagnóstico e Sincronização',
              onPressed: () => _showSyncDiagnostics(context, service),
            ),
            // Modo Seleção / Edição em Massa
            IconButton(
              icon: Icon(
                _modoSelecao ? Icons.check_circle : Icons.edit_note_rounded,
                color: _modoSelecao ? Colors.greenAccent : Colors.white70,
              ),
              tooltip: _modoSelecao ? 'Finalizar Seleção' : 'Edição em Massa',
              onPressed: () => setState(() {
                _modoSelecao = !_modoSelecao;
                if (!_modoSelecao) _selecionados.clear();
              }),
            ),
            if (_modoSelecao) ...[
              IconButton(
                icon: Icon(
                  _selecionados.length == produtosFiltrados.length 
                      ? Icons.deselect 
                      : Icons.select_all,
                  color: Colors.white70,
                ),
                tooltip: 'Selecionar Todos',
                onPressed: () {
                  setState(() {
                    if (_selecionados.length == produtosFiltrados.length) {
                      _selecionados.clear();
                    } else {
                      _selecionados.addAll(produtosFiltrados.map((p) => p.id));
                    }
                  });
                },
              ),
              if (_selecionados.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.bolt_rounded, color: Colors.yellowAccent),
                  tooltip: 'Edição Rápida da Lista',
                  onPressed: () => _mostrarQuickListEdit(context, service),
                ),
                IconButton(
                  icon: const Icon(Icons.auto_fix_high_rounded, color: Colors.orangeAccent),
                  tooltip: 'Alterar Selecionados (Massa)',
                  onPressed: () => _mostrarDialogEdicaoEmMassa(context, service),
                ),
              ],
            ],
            // Botão Relatório de Reposição (Atenção ao Estoque Mínimo)
            PermissionWidget(
              permissao: TipoPermissao.estoqueVisualizar,
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.assignment_late_outlined,
                      color: Colors.white70,
                    ),
                    tooltip: 'Relatório de Reposição',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EstoqueReposicaoPage(),
                        ),
                      );
                    },
                  ),
                  if (service.produtos.any((p) => (p.estoqueMinimo > 0 && p.estoque <= p.estoqueMinimo) || p.estoque <= 0))
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          service.produtos.where((p) => (p.estoqueMinimo > 0 && p.estoque <= p.estoqueMinimo) || p.estoque <= 0).length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Botão Relatório Geral
            PermissionWidget(
              permissao: TipoPermissao.estoqueVisualizar,
              child: IconButton(
                icon: const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white70,
                ),
                tooltip: 'Relatório Geral de Estoque',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EstoqueRelatorioGeralPage(),
                    ),
                  );
                },
              ),
            ),
            // Botão Exportar CSV
            PermissionWidget(
              permissao: TipoPermissao.estoqueVisualizar,
              child: IconButton(
                icon: const Icon(
                  Icons.shopping_cart_checkout_rounded,
                  color: Colors.blueAccent,
                ),
                tooltip: 'Exportar CSV para E-commerce',
                onPressed: () {
                  try {
                    debugPrint('>>> [ProdutosPage] Iniciando exportação CSV...');
                    if (produtosFiltrados.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nenhum produto filtrado para exportar')),
                      );
                      return;
                    }
                    ExcelExportService.exportarProdutosCSV(produtosFiltrados);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✓ CSV exportado! Verifique a pasta DOWNLOADS (Ctrl+J)'),
                        backgroundColor: Colors.blueAccent,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Erro na exportação CSV: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
              ),
            ),
            // Botão Inventário para Contabilidade (Novo!)
            PermissionWidget(
              permissao: TipoPermissao.estoqueVisualizar,
              child: IconButton(
                icon: const Icon(
                  Icons.account_balance_rounded,
                  color: Colors.amberAccent,
                ),
                tooltip: 'Inventário p/ Contabilidade (Custo)',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E2E),
                      title: const Text('Gerar Inventário', style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'Escolha o tipo de inventário que deseja gerar para a contabilidade:',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _gerarInventario(isRetroativo: false);
                          },
                          child: const Text('ESTOQUE ATUAL'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            final data = await showDatePicker(
                              context: context,
                              initialDate: DateTime(DateTime.now().year - 1, 12, 31),
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                              helpText: 'Selecione a data do inventário retroativo',
                            );
                            if (data != null) {
                              _gerarInventario(isRetroativo: true, dataAlvo: data);
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                          child: const Text('ESTOQUE RETROATIVO'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Botão Exportar Excel
            PermissionWidget(
              permissao: TipoPermissao.estoqueVisualizar,
              child: IconButton(
                icon: const Icon(
                  Icons.file_download_outlined,
                  color: Colors.greenAccent,
                ),
                tooltip: 'Exportar para Excel',
                onPressed: () {
                  try {
                    debugPrint('>>> [ProdutosPage] Iniciando exportação Excel...');
                    if (produtosFiltrados.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nenhum produto filtrado para exportar')),
                      );
                      return;
                    }
                    ExcelExportService.exportarProdutos(produtosFiltrados);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✓ Exportação concluída! Verifique a pasta DOWNLOADS (Ctrl+J)'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Erro na exportação Excel: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
              ),
            ),
            // Botão entrada rápida
            PermissionWidget(
              permissao: TipoPermissao.estoqueEntrada,
              child: IconButton(
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
            ),
            PermissionWidget(
              permissao: TipoPermissao.produtosCriar,
              child: IconButton(
                icon: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: () => _showForm(context),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
                    // Barra de busca minimalista
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.white.withOpacity(0.6), size: 22),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, color: Colors.blueAccent.withOpacity(0.8), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Total: ${service.produtos.length}',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        if (produtosFiltrados.length < service.produtos.length) ...[
                          const SizedBox(width: 6),
                          Container(width: 1, height: 12, color: Colors.blueAccent.withOpacity(0.3)),
                          const SizedBox(width: 6),
                          Text(
                            'Filtrados: ${produtosFiltrados.length}',
                            style: TextStyle(color: Colors.blueAccent.withOpacity(0.7), fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      onChanged: (v) { setState(() { _busca = v; _resetPaginacao(); }); },
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Buscar produtos...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_busca.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () { _buscaController.clear(); setState(() { _busca = ''; _resetPaginacao(); }); },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const VerticalDivider(width: 20, indent: 14, endIndent: 14, color: Colors.white10),
                  // Botão de Ordenação (Novo lugar, mais visível)
                  PopupMenuButton<SortOption>(
                    icon: Icon(
                      _sortOption == SortOption.codigo ? Icons.tag :
                      _sortOption == SortOption.nome ? Icons.sort_by_alpha :
                      _sortOption == SortOption.recentes ? Icons.history : 
                      _sortOption == SortOption.grupo ? Icons.category_outlined : Icons.straighten,
                      color: Colors.blueAccent, size: 20,
                    ),
                    tooltip: 'Ordenar produtos',
                    onSelected: (option) => setState(() => _sortOption = option),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: SortOption.codigo, child: Row(children: [Icon(Icons.tag, size: 16), SizedBox(width: 8), Text('Código')])),
                      const PopupMenuItem(value: SortOption.nome, child: Row(children: [Icon(Icons.sort_by_alpha, size: 16), SizedBox(width: 8), Text('Nome (A-Z)')])),
                      const PopupMenuItem(value: SortOption.recentes, child: Row(children: [Icon(Icons.history, size: 16), SizedBox(width: 8), Text('Recentes')])),
                      const PopupMenuItem(value: SortOption.grupo, child: Row(children: [Icon(Icons.category_outlined, size: 16), SizedBox(width: 8), Text('Grupo')])),
                      const PopupMenuItem(value: SortOption.unidade, child: Row(children: [Icon(Icons.straighten, size: 16), SizedBox(width: 8), Text('Unidade')])),
                    ],
                  ),
                  const VerticalDivider(width: 12, indent: 14, endIndent: 14, color: Colors.white10),
                  // Filtro por Grupo (Novo!)
                  PopupMenuButton<String?>(
                    icon: Icon(Icons.category, 
                      color: _filtroGrupo != null ? Colors.purpleAccent : Colors.white60, 
                      size: 20
                    ),
                    tooltip: 'Filtrar por Grupo',
                    onSelected: (v) => setState(() { _filtroGrupo = v; _resetPaginacao(); }),
                    itemBuilder: (context) {
                      final grupos = service.produtos
                          .map((p) => p.grupo)
                          .where((g) => g.isNotEmpty)
                          .toSet()
                          .toList();
                      grupos.sort();
                      
                      return [
                        const PopupMenuItem(value: null, child: Text('Todos os Grupos')),
                        ...grupos.map((g) => PopupMenuItem(value: g, child: Text(g))),
                      ];
                    },
                  ),
                  const VerticalDivider(width: 12, indent: 14, endIndent: 14, color: Colors.white10),
                  // Filtro por Unidade (Novo!)
                  PopupMenuButton<String?>(
                    icon: Icon(Icons.straighten, 
                      color: _filtroUnidade != null ? Colors.tealAccent : Colors.white60, 
                      size: 20
                    ),
                    tooltip: 'Filtrar por Unidade',
                    onSelected: (v) => setState(() { _filtroUnidade = v; _resetPaginacao(); }),
                    itemBuilder: (context) {
                      final unidades = service.produtos
                          .map((p) => p.unidade)
                          .where((u) => u.isNotEmpty)
                          .toSet()
                          .toList();
                      unidades.sort();
                      
                      return [
                        const PopupMenuItem(value: null, child: Text('Todas as Unidades')),
                        ...unidades.map((u) => PopupMenuItem(value: u, child: Text(u))),
                      ];
                    },
                  ),
                  const VerticalDivider(width: 12, indent: 14, endIndent: 14, color: Colors.white10),
                  PopupMenuButton<int?>(
                    icon: Icon(Icons.filter_list, 
                      color: _filtroEstoque != null ? Colors.orangeAccent : Colors.white60, 
                      size: 22
                    ),
                    color: const Color(0xFF1A1A2E),
                    onSelected: (v) { setState(() { _filtroEstoque = v; _resetPaginacao(); }); },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: null, child: Text('Todos os Itens', style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 10, child: Text('Estoque Baixo (<10)', style: TextStyle(color: Colors.redAccent))),
                      const PopupMenuItem(value: 20, child: Text('Estoque Médio (<20)', style: TextStyle(color: Colors.orangeAccent))),
                    ],
                  ),
                ],
              ),
            ),
            if (_filtroEstoque != null || _filtroGrupo != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8, right: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_filtroEstoque != null)
                      ChoiceChip(
                        label: Text('Estoque < $_filtroEstoque', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        selected: true,
                        onSelected: (_) => setState(() => _filtroEstoque = null),
                        backgroundColor: Colors.orange.shade900.withOpacity(0.4),
                        selectedColor: Colors.orange.shade800,
                        avatar: const Icon(Icons.close, size: 14, color: Colors.white),
                        padding: EdgeInsets.zero,
                      ),
                    if (_filtroGrupo != null)
                      ChoiceChip(
                        label: Text('Grupo: $_filtroGrupo', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        selected: true,
                        onSelected: (_) => setState(() => _filtroGrupo = null),
                        backgroundColor: Colors.purple.shade900.withOpacity(0.4),
                        selectedColor: Colors.purple.shade800,
                        avatar: const Icon(Icons.close, size: 14, color: Colors.white),
                        padding: EdgeInsets.zero,
                      ),
                    if (_filtroUnidade != null)
                      ChoiceChip(
                        label: Text('Unidade: $_filtroUnidade', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        selected: true,
                        onSelected: (_) => setState(() => _filtroUnidade = null),
                        backgroundColor: Colors.teal.shade900.withOpacity(0.4),
                        selectedColor: Colors.teal.shade800,
                        avatar: const Icon(Icons.close, size: 14, color: Colors.white),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: produtosFiltrados.isEmpty
                  ? Center(
                      child: Text(
                        _filtroEstoque != null
                            ? 'Nenhum produto com estoque menor que $_filtroEstoque'
                            : 'Nenhum produto encontrado.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    )
                  : Focus(
                        autofocus: true,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            final maxItems = _itensVisiveis > produtosFiltrados.length 
                                ? produtosFiltrados.length 
                                : _itensVisiveis;

                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                              setState(() {
                                if (_selectedIndex < produtosFiltrados.length - 1) {
                                  _selectedIndex++;
                                  // Lazy loading antecipado via teclado
                                  if (_selectedIndex >= _itensVisiveis - 5) {
                                    _itensVisiveis += _itensPorPagina;
                                  }
                                }
                              });
                              _scrollToSelectedIndex();
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() {
                                if (_selectedIndex > 0) _selectedIndex--;
                              });
                              _scrollToSelectedIndex();
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.enter || 
                                       event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                              if (_selectedIndex >= 0 && _selectedIndex < produtosFiltrados.length) {
                                final p = produtosFiltrados[_selectedIndex];
                                if (_modoSelecao) {
                                  setState(() {
                                    if (_selecionados.contains(p.id)) _selecionados.remove(p.id);
                                    else _selecionados.add(p.id);
                                  });
                                } else {
                                  _iniciarEdicaoRapida(p);
                                }
                              }
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                              if (_editandoId != null) {
                                _cancelarEdicao();
                                return KeyEventResult.handled;
                              }
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          thickness: 8,
                          radius: const Radius.circular(10),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _itensVisiveis > produtosFiltrados.length 
                                ? produtosFiltrados.length 
                                : _itensVisiveis,
                        itemBuilder: (context, index) {
                          final produto = produtosFiltrados[index];
                          final estaEditando = _editandoId == produto.id;
                          final isSelected = _selectedIndex == index;
                          final estoqueBaixo = produto.estoque < 10;
  
                          if (estaEditando) {
                            return _buildEdicaoRapida(produto);
                          }
  
                          return RepaintBoundary(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.blueAccent.withOpacity(0.15) 
                                  : Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? Colors.blueAccent : Colors.white.withOpacity(0.05),
                                width: isSelected ? 3 : 1,
                              ),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.5),
                                  blurRadius: 15,
                                  spreadRadius: 4,
                                )
                              ] : null,
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedIndex = index;
                                });
                                if (_modoSelecao) {
                                  setState(() {
                                    if (_selecionados.contains(produto.id)) {
                                      _selecionados.remove(produto.id);
                                    } else {
                                      _selecionados.add(produto.id);
                                    }
                                  });
                                } else {
                                  _iniciarEdicaoRapida(produto);
                                }
                              },
                              onLongPress: () => _showForm(context, produto: produto),
                              onDoubleTap: () => _showForm(context, produto: produto),
                              hoverColor: Colors.blueAccent.withOpacity(0.1),
                              splashColor: Colors.blueAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    if (_modoSelecao)
                                      Checkbox(
                                        value: _selecionados.contains(produto.id),
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selecionados.add(produto.id);
                                            } else {
                                              _selecionados.remove(produto.id);
                                            }
                                          });
                                        },
                                        activeColor: Colors.blueAccent,
                                        side: const BorderSide(color: Colors.white24),
                                      ),
                                    if (_modoSelecao) const SizedBox(width: 4),
                                    Container(
                                      width: 52,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        produto.codigo?.replaceAll('COD-', '') ?? '?',
                                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                produto.nome.toUpperCase(),
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy_rounded, color: Colors.white30, size: 14),
                                              tooltip: 'Copiar Descrição',
                                              onPressed: () => _copiarDescricao(produto),
                                              constraints: const BoxConstraints(),
                                              padding: const EdgeInsets.only(left: 4),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            // Badge de Estoque
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: estoqueBaixo ? Colors.redAccent.withOpacity(0.15) : Colors.white.withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: estoqueBaixo ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(estoqueBaixo ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, 
                                                    size: 12, color: estoqueBaixo ? Colors.redAccent : Colors.blueAccent),
                                                  const SizedBox(width: 6),
                                                  Text('${produto.estoque} ${produto.unidade}', 
                                                    style: TextStyle(
                                                      fontSize: 11, 
                                                      color: estoqueBaixo ? Colors.redAccent : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: 0.5
                                                    )),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Badge de Grupo
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.blueAccent.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                                              ),
                                              child: Text(produto.grupo.isEmpty ? 'GERAL' : produto.grupo.toUpperCase(),
                                                style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                            ),
                                            if (produto.enviaBalanca) ...[
                                              const SizedBox(width: 8),
                                              // Badge de Balança
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.tealAccent.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.scale, size: 10, color: Colors.tealAccent),
                                                    SizedBox(width: 4),
                                                    Text('BALANÇA',
                                                      style: TextStyle(fontSize: 9, color: Colors.tealAccent, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (produto.estoquePorFornecedor.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              produto.estoquePorFornecedor.entries
                                                  .where((e) => e.value > 0)
                                                  .map((e) => '${e.value} da ${e.key}')
                                                  .join(', '),
                                              style: const TextStyle(fontSize: 10, color: Colors.white60, fontStyle: FontStyle.italic),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatoMoeda.format(produto.precoAtual),
                                        style: const TextStyle(
                                          color: Color(0xFF00FF9D), // Verde cintilante/neon
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 17,
                                          // Sombras simplificadas para performance Web
                                          shadows: [
                                            Shadow(color: Color(0x8000FF9D), blurRadius: 4),
                                          ],
                                        ),
                                      ),
                                      if (produto.promocaoAtiva)
                                        Text(
                                          _formatoMoeda.format(produto.preco),
                                          style: const TextStyle(color: Colors.white24, fontSize: 10, decoration: TextDecoration.lineThrough),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white30, size: 20),
                                    color: const Color(0xFF1A1A2E),
                                    onSelected: (v) {
                                      if (v == 'edit') _showForm(context, produto: produto);
                                      if (v == 'clone') _clonarProduto(produto);
                                      if (v == 'copy') _copiarDescricao(produto);
                                      if (v == 'del') _confirmarExclusao(produto);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Editar Detalhes', style: TextStyle(color: Colors.white))])),
                                      const PopupMenuItem(value: 'clone', child: Row(children: [Icon(Icons.copy_all_rounded, size: 16, color: Colors.blueAccent), SizedBox(width: 8), Text('Clonar Produto', style: TextStyle(color: Colors.white))])),
                                      const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy_rounded, size: 16, color: Colors.white70), SizedBox(width: 8), Text('Copiar Texto', style: TextStyle(color: Colors.white))])),
                                      const PopupMenuItem(value: 'del', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Excluir Produto', style: TextStyle(color: Colors.redAccent))])),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEdicaoRapida(Produto produto) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço R\$', labelStyle: TextStyle(color: Colors.white54, fontSize: 12)),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _estoqueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Estoque', labelStyle: TextStyle(color: Colors.white54, fontSize: 12)),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _cancelarEdicao, child: const Text('Cancelar')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _salvarEdicaoRapida(produto),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: const Text('SALVAR'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmarExclusao(Produto produto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Produto'),
        content: Text('Deseja realmente excluir "${produto.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Excluir', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      Provider.of<DataService>(context, listen: false).deleteProduto(produto.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produto excluído')));
    }
  }
  void _mostrarDialogEdicaoEmMassa(BuildContext context, DataService service) {
    // Estados de ativação dos campos
    bool ePreco = false, eEstoque = false, eGrupo = false, eUnidade = false, eCusto = false;
    bool eNcm = false, eCfop = false, eOrigem = false, eCest = false;
    bool eIcmsAliq = false, eIcmsCst = false, eCsosn = false;
    bool ePisAliq = false, ePisCst = false, eCofinsAliq = false, eCofinsCst = false;
    bool eLoja = false, eDestaque = false, eCozinha = false, eBar = false, eBalanca = false;

    // Controladores
    final cPreco = TextEditingController(), cEstoque = TextEditingController(), cGrupo = TextEditingController();
    final cUnidade = TextEditingController(), cCusto = TextEditingController(), cNcm = TextEditingController();
    final cCfop = TextEditingController(), cOrigem = TextEditingController(), cCest = TextEditingController();
    final cIcmsAliq = TextEditingController(), cIcmsCst = TextEditingController(), cCsosn = TextEditingController();
    final cPisAliq = TextEditingController(), cPisCst = TextEditingController(), cCofinsAliq = TextEditingController(), cCofinsCst = TextEditingController();
    
    // Valores booleanos
    bool vLoja = false, vDestaque = false, vCozinha = false, vBar = false, vBalanca = false;

    // Lista de grupos existentes para o autocomplete
    final gruposExistentes = service.produtos.map((p) => p.grupo).where((g) => g.isNotEmpty).toSet().toList();
    gruposExistentes.sort();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF0D0D15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.blue.withOpacity(0.2))),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_fix_high, color: Colors.orangeAccent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Edição em Massa Profissional', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_selecionados.length} produtos serão impactados', style: TextStyle(color: Colors.blueAccent.withOpacity(0.7), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildSecaoBulk('🛒 BÁSICO & ESTOQUE', [
                    _buildCampoBulk('Preço de Venda', cPreco, ePreco, (v) => setDs(() => ePreco = v!), kType: const TextInputType.numberWithOptions(decimal: true)),
                    _buildCampoBulk('Preço de Custo', cCusto, eCusto, (v) => setDs(() => eCusto = v!), kType: const TextInputType.numberWithOptions(decimal: true)),
                    _buildCampoBulk('Estoque Atual', cEstoque, eEstoque, (v) => setDs(() => eEstoque = v!), kType: TextInputType.number),
                    _buildCampoBulk('Unidade (UN, KG, PC)', cUnidade, eUnidade, (v) => setDs(() => eUnidade = v!)),
                    // Grupo com sugestões
                    _buildCampoAutocompleteBulk('Grupo/Categoria', cGrupo, gruposExistentes, eGrupo, (v) => setDs(() => eGrupo = v!)),
                  ]),
                  
                  _buildSecaoBulk('⚖️ FISCAL & TRIBUTAÇÃO', [
                    _buildCampoBulk('NCM (8 dígitos)', cNcm, eNcm, (v) => setDs(() => eNcm = v!), kType: TextInputType.number),
                    _buildCampoBulk('CFOP Padrão', cCfop, eCfop, (v) => setDs(() => eCfop = v!), kType: TextInputType.number),
                    _buildCampoBulk('Origem (0-8)', cOrigem, eOrigem, (v) => setDs(() => eOrigem = v!), kType: TextInputType.number),
                    _buildCampoBulk('CEST', cCest, eCest, (v) => setDs(() => eCest = v!), kType: TextInputType.number),
                    const Divider(color: Colors.white10, height: 24),
                    _buildCampoBulk('ICMS Alíquota (%)', cIcmsAliq, eIcmsAliq, (v) => setDs(() => eIcmsAliq = v!), kType: TextInputType.number),
                    _buildCampoBulk('ICMS CST', cIcmsCst, eIcmsCst, (v) => setDs(() => eIcmsCst = v!)),
                    _buildCampoBulk('CSOSN (Simples)', cCsosn, eCsosn, (v) => setDs(() => eCsosn = v!)),
                    const Divider(color: Colors.white10, height: 24),
                    _buildCampoBulk('PIS Alíquota (%)', cPisAliq, ePisAliq, (v) => setDs(() => ePisAliq = v!), kType: TextInputType.number),
                    _buildCampoBulk('PIS CST', cPisCst, ePisCst, (v) => setDs(() => ePisCst = v!)),
                    _buildCampoBulk('COFINS Alíquota (%)', cCofinsAliq, eCofinsAliq, (v) => setDs(() => eCofinsAliq = v!), kType: TextInputType.number),
                    _buildCampoBulk('COFINS CST', cCofinsCst, eCofinsCst, (v) => setDs(() => eCofinsCst = v!)),
                  ]),
 
                  _buildSecaoBulk('🌐 OPÇÕES ADICIONAIS', [
                    _buildSwitchBulk('Exibir no E-commerce', vLoja, eLoja, (v) => setDs(() => eLoja = v!), (val) => setDs(() => vLoja = val)),
                    _buildSwitchBulk('Produto em Destaque', vDestaque, eDestaque, (v) => setDs(() => eDestaque = v!), (val) => setDs(() => vDestaque = val)),
                    _buildSwitchBulk('Enviar para Cozinha', vCozinha, eCozinha, (v) => setDs(() => eCozinha = v!), (val) => setDs(() => vCozinha = val)),
                    _buildSwitchBulk('Enviar para o Bar', vBar, eBar, (v) => setDs(() => eBar = v!), (val) => setDs(() => vBar = val)),
                    _buildSwitchBulk('Enviar para Balança', vBalanca, eBalanca, (v) => setDs(() => eBalanca = v!), (val) => setDs(() => vBalanca = val)),
                  ]),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              onPressed: () {
                for (final id in _selecionados) {
                  try {
                    final p = service.produtos.firstWhere((prod) => prod.id == id);
                    final up = p.copyWith(
                      preco: ePreco ? (double.tryParse(cPreco.text.replaceAll(',', '.')) ?? p.preco) : p.preco,
                      precoCusto: eCusto ? (double.tryParse(cCusto.text.replaceAll(',', '.')) ?? p.precoCusto) : p.precoCusto,
                      estoque: eEstoque ? (double.tryParse(cEstoque.text.replaceAll(',', '.')) ?? p.estoque) : p.estoque,
                      unidade: eUnidade ? cUnidade.text.trim() : p.unidade,
                      grupo: eGrupo ? cGrupo.text.trim() : p.grupo,
                      ncm: eNcm ? cNcm.text.trim() : p.ncm,
                      cfop: eCfop ? cCfop.text.trim() : p.cfop,
                      origem: eOrigem ? cOrigem.text.trim() : p.origem,
                      cest: eCest ? cCest.text.trim() : p.cest,
                      icmsAliquota: eIcmsAliq ? (double.tryParse(cIcmsAliq.text.replaceAll(',', '.')) ?? p.icmsAliquota) : p.icmsAliquota,
                      icmsCst: eIcmsCst ? cIcmsCst.text.trim() : p.icmsCst,
                      csosn: eCsosn ? cCsosn.text.trim() : p.csosn,
                      pisAliquota: ePisAliq ? (double.tryParse(cPisAliq.text.replaceAll(',', '.')) ?? p.pisAliquota) : p.pisAliquota,
                      pisCst: ePisCst ? cPisCst.text.trim() : p.pisCst,
                      cofinsAliquota: eCofinsAliq ? (double.tryParse(cCofinsAliq.text.replaceAll(',', '.')) ?? p.cofinsAliquota) : p.cofinsAliquota,
                      cofinsCst: eCofinsCst ? cCofinsCst.text.trim() : p.cofinsCst,
                      exibirNaLoja: eLoja ? vLoja : p.exibirNaLoja,
                      emDestaque: eDestaque ? vDestaque : p.emDestaque,
                      paraCozinha: eCozinha ? vCozinha : p.paraCozinha,
                      paraBar: eBar ? vBar : p.paraBar,
                      enviaBalanca: eBalanca ? vBalanca : p.enviaBalanca,
                      updatedAt: DateTime.now(),
                    );
                    service.updateProduto(up);
                  } catch (_) {}
                }
                setState(() { _selecionados.clear(); _modoSelecao = false; });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operação concluída com sucesso!'), backgroundColor: Colors.green));
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('ATUALIZAR TUDO', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoBulk(String titulo, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(titulo, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        ),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }


  void _mostrarQuickListEdit(BuildContext context, DataService service) {
    // Pegar os produtos selecionados
    final selecionados = service.produtos
        .where((p) => _selecionados.contains(p.id))
        .toList();

    // Ordenar por código para facilitar
    selecionados.sort((a, b) {
      final numA = int.tryParse(a.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
      final numB = int.tryParse(b.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
      return numA.compareTo(numB);
    });

    // Mapa para controlar as edições locais antes de salvar
    final Map<String, Produto> edicoes = {
      for (var p in selecionados) p.id: p
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDs) => Dialog.fullscreen(
          backgroundColor: const Color(0xFF0F0F1E),
          child: Scaffold(
            backgroundColor: const Color(0xFF0F0F1E),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text('Edição Rápida de Lista (${selecionados.length})'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('SALVAR TUDO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      // Mostrar loading
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator()),
                      );

                      try {
                        for (var p in edicoes.values) {
                          await service.updateProduto(p);
                        }
                        
                        if (context.mounted) {
                          Navigator.pop(context); // Feedback do loading
                          Navigator.pop(context); // Fechar Edição Rápida
                          
                          setState(() {
                            _selecionados.clear();
                            _modoSelecao = false;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Todos os produtos foram atualizados!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                         if (context.mounted) {
                          Navigator.pop(context); // Feedback do loading
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('❌ Erro ao salvar: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 24,
                    headingTextStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    dataTextStyle: const TextStyle(color: Colors.white70),
                    columns: const [
                      DataColumn(label: Text('Cod')),
                      DataColumn(label: Text('Nome do Produto')),
                      DataColumn(label: Text('Preço (R\$)')),
                      DataColumn(label: Text('Custo (R\$)')),
                      DataColumn(label: Text('Estoque')),
                      DataColumn(label: Text('Grupo')),
                    ],
                    rows: selecionados.map((p) {
                      final atual = edicoes[p.id]!;
                      
                      return DataRow(
                        cells: [
                          DataCell(Text(p.codigo?.replaceAll('COD-', '') ?? '-', style: const TextStyle(fontSize: 12))),
                          DataCell(
                            SizedBox(
                              width: 250,
                              child: TextFormField(
                                initialValue: atual.nome,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) => edicoes[p.id] = edicoes[p.id]!.copyWith(nome: v),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: atual.preco.toStringAsFixed(2),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(
                                  fontSize: 13, 
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.greenAccent, blurRadius: 8),
                                  ],
                                ),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) => edicoes[p.id] = edicoes[p.id]!.copyWith(preco: double.tryParse(v.replaceAll(',', '.')) ?? atual.preco),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: (atual.precoCusto ?? 0).toStringAsFixed(2),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 13, color: Colors.orangeAccent),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) => edicoes[p.id] = edicoes[p.id]!.copyWith(precoCusto: double.tryParse(v.replaceAll(',', '.')) ?? atual.precoCusto),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 60,
                              child: TextFormField(
                                initialValue: atual.estoque.toString(),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13, color: Colors.blueAccent),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) => edicoes[p.id] = edicoes[p.id]!.copyWith(estoque: double.tryParse(v.replaceAll(',', '.')) ?? atual.estoque),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: atual.grupo,
                                style: const TextStyle(fontSize: 13, color: Colors.purpleAccent),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                onChanged: (v) => edicoes[p.id] = edicoes[p.id]!.copyWith(grupo: v),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCampoBulk(String label, TextEditingController ctrl, bool ativo, Function(bool?) onToggle, {TextInputType? kType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(value: ativo, onChanged: onToggle, activeColor: Colors.blueAccent, side: const BorderSide(color: Colors.white24)),
          Expanded(
            child: TextField(
              controller: ctrl,
              enabled: ativo,
              keyboardType: kType,
              style: TextStyle(color: ativo ? Colors.white : Colors.white24, fontSize: 13),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: ativo ? Colors.white70 : Colors.white24, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.03),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoAutocompleteBulk(String label, TextEditingController ctrl, List<String> sugestoes, bool ativo, Function(bool?) onToggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(value: ativo, onChanged: onToggle, activeColor: Colors.blueAccent, side: const BorderSide(color: Colors.white24)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return sugestoes;
                  return sugestoes.where((s) => s.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (val) => ctrl.text = val,
                fieldViewBuilder: (ctx, tEc, fN, onFieldSubmitted) {
                   if (tEc.text.isEmpty && ctrl.text.isNotEmpty) tEc.text = ctrl.text;
                   return TextField(
                     controller: tEc,
                     focusNode: fN,
                     enabled: ativo,
                     style: TextStyle(color: ativo ? Colors.white : Colors.white24, fontSize: 13),
                     decoration: InputDecoration(
                       labelText: label,
                       hintText: 'Digite ou selecione...',
                       labelStyle: TextStyle(color: ativo ? Colors.white70 : Colors.white24, fontSize: 12),
                       filled: true,
                       fillColor: Colors.white.withOpacity(0.03),
                       isDense: true,
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                     ),
                     onChanged: (v) => ctrl.text = v,
                   );
                },
                optionsViewBuilder: (ctx, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: constraints.maxWidth,
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (ctx, i) => ListTile(
                            title: Text(options.elementAt(i), style: const TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () => onSelected(options.elementAt(i)),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchBulk(String label, bool valor, bool ativo, Function(bool?) onToggle, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(value: ativo, onChanged: onToggle, activeColor: Colors.blueAccent, side: const BorderSide(color: Colors.white24)),
          Expanded(
            child: Opacity(
              opacity: ativo ? 1.0 : 0.3,
              child: SwitchListTile(
                title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                value: valor,
                onChanged: ativo ? onChanged : null,
                activeColor: Colors.blueAccent,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSyncDiagnostics(BuildContext context, DataService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.analytics_outlined, color: Colors.blueAccent),
            SizedBox(width: 12),
            Text('Diagnóstico de Catálogo', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagRow('Empresa Atual:', service.currentEmpresaId ?? 'Nenhuma'),
            _buildDiagRow('Total em Memória:', '${service.produtos.length} itens'),
            _buildDiagRow('Firebase Habilitado:', service.firebaseHabilitado ? 'Sim' : 'Não'),
            if (service.ultimoErroSync != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Erro: ${service.ultimoErroSync}', style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            const Divider(color: Colors.white10, height: 24),
            const Text('Ações Disponíveis:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download, size: 18),
                label: const Text('FORÇAR RECARGA DA NUVEM'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.2), foregroundColor: Colors.blueAccent),
                onPressed: () async {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizando com Firebase...')));
                  await service.recarregarTudoDoFirebase();
                },
              ),
            ),
            if (!service.firebaseHabilitado) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_queue, size: 18),
                  label: const Text('REATIVAR NUVEM (FIREBASE)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.2), foregroundColor: Colors.green),
                  onPressed: () {
                    Navigator.pop(context);
                    service.reativarFirebase();
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('FORÇAR UPLOAD TOTAL (MEMÓRIA -> NUVEM)'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.withOpacity(0.2), foregroundColor: Colors.orange),
                onPressed: () async {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviando dados para a nuvem em lotes...')));
                  await service.addProdutosLote(service.produtos);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.storage_rounded, size: 18),
                label: const Text('RECARREGAR DADOS LOCAIS'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(context);
                  await service.definirEmpresaAtual(service.currentEmpresaId);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('FECHAR')),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

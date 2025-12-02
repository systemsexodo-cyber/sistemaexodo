import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../services/pedido_service.dart';
import '../models/pedido.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/item_pedido.dart';
import '../models/forma_pagamento.dart';
import '../widgets/pagamento_widget.dart';
import '../theme.dart';

/// Item no carrinho de compras
class ItemCarrinho {
  final Produto produto;
  int quantidade;
  double precoUnitario;

  ItemCarrinho({
    required this.produto,
    this.quantidade = 1,
    double? precoUnitario,
  }) : precoUnitario = precoUnitario ?? produto.preco;

  double get subtotal => quantidade * precoUnitario;

  ItemPedido toItemPedido() {
    return ItemPedido(
      id: produto.id,
      nome: produto.nome,
      quantidade: quantidade,
      preco: precoUnitario,
    );
  }
}

/// Página de lançamento inteligente de pedidos
class LancarPedidoPage extends StatefulWidget {
  final Pedido? pedidoExistente;
  final Cliente? clienteInicial; // Cliente já selecionado

  const LancarPedidoPage({
    super.key,
    this.pedidoExistente,
    this.clienteInicial,
  });

  @override
  State<LancarPedidoPage> createState() => _LancarPedidoPageState();
}

class _LancarPedidoPageState extends State<LancarPedidoPage> {
  final _formKey = GlobalKey<FormState>();
  final _buscaController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _buscaFocusNode = FocusNode();

  // Estado do pedido
  Cliente? _clienteSelecionado;
  final List<ItemCarrinho> _carrinho = [];
  List<PagamentoPedido> _pagamentos = []; // Formas de pagamento
  String _statusPedido = 'Pendente';
  String _numeroPedido = '';
  bool _mostrarPagamentos = false; // Controla exibição do painel de pagamentos

  // Estado da busca
  List<Produto> _produtosFiltrados = [];
  bool _mostrarResultadosBusca = false;
  int _indiceSelecionado = -1;

  // Lista de status disponíveis
  final List<String> _statusDisponiveis = [
    'Pendente',
    'Em Andamento',
    'Concluído',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);

    // Se for edição, carregar dados do pedido existente
    if (widget.pedidoExistente != null) {
      _carregarPedidoExistente();
    } else {
      // Carregar cliente inicial se fornecido
      if (widget.clienteInicial != null) {
        _clienteSelecionado = widget.clienteInicial;
      }
      // Gerar próximo número de pedido
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gerarNumeroPedido();
      });
    }
  }

  void _gerarNumeroPedido() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final numerosExistentes = dataService.pedidos.map((p) => p.numero).toList();
    setState(() {
      _numeroPedido = PedidoService.gerarProximoNumeroPedido(numerosExistentes);
    });
  }

  void _carregarPedidoExistente() {
    final pedido = widget.pedidoExistente!;
    final dataService = Provider.of<DataService>(context, listen: false);

    // Carregar número do pedido
    _numeroPedido = pedido.numero;

    // Buscar cliente
    if (pedido.clienteId != null) {
      _clienteSelecionado = dataService.clientes
          .where((c) => c.id == pedido.clienteId)
          .firstOrNull;
    }

    // Carregar itens do carrinho
    for (final item in pedido.produtos) {
      final produto = dataService.produtos
          .where((p) => p.id == item.id)
          .firstOrNull;

      if (produto != null) {
        _carrinho.add(
          ItemCarrinho(
            produto: produto,
            quantidade: item.quantidade,
            precoUnitario: item.preco,
          ),
        );
      }
    }

    // Carregar pagamentos existentes
    _pagamentos = List.from(pedido.pagamentos);
    _mostrarPagamentos = _pagamentos.isNotEmpty;

    _statusPedido = pedido.status;
    _observacoesController.text = pedido.observacoes ?? '';
  }

  @override
  void dispose() {
    _buscaController.removeListener(_onBuscaChanged);
    _buscaController.dispose();
    _observacoesController.dispose();
    _buscaFocusNode.dispose();
    super.dispose();
  }

  void _onBuscaChanged() {
    final query = _buscaController.text.trim();
    final queryLower = query.toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _produtosFiltrados = [];
        _mostrarResultadosBusca = false;
        _indiceSelecionado = -1;
      });
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    final produtos = dataService.produtos;

    setState(() {
      // Extrair números do query (removendo zeros à esquerda para comparação)
      final queryNumeros = query.replaceAll(RegExp(r'[^0-9]'), '');
      final queryNumerosSemZeros = queryNumeros.isEmpty ? '' : int.tryParse(queryNumeros)?.toString() ?? queryNumeros;
      
      final produtosFiltrados = produtos.where((p) {
        final nome = p.nome.toLowerCase();
        final codigo = (p.codigo ?? '').trim();
        final codigoLower = codigo.toLowerCase();
        final codigoBarras = (p.codigoBarras ?? '').trim();
        final codigoBarrasLower = codigoBarras.toLowerCase();
        final grupo = p.grupo.toLowerCase();
        
        // Extrair números dos códigos (removendo zeros à esquerda)
        final codigoNumeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');
        final codigoNumerosSemZeros = codigoNumeros.isEmpty ? '' : int.tryParse(codigoNumeros)?.toString() ?? codigoNumeros;
        final codigoBarrasNumeros = codigoBarras.replaceAll(RegExp(r'[^0-9]'), '');
        final codigoBarrasNumerosSemZeros = codigoBarrasNumeros.isEmpty ? '' : int.tryParse(codigoBarrasNumeros)?.toString() ?? codigoBarrasNumeros;

        // 1. Match exato case-insensitive de código (maior prioridade)
        if (codigoLower == queryLower || codigo == query) {
          return true;
        }
        
        // 2. Match exato case-insensitive de código de barras
        if (codigoBarrasLower == queryLower || codigoBarras == query) {
          return true;
        }
        
        // 3. Match exato numérico (ignorando zeros à esquerda e caracteres não numéricos)
        // Ex: "001" encontra "1", "PROD-001", "001", etc.
        if (queryNumerosSemZeros.isNotEmpty) {
          if (codigoNumerosSemZeros == queryNumerosSemZeros || 
              codigoBarrasNumerosSemZeros == queryNumerosSemZeros) {
            return true;
          }
          // Também verificar com zeros à esquerda preservados
          if (codigoNumeros == queryNumeros || codigoBarrasNumeros == queryNumeros) {
            return true;
          }
        }
        
        // 4. Código começa exatamente com o termo (case-insensitive)
        if (codigoLower.startsWith(queryLower) && codigoLower.isNotEmpty) {
          return true;
        }
        
        // 5. Código de barras começa exatamente com o termo
        if (codigoBarrasLower.startsWith(queryLower) && codigoBarrasLower.isNotEmpty) {
          return true;
        }
        
        // 6. Código numérico começa com o termo numérico
        // Para números pequenos, ser mais restritivo para evitar muitos resultados
        if (queryNumerosSemZeros.isNotEmpty) {
          // Se o termo numérico tem apenas 1 dígito, só buscar matches exatos
          // (já verificado acima no passo 3)
          // Não buscar por "começa com" para evitar trazer todos os códigos que contêm "1"
          
          // Se o termo numérico tem 2 dígitos, buscar matches exatos ou que começam
          if (queryNumerosSemZeros.length == 2) {
            if (codigoNumerosSemZeros.startsWith(queryNumerosSemZeros) &&
                codigoNumerosSemZeros.length <= 3) {
              return true;
            }
            if (codigoBarrasNumerosSemZeros.startsWith(queryNumerosSemZeros) &&
                codigoBarrasNumerosSemZeros.length <= 3) {
              return true;
            }
          }
          // Para números maiores (3+ dígitos), pode buscar por início
          else if (queryNumerosSemZeros.length >= 3) {
            if (codigoNumerosSemZeros.startsWith(queryNumerosSemZeros) ||
                codigoBarrasNumerosSemZeros.startsWith(queryNumerosSemZeros)) {
              return true;
            }
          }
        }
        
        // 7. Match exato do nome (case-insensitive)
        if (nome == queryLower) {
          return true;
        }
        
        // 8. Nome começa com o termo
        if (nome.startsWith(queryLower)) {
          return true;
        }
        
        // 9. Busca por palavras no nome (todas as palavras devem estar presentes)
        final palavrasQuery = queryLower.split(RegExp(r'[\s\-_]+')).where((p) => p.isNotEmpty).toList();
        if (palavrasQuery.length > 1) {
          final palavrasNome = nome.split(RegExp(r'[\s\-_]+'));
          final todasPalavrasEncontradas = palavrasQuery.every((palavra) =>
              palavrasNome.any((pn) => pn.startsWith(palavra) || pn.contains(palavra)));
          if (todasPalavrasEncontradas) {
            return true;
          }
        }
        
        // 10. Nome contém o termo (apenas se o termo tiver pelo menos 3 caracteres)
        if (query.length >= 3 && nome.contains(queryLower)) {
          return true;
        }
        
        // 11. Código contém o termo (apenas se o termo tiver pelo menos 3 caracteres)
        if (query.length >= 3 && codigoLower.contains(queryLower)) {
          return true;
        }
        
        // 12. Código de barras contém o termo (apenas se o termo tiver pelo menos 3 caracteres)
        if (query.length >= 3 && codigoBarrasLower.contains(queryLower)) {
          return true;
        }
        
        // 13. Código numérico contém o termo numérico (apenas se tiver 3+ dígitos)
        if (queryNumerosSemZeros.length >= 3 && 
            (codigoNumerosSemZeros.contains(queryNumerosSemZeros) ||
             codigoBarrasNumerosSemZeros.contains(queryNumerosSemZeros))) {
          return true;
        }
        
        // 14. Grupo contém o termo
        if (grupo.contains(queryLower)) {
          return true;
        }
        
        return false;
      }).toList();
      
      // Ordenar por relevância: matches exatos primeiro
      produtosFiltrados.sort((a, b) {
        final aNome = a.nome.toLowerCase();
        final bNome = b.nome.toLowerCase();
        final aCodigo = (a.codigo ?? '').trim().toLowerCase();
        final bCodigo = (b.codigo ?? '').trim().toLowerCase();
        final aCodigoBarras = (a.codigoBarras ?? '').trim().toLowerCase();
        final bCodigoBarras = (b.codigoBarras ?? '').trim().toLowerCase();
        
        // Extrair números sem zeros à esquerda
        final aCodigoNum = aCodigo.replaceAll(RegExp(r'[^0-9]'), '');
        final aCodigoNumSemZeros = aCodigoNum.isEmpty ? '' : int.tryParse(aCodigoNum)?.toString() ?? aCodigoNum;
        final bCodigoNum = bCodigo.replaceAll(RegExp(r'[^0-9]'), '');
        final bCodigoNumSemZeros = bCodigoNum.isEmpty ? '' : int.tryParse(bCodigoNum)?.toString() ?? bCodigoNum;
        final queryNumSemZeros = queryNumerosSemZeros;
        
        // 1. Priorizar matches exatos de código (case-insensitive)
        final aCodigoExato = aCodigo == queryLower || aCodigo == query;
        final bCodigoExato = bCodigo == queryLower || bCodigo == query;
        if (aCodigoExato != bCodigoExato) return aCodigoExato ? -1 : 1;
        
        // 2. Priorizar matches exatos de código de barras
        final aCodigoBarrasExato = aCodigoBarras == queryLower || aCodigoBarras == query;
        final bCodigoBarrasExato = bCodigoBarras == queryLower || bCodigoBarras == query;
        if (aCodigoBarrasExato != bCodigoBarrasExato) return aCodigoBarrasExato ? -1 : 1;
        
        // 3. Priorizar matches numéricos exatos (sem zeros à esquerda)
        if (queryNumSemZeros.isNotEmpty) {
          final aNumExato = aCodigoNumSemZeros == queryNumSemZeros;
          final bNumExato = bCodigoNumSemZeros == queryNumSemZeros;
          if (aNumExato != bNumExato) return aNumExato ? -1 : 1;
        }
        
        // 4. Priorizar matches exatos de nome
        final aNomeExato = aNome == queryLower;
        final bNomeExato = bNome == queryLower;
        if (aNomeExato != bNomeExato) return aNomeExato ? -1 : 1;
        
        // 5. Priorizar códigos que começam com o termo
        final aCodigoComeca = aCodigo.startsWith(queryLower);
        final bCodigoComeca = bCodigo.startsWith(queryLower);
        if (aCodigoComeca != bCodigoComeca) return aCodigoComeca ? -1 : 1;
        
        // 6. Priorizar nomes que começam com o termo
        final aNomeComeca = aNome.startsWith(queryLower);
        final bNomeComeca = bNome.startsWith(queryLower);
        if (aNomeComeca != bNomeComeca) return aNomeComeca ? -1 : 1;
        
        // 7. Por último, ordenar alfabeticamente por nome
        return aNome.compareTo(bNome);
      });
      
      _produtosFiltrados = produtosFiltrados.take(20).toList(); // Aumentado para 20 resultados
      _mostrarResultadosBusca = _produtosFiltrados.isNotEmpty;
      _indiceSelecionado = _produtosFiltrados.isNotEmpty ? 0 : -1;
    });
  }

  void _adicionarProduto(Produto produto, {int quantidade = 1}) {
    setState(() {
      // Verifica se o produto já está no carrinho
      final index = _carrinho.indexWhere(
        (item) => item.produto.id == produto.id,
      );

      if (index != -1) {
        // Incrementa quantidade
        _carrinho[index].quantidade += quantidade;
      } else {
        // Adiciona novo item
        _carrinho.add(ItemCarrinho(produto: produto, quantidade: quantidade));
      }

      // Limpa busca
      _buscaController.clear();
      _mostrarResultadosBusca = false;
    });

    // Mostra feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${produto.nome} adicionado ao pedido'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Foca novamente na busca
    _buscaFocusNode.requestFocus();
  }

  void _removerItem(int index) {
    final item = _carrinho[index];
    setState(() {
      _carrinho.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.produto.nome} removido'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Desfazer',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _carrinho.insert(index, item);
            });
          },
        ),
      ),
    );
  }

  void _alterarQuantidade(int index, int delta) {
    setState(() {
      final novaQuantidade = _carrinho[index].quantidade + delta;
      if (novaQuantidade > 0) {
        _carrinho[index].quantidade = novaQuantidade;
      } else if (novaQuantidade <= 0) {
        _removerItem(index);
      }
    });
  }

  double get _totalPedido {
    return _carrinho.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int get _totalItens {
    return _carrinho.fold(0, (sum, item) => sum + item.quantidade);
  }

  Future<void> _salvarPedido() async {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um produto ao pedido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);

    final pedido = Pedido(
      id:
          widget.pedidoExistente?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      numero: _numeroPedido,
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      dataPedido: widget.pedidoExistente?.dataPedido ?? DateTime.now(),
      status: _statusPedido,
      total: _totalPedido,
      observacoes: _observacoesController.text.isNotEmpty
          ? _observacoesController.text
          : null,
      produtos: _carrinho.map((item) => item.toItemPedido()).toList(),
      servicos: widget.pedidoExistente?.servicos ?? [],
      pagamentos: _pagamentos,
      createdAt: widget.pedidoExistente?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (widget.pedidoExistente != null) {
      dataService.updatePedido(pedido);
    } else {
      await dataService.addPedido(pedido);
    }

    if (mounted) {
      Navigator.of(context).pop(pedido);
    }
  }

  // Trata teclas especiais na busca
  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (_produtosFiltrados.isEmpty) return;

    setState(() {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _indiceSelecionado =
            (_indiceSelecionado + 1) % _produtosFiltrados.length;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _indiceSelecionado =
            (_indiceSelecionado - 1 + _produtosFiltrados.length) %
            _produtosFiltrados.length;
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_indiceSelecionado >= 0 &&
            _indiceSelecionado < _produtosFiltrados.length) {
          _adicionarProduto(_produtosFiltrados[_indiceSelecionado]);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _buscaController.clear();
        _mostrarResultadosBusca = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final clientes = dataService.clientes;
    final isEdicao = widget.pedidoExistente != null;
    final isPago = widget.pedidoExistente?.totalmenteRecebido ?? false;

    // Se o pedido já foi pago, mostrar tela de visualização apenas
    if (isPago) {
      return _buildTelaPedidoPago(widget.pedidoExistente!);
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            children: [
              Text(isEdicao ? 'Editar Pedido' : 'Novo Pedido'),
              if (_numeroPedido.isNotEmpty)
                Text(
                  _numeroPedido,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton.icon(
              onPressed: _carrinho.isNotEmpty ? _salvarPedido : null,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                isEdicao ? 'Atualizar' : 'Salvar',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Área de busca e seleção de cliente
            _buildCabecalho(clientes),

            // Lista de resultados da busca (overlay)
            if (_mostrarResultadosBusca) _buildResultadosBusca(),

            // Carrinho de itens
            Expanded(child: _buildCarrinho()),

            // Rodapé com total
            _buildRodape(),
          ],
        ),
      ),
    );
  }

  Widget _buildCabecalho(List<Cliente> clientes) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Seleção de cliente
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Cliente?>(
                  initialValue: _clienteSelecionado,
                  decoration: InputDecoration(
                    labelText: 'Cliente (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.person, color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  dropdownColor: const Color(0xFF23272A),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem<Cliente?>(
                      value: null,
                      child: Text(
                        'Sem cliente',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    ...clientes.map(
                      (cliente) => DropdownMenuItem(
                        value: cliente,
                        child: Text(cliente.nome),
                      ),
                    ),
                  ],
                  onChanged: (cliente) {
                    setState(() {
                      _clienteSelecionado = cliente;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Status do pedido
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getCorStatus(_statusPedido),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _getCorStatus(_statusPedido).withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: DropdownButton<String>(
                  value: _statusPedido,
                  underline: const SizedBox(),
                  dropdownColor: const Color(0xFF23272A),
                  isDense: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white,
                    size: 20,
                  ),
                  items: _statusDisponiveis
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(
                            status,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (status) {
                    if (status != null) {
                      setState(() {
                        _statusPedido = status;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Campo de busca de produtos
          KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: _onKeyEvent,
            child: TextField(
              controller: _buscaController,
              focusNode: _buscaFocusNode,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Buscar produto (código, nome, código de barras)...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _buscaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _buscaController.clear();
                        },
                      )
                    : const Icon(Icons.qr_code_scanner, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF181A1B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_indiceSelecionado >= 0 &&
                    _indiceSelecionado < _produtosFiltrados.length) {
                  _adicionarProduto(_produtosFiltrados[_indiceSelecionado]);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultadosBusca() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF23272A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _produtosFiltrados.length,
        itemBuilder: (context, index) {
          final produto = _produtosFiltrados[index];
          final isSelected = index == _indiceSelecionado;

          return InkWell(
            onTap: () => _adicionarProduto(produto),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Código
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      produto.codigo ?? '-',
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Nome e grupo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${produto.grupo} • Estoque: ${produto.estoque}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Preço
                  Text(
                    'R\$ ${produto.preco.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Botão adicionar
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () => _adicionarProduto(produto),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCarrinho() {
    if (_carrinho.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Carrinho vazio',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Busque e adicione produtos acima',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // +1 para cabeçalho, +1 para botão pagamentos, +1 para observações, +1 para widget pagamentos (se visível)
    final itemCount = _carrinho.length + 3 + (_mostrarPagamentos ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Primeiro item: cabeçalho do carrinho
        if (index == 0) {
          return _buildCabecalhoCarrinho();
        }

        // Itens do carrinho
        if (index <= _carrinho.length) {
          final item = _carrinho[index - 1];
          return _buildItemCarrinho(item, index - 1);
        }

        // Botão de pagamentos
        if (index == _carrinho.length + 1) {
          return _buildBotaoPagamentos();
        }

        // Widget de pagamentos (se visível)
        if (_mostrarPagamentos && index == _carrinho.length + 2) {
          return _buildSecaoPagamentos();
        }

        // Campo de observações (último)
        return _buildCampoObservacoes();
      },
    );
  }

  Widget _buildBotaoPagamentos() {
    final totalPagamentos = _pagamentos.fold(0.0, (sum, p) => sum + p.valor);
    final pagamentoCompleto = totalPagamentos >= _totalPedido;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _mostrarPagamentos = !_mostrarPagamentos;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: pagamentoCompleto
                    ? [Colors.green.shade800, Colors.green.shade600]
                    : [const Color(0xFF7B1FA2), const Color(0xFF9C27B0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (pagamentoCompleto ? Colors.green : Colors.purple)
                      .withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    pagamentoCompleto ? Icons.check_circle : Icons.payment,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pagamentoCompleto
                            ? 'Pagamento Completo'
                            : 'Formas de Pagamento',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pagamentos.isEmpty
                            ? 'Toque para lançar pagamentos'
                            : '${_pagamentos.length} ${_pagamentos.length == 1 ? 'forma' : 'formas'} • R\$ ${totalPagamentos.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _mostrarPagamentos ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecaoPagamentos() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: PagamentoWidget(
        totalPedido: _totalPedido,
        pagamentos: _pagamentos,
        clienteId: _clienteSelecionado
            ?.id, // Passa o clienteId para validação de crediário/fiado
        onPagamentosChanged: (novosPagamentos) {
          setState(() {
            _pagamentos = novosPagamentos;
          });
        },
      ),
    );
  }

  Widget _buildCabecalhoCarrinho() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            'ITENS DO PEDIDO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_totalItens ${_totalItens == 1 ? 'item' : 'itens'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCarrinho(ItemCarrinho item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1a237e), const Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Info do produto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.produto.codigo ?? '-',
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.produto.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'R\$ ${item.precoUnitario.toStringAsFixed(2)} / ${item.produto.unidade}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Controle de quantidade
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.remove,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _alterarQuantidade(index, -1),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 40),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.quantidade}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add,
                      color: Colors.greenAccent,
                      size: 20,
                    ),
                    onPressed: () => _alterarQuantidade(index, 1),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Subtotal
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'R\$ ${item.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () => _removerItem(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampoObservacoes() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _observacoesController,
        style: const TextStyle(color: Colors.white),
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Observações (opcional)',
          labelStyle: const TextStyle(color: Colors.white70),
          hintText: 'Informações adicionais sobre o pedido...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: const Icon(Icons.notes, color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF181A1B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildRodape() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1a237e), const Color(0xFF0d47a1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Resumo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_totalItens ${_totalItens == 1 ? 'item' : 'itens'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'R\$ ${_totalPedido.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                ],
              ),
            ),

            // Botão finalizar
            ElevatedButton.icon(
              onPressed: _carrinho.isNotEmpty ? _salvarPedido : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.check, size: 24),
              label: Text(
                widget.pedidoExistente != null ? 'Atualizar' : 'Finalizar',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelaPedidoPago(Pedido pedido) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            children: [
              const Text('Pedido Pago'),
              Text(
                pedido.numero,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.greenAccent.withOpacity(0.9),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Badge PAGO
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade800, Colors.green.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text(
                      'PEDIDO PAGO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Este pedido não pode ser alterado',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Info do cliente
              if (pedido.clienteNome != null) ...[
                _buildInfoCard('Cliente', Icons.person, [
                  _buildInfoItem('Nome', pedido.clienteNome!),
                  if (pedido.clienteTelefone != null)
                    _buildInfoItem('Telefone', pedido.clienteTelefone!),
                  if (pedido.clienteEndereco != null)
                    _buildInfoItem('Endereço', pedido.clienteEndereco!),
                ]),
                const SizedBox(height: 16),
              ],

              // Itens do pedido
              _buildInfoCard('Itens do Pedido', Icons.shopping_bag, [
                ...pedido.produtos.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.quantidade}x',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        Text(
                          'R\$ ${(item.preco * item.quantidade).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.greenAccent),
                        ),
                      ],
                    ),
                  ),
                ),
                if (pedido.servicos.isNotEmpty) ...[
                  const Divider(color: Colors.white24),
                  ...pedido.servicos.map(
                    (servico) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.build,
                              color: Colors.purple,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              servico.descricao,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Text(
                            'R\$ ${servico.valor.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.greenAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 16),

              // Pagamentos
              _buildInfoCard(
                'Pagamentos',
                Icons.payment,
                pedido.pagamentos
                    .map(
                      (pag) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              pag.recebido ? Icons.check_circle : Icons.pending,
                              color: pag.recebido
                                  ? Colors.greenAccent
                                  : Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                pag.tipo.nome,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            Text(
                              'R\$ ${pag.valor.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: pag.recebido
                                    ? Colors.greenAccent
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),

              // Total
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL PAGO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String titulo, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white54, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Em Andamento':
        return Colors.blue;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/data_service.dart';
import '../services/local_storage_service.dart';
import '../models/produto.dart';
import '../models/servico.dart';
import '../models/cliente.dart';
import '../models/pedido.dart';
import '../models/item_pedido.dart';
import '../models/item_servico.dart';
import '../models/forma_pagamento.dart';
import '../models/venda_balcao.dart';
import 'historico_vendas_page.dart';
import 'cliente_detalhes_page.dart';
import 'pdv_page.dart';
import 'home_page.dart';
import '../theme.dart';

/// Item no carrinho da venda direta
class ItemCarrinho {
  final String id;
  final String nome;
  final double preco;
  int quantidade;
  final bool isServico;
  double desconto; // Desconto em valor (R$)

  ItemCarrinho({
    required this.id,
    required this.nome,
    required this.preco,
    this.quantidade = 1,
    this.isServico = false,
    this.desconto = 0.0,
  });

  double get subtotal => (preco * quantidade) - desconto;
  double get subtotalSemDesconto => preco * quantidade;

  // Serialização para persistência
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'quantidade': quantidade,
      'isServico': isServico,
      'desconto': desconto,
    };
  }

  factory ItemCarrinho.fromMap(Map<String, dynamic> map) {
    return ItemCarrinho(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      preco: (map['preco'] ?? 0.0).toDouble(),
      quantidade: map['quantidade'] ?? 1,
      isServico: map['isServico'] ?? false,
      desconto: (map['desconto'] ?? 0.0).toDouble(),
    );
  }
}

/// Página de Venda Direta no PDV - Versão Melhorada
class VendaDiretaPage extends StatefulWidget {
  final Pedido? pedidoParaEditar; // Pedido/venda salva para continuar
  final VoidCallback? onVendaFinalizada; // Callback quando finalizar
  final Cliente? clienteInicial; // Cliente já selecionado
  final List<ItemPedido>? itensParaRepetir; // Itens para repetir venda
  final List<ItemServico>? servicosParaRepetir; // Serviços para repetir venda

  const VendaDiretaPage({
    super.key,
    this.pedidoParaEditar,
    this.onVendaFinalizada,
    this.clienteInicial,
    this.itensParaRepetir,
    this.servicosParaRepetir,
  });

  @override
  State<VendaDiretaPage> createState() => _VendaDiretaPageState();
}

class _VendaDiretaPageState extends State<VendaDiretaPage> {
  final _buscaController = TextEditingController();
  final _buscaFocusNode = FocusNode();
  String _termoBusca = '';
  final List<ItemCarrinho> _carrinho = [];
  Cliente? _clienteSelecionado;
  String? _categoriaAtiva;
  int _quantidadeDigitada = 1;
  Pedido? _pedidoOriginal; // Pedido original sendo editado
  List<PagamentoPedido> _pagamentosSalvos =
      []; // Pagamentos do pedido sendo editado
  double _descontoTotal = 0.0; // Desconto total da venda (R$)

  final LocalStorageService _storage = LocalStorageService();
  static const String _keyCarrinhoPDV = 'exodo_carrinho_pdv';
  static const String _keyClientePDV = 'exodo_cliente_pdv';
  static const String _keyDescontoTotalPDV = 'exodo_desconto_total_pdv';

  @override
  void initState() {
    super.initState();
    
    // Solicitar abertura de caixa quando o PDV é aberto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataService = Provider.of<DataService>(context, listen: false);
      if (!dataService.caixaAberto) {
        // Mostrar diálogo para solicitar valor de abertura
        _solicitarAberturaCaixa(context, dataService);
      }
    });
    
    // Se veio um pedido para editar, carregar os itens
    if (widget.pedidoParaEditar != null) {
      _carregarPedidoParaEditar(widget.pedidoParaEditar!);
    } else {
      // Carregar cliente inicial se fornecido
      if (widget.clienteInicial != null) {
        _clienteSelecionado = widget.clienteInicial;
        _salvarClienteSelecionado();
      } else {
        // Tentar carregar cliente salvo (assíncrono após o frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _carregarClienteSelecionado();
        });
      }
      // Carregar itens para repetir venda
      if (widget.itensParaRepetir != null) {
        _carregarItensParaRepetir();
      } else {
        // Tentar carregar carrinho salvo (assíncrono após o frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _carregarCarrinhoSalvo();
        });
      }
    }
  }

  void _carregarItensParaRepetir() {
    // Carregar produtos
    if (widget.itensParaRepetir != null) {
      for (final item in widget.itensParaRepetir!) {
        _carrinho.add(
          ItemCarrinho(
            id: item.id,
            nome: item.nome,
            preco: item.preco,
            quantidade: item.quantidade,
            isServico: false,
          ),
        );
      }
    }
    // Carregar serviços
    if (widget.servicosParaRepetir != null) {
      for (final servico in widget.servicosParaRepetir!) {
        _carrinho.add(
          ItemCarrinho(
            id: servico.id,
            nome: servico.descricao,
            preco: servico.valor,
            quantidade: 1,
            isServico: true,
          ),
        );
      }
    }
  }

  void _carregarPedidoParaEditar(Pedido pedido) {
    _pedidoOriginal = pedido;

    // Carregar pagamentos salvos
    _pagamentosSalvos = List.from(pedido.pagamentos);

    // Carregar produtos
    for (final produto in pedido.produtos) {
      _carrinho.add(
        ItemCarrinho(
          id: produto.id,
          nome: produto.nome,
          preco: produto.preco,
          quantidade: produto.quantidade,
          isServico: false,
        ),
      );
    }

    // Carregar serviços
    for (final servico in pedido.servicos) {
      _carrinho.add(
        ItemCarrinho(
          id: servico.id,
          nome: servico.descricao,
          preco: servico.valor,
          quantidade: 1,
          isServico: true,
        ),
      );
    }

    // Carregar cliente se existir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pedido.clienteId != null) {
        final dataService = Provider.of<DataService>(context, listen: false);
        final cliente = dataService.clientes
            .where((c) => c.id == pedido.clienteId)
            .firstOrNull;
        if (cliente != null) {
          setState(() => _clienteSelecionado = cliente);
        }
      }
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    super.dispose();
  }

  // ============ Métodos de Persistência do Carrinho ============

  /// Carrega o carrinho salvo do localStorage
  Future<void> _carregarCarrinhoSalvo() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não carregar carrinho salvo se estiver editando um pedido
        return;
      }

      final carrinhoMap = await _storage.carregarLista(_keyCarrinhoPDV);
      if (carrinhoMap.isNotEmpty) {
        setState(() {
          _carrinho.clear();
          _carrinho.addAll(
            carrinhoMap.map((map) => ItemCarrinho.fromMap(map)),
          );
        });
        debugPrint('>>> ✓ Carrinho carregado: ${_carrinho.length} itens');
      }
      
      // Carregar desconto total
      final descontoTotalMap = await _storage.carregar(_keyDescontoTotalPDV);
      if (descontoTotalMap != null && descontoTotalMap is double) {
        setState(() {
          _descontoTotal = descontoTotalMap;
        });
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar carrinho: $e');
    }
  }

  /// Salva o carrinho atual no localStorage
  Future<void> _salvarCarrinho() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não salvar se estiver editando um pedido
        return;
      }

      await _storage.salvarLista(_keyCarrinhoPDV, _carrinho);
      await _storage.salvar(_keyDescontoTotalPDV, _descontoTotal);
      debugPrint('>>> ✓ Carrinho salvo: ${_carrinho.length} itens');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar carrinho: $e');
    }
  }

  /// Carrega o cliente selecionado salvo
  Future<void> _carregarClienteSelecionado() async {
    try {
      if (widget.pedidoParaEditar != null || widget.clienteInicial != null) {
        // Não carregar se já tiver cliente definido
        return;
      }

      final clienteMap = await _storage.carregarLista(_keyClientePDV);
      if (clienteMap.isNotEmpty) {
        final clienteData = clienteMap.first;
        final clienteId = clienteData['id'] as String?;
        
        if (clienteId != null) {
          final dataService = Provider.of<DataService>(context, listen: false);
          final cliente = dataService.clientes
              .where((c) => c.id == clienteId)
              .firstOrNull;
          
          if (cliente != null) {
            setState(() {
              _clienteSelecionado = cliente;
            });
            debugPrint('>>> ✓ Cliente carregado: ${cliente.nome}');
          }
        }
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar cliente: $e');
    }
  }

  /// Salva o cliente selecionado no localStorage
  Future<void> _salvarClienteSelecionado() async {
    try {
      if (_clienteSelecionado != null) {
        await _storage.salvarLista(
          _keyClientePDV,
          [{'id': _clienteSelecionado!.id}],
        );
        debugPrint('>>> ✓ Cliente salvo: ${_clienteSelecionado!.nome}');
      } else {
        // Se não há cliente, limpar do storage (salvar lista vazia)
        await _storage.salvarLista(_keyClientePDV, []);
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar cliente: $e');
    }
  }

  /// Limpa o carrinho e cliente salvos (quando finalizar venda)
  Future<void> _limparCarrinhoSalvo() async {
    try {
      // Limpar carrinho (salvar lista vazia)
      await _storage.salvarLista(_keyCarrinhoPDV, []);
      // Limpar cliente (salvar lista vazia)
      await _storage.salvarLista(_keyClientePDV, []);
      // Limpar desconto total
      await _storage.salvar(_keyDescontoTotalPDV, 0.0);
      debugPrint('>>> ✓ Carrinho, cliente e desconto limpos do storage');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao limpar carrinho: $e');
    }
  }

  double get _totalCarrinho {
    final subtotalItens = _carrinho.fold(0.0, (sum, item) => sum + item.subtotal);
    return subtotalItens - _descontoTotal;
  }
  
  double get _totalCarrinhoSemDesconto =>
      _carrinho.fold(0.0, (sum, item) => sum + item.subtotalSemDesconto);

  int get _totalItens =>
      _carrinho.fold(0, (sum, item) => sum + item.quantidade);

  void _adicionarAoCarrinho(dynamic item) {
    final isServico = item is Servico;
    final id = item.id;
    final nome = item.nome;
    final preco = isServico ? item.preco : (item as Produto).precoAtual;

    // Verificar se já existe no carrinho
    final index = _carrinho.indexWhere((c) => c.id == id);
    if (index >= 0) {
      setState(() {
        _carrinho[index].quantidade += _quantidadeDigitada;
      });
    } else {
      setState(() {
        _carrinho.add(
          ItemCarrinho(
            id: id,
            nome: nome,
            preco: preco,
            isServico: isServico,
            quantidade: _quantidadeDigitada,
          ),
        );
      });
    }

    // Resetar quantidade e limpar busca
    setState(() {
      _quantidadeDigitada = 1;
      _termoBusca = '';
    });
    _buscaController.clear();
    _buscaFocusNode.requestFocus();
    
    // Salvar carrinho automaticamente
    _salvarCarrinho();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ $nome adicionado'),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 20,
          right: 20,
        ),
      ),
    );
  }

  void _alterarQuantidade(int index, int delta) {
    setState(() {
      _carrinho[index].quantidade += delta;
      if (_carrinho[index].quantidade <= 0) {
        _carrinho.removeAt(index);
      }
    });
    // Salvar carrinho automaticamente
    _salvarCarrinho();
  }

  void _removerItem(int index) {
    setState(() {
      _carrinho.removeAt(index);
    });
    // Salvar carrinho automaticamente
    _salvarCarrinho();
  }

  void _aplicarDescontoItem(int index) {
    final item = _carrinho[index];
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final subtotalSemDesconto = item.subtotalSemDesconto;
    
    final descontoController = TextEditingController(
      text: item.desconto > 0 ? item.desconto.toStringAsFixed(2) : '0.00',
    );
    final descontoPercentualController = TextEditingController(
      text: item.desconto > 0 
          ? ((item.desconto / subtotalSemDesconto) * 100).toStringAsFixed(2)
          : '0.00',
    );
    bool usarPercentual = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.discount_rounded, color: Colors.orangeAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Desconto no Item',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Subtotal: ${formatoMoeda.format(subtotalSemDesconto)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor (R\$)'),
                        selected: !usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Percentual (%)'),
                        selected: usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usarPercentual ? descontoPercentualController : descontoController,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: usarPercentual ? 'Desconto (%)' : 'Desconto (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: usarPercentual ? '' : 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    setDialogState(() {
                      if (usarPercentual) {
                        final percentual = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final valorDesconto = (subtotalSemDesconto * percentual) / 100;
                        descontoController.text = valorDesconto.toStringAsFixed(2);
                      } else {
                        final valor = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final percentual = subtotalSemDesconto > 0 
                            ? (valor / subtotalSemDesconto) * 100 
                            : 0.0;
                        descontoPercentualController.text = percentual.toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (usarPercentual)
                  Text(
                    'Valor: ${formatoMoeda.format(double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    'Percentual: ${descontoPercentualController.text}%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total com desconto:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        formatoMoeda.format(
                          subtotalSemDesconto - 
                          (double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)
                        ),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
              onPressed: () {
                setState(() {
                  _carrinho[index].desconto = 0.0;
                });
                Navigator.pop(dialogContext);
                _salvarCarrinho();
              },
              child: const Text('Remover Desconto', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                final desconto = double.tryParse(
                  descontoController.text.replaceAll(',', '.'),
                ) ?? 0.0;
                
                if (desconto < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Desconto não pode ser negativo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (desconto > subtotalSemDesconto) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Desconto não pode ser maior que ${formatoMoeda.format(subtotalSemDesconto)}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                setState(() {
                  _carrinho[index].desconto = desconto;
                });
                Navigator.pop(dialogContext);
                _salvarCarrinho();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Desconto de ${formatoMoeda.format(desconto)} aplicado'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _aplicarDescontoTotal() {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final subtotalSemDesconto = _totalCarrinhoSemDesconto;
    
    final descontoController = TextEditingController(
      text: _descontoTotal > 0 ? _descontoTotal.toStringAsFixed(2) : '0.00',
    );
    final descontoPercentualController = TextEditingController(
      text: _descontoTotal > 0 
          ? ((_descontoTotal / subtotalSemDesconto) * 100).toStringAsFixed(2)
          : '0.00',
    );
    bool usarPercentual = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.discount_rounded, color: Colors.orangeAccent, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Desconto Total',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Subtotal dos itens: ${formatoMoeda.format(subtotalSemDesconto)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor (R\$)'),
                        selected: !usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Percentual (%)'),
                        selected: usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usarPercentual ? descontoPercentualController : descontoController,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: usarPercentual ? 'Desconto (%)' : 'Desconto (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: usarPercentual ? '' : 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    setDialogState(() {
                      if (usarPercentual) {
                        final percentual = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final valorDesconto = (subtotalSemDesconto * percentual) / 100;
                        descontoController.text = valorDesconto.toStringAsFixed(2);
                      } else {
                        final valor = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final percentual = subtotalSemDesconto > 0 
                            ? (valor / subtotalSemDesconto) * 100 
                            : 0.0;
                        descontoPercentualController.text = percentual.toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (usarPercentual)
                  Text(
                    'Valor: ${formatoMoeda.format(double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    'Percentual: ${descontoPercentualController.text}%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total final:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        formatoMoeda.format(
                          subtotalSemDesconto - 
                          (double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)
                        ),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
              onPressed: () async {
                setState(() {
                  _descontoTotal = 0.0;
                });
                await _storage.salvar(_keyDescontoTotalPDV, 0.0);
                Navigator.pop(dialogContext);
              },
              child: const Text('Remover Desconto', style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                final desconto = double.tryParse(
                  descontoController.text.replaceAll(',', '.'),
                ) ?? 0.0;
                
                if (desconto < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Desconto não pode ser negativo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (desconto > subtotalSemDesconto) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Desconto não pode ser maior que ${formatoMoeda.format(subtotalSemDesconto)}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                setState(() {
                  _descontoTotal = desconto;
                });
                await _storage.salvar(_keyDescontoTotalPDV, desconto);
                Navigator.pop(dialogContext);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Desconto total de ${formatoMoeda.format(desconto)} aplicado'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _limparCarrinho() {
    if (_carrinho.isEmpty) return;
    setState(() {
      _carrinho.clear();
    });
    // Salvar carrinho vazio
    _salvarCarrinho();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Limpar Carrinho', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Deseja remover todos os itens do carrinho?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _carrinho.clear();
                _clienteSelecionado = null;
                _pagamentosSalvos = [];
              });
              // Salvar carrinho vazio
              _salvarCarrinho();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  List<String> _getCategorias(DataService dataService) {
    final categorias = dataService.produtos
        .map((p) => p.grupo)
        .toSet()
        .toList();
    categorias.sort();
    return categorias;
  }

  List<Produto> _getProdutosPorCategoria(DataService dataService) {
    if (_categoriaAtiva == null) return [];
    return dataService.produtos
        .where((p) => p.grupo == _categoriaAtiva)
        .toList();
  }

  List<dynamic> _buscarItens(DataService dataService) {
    if (_termoBusca.isEmpty) return [];

    final buscaLower = _termoBusca.toLowerCase().trim();
    final ehNumero = RegExp(r'^[0-9]+$').hasMatch(buscaLower);

    // Se for número, mínimo 1 caractere; se for texto, mínimo 2 caracteres
    if (!ehNumero && buscaLower.length < 2) return [];

    final resultados = <dynamic>[];

    for (final produto in dataService.produtos) {
      // BUSCA POR NÚMERO DO CÓDIGO - EXATA (ex: "1" encontra APENAS COD-1, não COD-10)
      if (ehNumero && produto.codigo != null) {
        final numCodigo = produto.codigo!.replaceAll(RegExp(r'[^0-9]'), '');
        if (numCodigo == buscaLower) {
          resultados.add(produto);
        }
        // Não continua buscando em outros lugares se for número
        continue;
      }

      // BUSCA POR CÓDIGO DE BARRAS EXATO
      if (ehNumero && produto.codigoBarras != null) {
        if (produto.codigoBarras == buscaLower) {
          resultados.add(produto);
        }
        continue;
      }

      // BUSCA POR CÓDIGO COMPLETO (cod-1, cod-2, etc) - só para texto
      if (!ehNumero && produto.codigo != null) {
        final codigoLower = produto.codigo!.toLowerCase();
        if (codigoLower.startsWith(buscaLower)) {
          resultados.add(produto);
          continue;
        }
      }

      // BUSCA POR NOME - SOMENTE palavras que COMEÇAM com o termo
      if (!ehNumero) {
        final palavras = produto.nome
            .toLowerCase()
            .replaceAll(RegExp(r'[0-9]+'), ' ')
            .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 2)
            .toList();

        if (palavras.any((palavra) => palavra.startsWith(buscaLower))) {
          resultados.add(produto);
        }
      }
    }

    // Buscar serviços também (só por nome, não por código)
    if (!ehNumero) {
      for (final servico in dataService.tiposServico) {
        final palavras = servico.nome
            .toLowerCase()
            .replaceAll(RegExp(r'[0-9]+'), ' ')
            .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 2)
            .toList();

        if (palavras.any((palavra) => palavra.startsWith(buscaLower))) {
          resultados.add(servico);
        }
      }
    }

    return resultados;
  }

  void _solicitarAberturaCaixa(BuildContext context, DataService dataService) {
    final valorController = TextEditingController(text: '0.00');
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      barrierDismissible: false, // Não permite fechar sem abrir o caixa
      builder: (dialogContext) => PopScope(
        canPop: false, // Impede fechar com back button
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.green.withOpacity(0.4),
                      Colors.greenAccent.withOpacity(0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: Colors.greenAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Abrir Caixa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Para iniciar as vendas, é necessário abrir o caixa.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: valorController,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Valor Inicial (R\$)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixText: 'R\$ ',
                      prefixStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.green, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Informe o valor inicial';
                      }
                      final valor = double.tryParse(
                        value.replaceAll('.', '').replaceAll(',', '.'),
                      );
                      if (valor == null || valor < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.withOpacity(0.8),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O valor inicial será usado para calcular o total esperado no fechamento do caixa.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (route) => false,
                );
              },
              child: const Text(
                'Fechar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final valor = double.parse(
                      valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                    );

                    await dataService.abrirCaixaComValor(valor);

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Caixa aberto com ${formatoMoeda.format(valor)}',
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao abrir caixa: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Abrir Caixa',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  void _finalizarVenda(DataService dataService) {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Adicione itens ao carrinho'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
        ),
      );
      return;
    }
    
    // Verificar se o caixa está aberto antes de finalizar venda
    if (!dataService.caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('É necessário abrir o caixa antes de realizar vendas'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Abrir',
            textColor: Colors.white,
            onPressed: () {
              _solicitarAberturaCaixa(context, dataService);
            },
          ),
        ),
      );
      return;
    }
    
    _mostrarDialogPagamento(dataService);
  }

  void _selecionarCliente(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSeletorCliente(dataService),
    );
  }

  void _abrirHistoricoVendas() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoricoVendasPage()),
    );
  }

  void _mostrarDialogPagamento(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DialogPagamentoPDV(
        totalCarrinho: _totalCarrinho,
        pagamentosIniciais: _pagamentosSalvos,
        cliente: _clienteSelecionado,
        onConfirmar: (listaPagamentos) {
          Navigator.pop(context);
          _concluirVendaComPagamentos(dataService, listaPagamentos);
        },
        onSalvarPendente: (listaPagamentos) {
          Navigator.pop(context);
          _salvarVendaPendente(dataService, listaPagamentos);
        },
      ),
    );
  }

  void _concluirVendaComPagamentos(
    DataService dataService,
    List<PagamentoPedido> pagamentos,
  ) {
    final uuid = const Uuid();
    final numero = dataService.getProximoNumeroVenda();

    // Atualizar status de recebido dos pagamentos instantâneos
    // (Dinheiro, PIX, Cartão) devem ser marcados como recebidos ao finalizar
    final pagamentosAtualizados = pagamentos.map((p) {
      final isInstantaneo =
          p.tipo == TipoPagamento.dinheiro ||
          p.tipo == TipoPagamento.pix ||
          p.tipo == TipoPagamento.cartaoCredito ||
          p.tipo == TipoPagamento.cartaoDebito;

      // Se é pagamento instantâneo e não é parcela, marcar como recebido
      if (isInstantaneo && !p.isParcela) {
        return PagamentoPedido(
          id: p.id,
          tipo: p.tipo,
          valor: p.valor,
          recebido: true, // Marcar como recebido
          dataRecebimento: DateTime.now(),
          dataVencimento: p.dataVencimento,
          parcelas: p.parcelas,
          numeroParcela: p.numeroParcela,
          parcelamentoId: p.parcelamentoId,
          observacao: p.observacao,
          valorRecebido: p.valorRecebido,
          troco: p.troco,
        );
      }
      return p;
    }).toList();

    // Separar produtos e serviços
    final produtos = _carrinho
        .where((item) => !item.isServico)
        .map(
          (item) => ItemPedido(
            id: item.id,
            nome: item.nome,
            quantidade: item.quantidade,
            preco: item.preco,
          ),
        )
        .toList();

    final List<ItemServico> servicos = _carrinho
        .where((item) => item.isServico)
        .map<ItemServico>(
          (item) => ItemServico(
            id: item.id,
            descricao: item.nome,
            valor: item.preco * item.quantidade,
          ),
        )
        .toList();

    // Calcular totais usando os pagamentos atualizados
    final totalLancado = pagamentosAtualizados.fold(
      0.0,
      (sum, p) => sum + p.valor,
    );
    final totalRecebido = pagamentosAtualizados
        .where((p) => p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);

    // Determinar status
    String statusPedido;
    if (totalRecebido >= _totalCarrinho - 0.01) {
      statusPedido = 'Pago';
    } else if (totalLancado >= _totalCarrinho - 0.01) {
      // Tem pagamentos lançados mas não recebidos (boleto, crediário)
      final temPendente = pagamentosAtualizados.any((p) => !p.recebido);
      statusPedido = temPendente ? 'Pendente' : 'Pago';
    } else {
      statusPedido = 'Pendente';
    }

    final pedido = Pedido(
      id: uuid.v4(),
      numero: numero,
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      clienteTelefone: _clienteSelecionado?.telefone,
      clienteEndereco: _clienteSelecionado?.endereco,
      dataPedido: DateTime.now(),
      status: statusPedido,
      produtos: produtos,
      servicos: servicos,
      pagamentos: pagamentosAtualizados,
    );

    dataService.addPedido(pedido);

    // Criar/Atualizar VendaBalcao com o tipo de pagamento correto
    // Determinar tipo de pagamento principal - SEMPRE usar o tipo escolhido pelo usuário
    TipoPagamento tipoPagamentoVenda = TipoPagamento.outro;
    
    // Verificar se estava editando uma venda salva (tipo "outro")
    VendaBalcao? vendaOriginal;
    if (_pedidoOriginal != null) {
      vendaOriginal = dataService.vendasBalcao
          .where((v) => v.numero == _pedidoOriginal!.numero)
          .firstOrNull;
    }
    
    // SEMPRE usar o tipo do primeiro pagamento se houver pagamentos
    // Isso garante que o tipo escolhido pelo usuário seja respeitado
    if (pagamentosAtualizados.isNotEmpty) {
      // Pegar o tipo do primeiro pagamento (que é o principal escolhido)
      tipoPagamentoVenda = pagamentosAtualizados.first.tipo;
      
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  TIPO DE PAGAMENTO DA VENDA                   ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      debugPrint('>>> Tipo escolhido: ${tipoPagamentoVenda.name}');
      debugPrint('>>> Total de pagamentos: ${pagamentosAtualizados.length}');
      for (var i = 0; i < pagamentosAtualizados.length; i++) {
        debugPrint('>>>   Pagamento ${i + 1}: ${pagamentosAtualizados[i].tipo.name} - R\$ ${pagamentosAtualizados[i].valor.toStringAsFixed(2)}');
      }
    } else {
      // Sem pagamentos definidos, manter como "outro"
      tipoPagamentoVenda = TipoPagamento.outro;
      debugPrint('>>> AVISO: Nenhum pagamento definido, usando tipo "outro"');
    }

    // Criar itens da venda balcão
    final itensVenda = _carrinho
        .map(
          (item) => ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: item.isServico,
          ),
        )
        .toList();

    final vendaBalcao = VendaBalcao(
      id: uuid.v4(),
      numero: numero,
      dataVenda: DateTime.now(),
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      clienteTelefone: _clienteSelecionado?.telefone,
      itens: itensVenda,
      tipoPagamento: tipoPagamentoVenda,
      valorTotal: _totalCarrinho,
      valorRecebido: totalRecebido > 0 ? totalRecebido : null,
      troco: pagamentosAtualizados
          .where((p) => p.troco != null && p.troco! > 0)
          .fold<double?>(null, (sum, p) => (sum ?? 0) + (p.troco ?? 0)),
    );

    dataService.addVendaBalcao(vendaBalcao);

    // ATUALIZAR ESTOQUE - Dar baixa nos produtos vendidos
    // Apenas para vendas pagas (não pendentes)
    if (statusPedido == 'Pago' || totalRecebido > 0) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  ATUALIZANDO ESTOQUE - VENDA FINALIZADA       ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      
      for (final item in _carrinho) {
        // Apenas produtos (não serviços)
        if (!item.isServico) {
          try {
            final produto = dataService.produtos.firstWhere(
              (p) => p.id == item.id,
            );
            
            final estoqueAnterior = produto.estoque;
            final novoEstoque = (produto.estoque - item.quantidade) < 0 
                ? 0 
                : (produto.estoque - item.quantidade);
            
            dataService.updateProduto(
              produto.copyWith(
                estoque: novoEstoque,
                updatedAt: DateTime.now(),
              ),
            );
            
            debugPrint('>>> ✓ Baixa no estoque:');
            debugPrint('>>>   Produto: ${produto.nome}');
            debugPrint('>>>   Estoque anterior: $estoqueAnterior');
            debugPrint('>>>   Quantidade vendida: ${item.quantidade}');
            debugPrint('>>>   Novo estoque: $novoEstoque');
          } catch (e) {
            debugPrint('>>> ERRO ao dar baixa no produto ${item.nome} (id: ${item.id}): $e');
          }
        }
      }
      debugPrint('');
    }

    // Se teve pagamento fiado, atualizar saldo devedor do cliente
    final valorFiado = pagamentosAtualizados
        .where((p) => p.tipo == TipoPagamento.fiado && !p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);

    if (valorFiado > 0 && _clienteSelecionado != null) {
      final clienteAtualizado = _clienteSelecionado!.copyWith(
        saldoDevedor: _clienteSelecionado!.saldoDevedor + valorFiado,
        updatedAt: DateTime.now(),
      );
      dataService.updateCliente(clienteAtualizado);
    }

    // Se estava editando um pedido/venda salva, remover o antigo
    // (a venda original já foi buscada acima, então podemos deletar aqui)
    if (_pedidoOriginal != null) {
      dataService.deletePedido(_pedidoOriginal!.id);
      if (vendaOriginal != null) {
        dataService.deleteVendaBalcao(vendaOriginal.id);
      }
      _pedidoOriginal = null;
    }

    // Chamar callback se existir
    widget.onVendaFinalizada?.call();

    // Mostrar sucesso baseado no tipo de pagamento
    final temParcelamento = pagamentosAtualizados.any((p) => p.isParcela);
    final temPendente = pagamentosAtualizados.any((p) => !p.recebido);

    if (temParcelamento) {
      final parcelasCount = pagamentosAtualizados
          .where((p) => p.isParcela)
          .length;
      final valorParcela = pagamentosAtualizados
          .firstWhere((p) => p.isParcela)
          .valor;
      _mostrarSucessoVendaParcelada(parcelasCount, valorParcela, numero);
    } else if (temPendente) {
      final tipoPrincipal = pagamentosAtualizados.first.tipo;
      final dataVenc =
          pagamentosAtualizados.first.dataVencimento ??
          DateTime.now().add(const Duration(days: 30));
      _mostrarSucessoVendaCredito(
        _totalCarrinho,
        numero,
        tipoPrincipal,
        dataVenc,
      );
    } else {
      // Pagamento normal
      final troco = pagamentosAtualizados
          .where((p) => p.troco != null && p.troco! > 0)
          .fold(0.0, (sum, p) => sum + (p.troco ?? 0));
      if (troco > 0) {
        _mostrarNotificacaoSucesso(
          icone: Icons.check_circle_rounded,
          titulo: 'Venda Concluída!',
          subtitulo: numero,
          cor: Colors.green,
          valorFormatado: 'R\$ ${_totalCarrinho.toStringAsFixed(2)}',
          info: 'Troco: R\$ ${troco.toStringAsFixed(2)}',
          duracao: const Duration(seconds: 3),
        );
        setState(() {
          _carrinho.clear();
          _clienteSelecionado = null;
          _pagamentosSalvos = [];
        });
        // Limpar carrinho salvo após finalizar venda
        _limparCarrinhoSalvo();
      } else {
        _mostrarSucessoVenda(_totalCarrinho, numero);
      }
    }

    // Limpar carrinho
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
      _pagamentosSalvos = [];
    });
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
  }

  // Salvar venda pendente para receber depois
  void _salvarVendaPendente(
    DataService dataService,
    List<PagamentoPedido> pagamentosDoDialog,
  ) {
    final uuid = const Uuid();

    // Criar itens da venda balcão
    final itensVenda = _carrinho
        .map(
          (item) => ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: item.isServico,
          ),
        )
        .toList();

    // Determinar tipo de pagamento principal (se houver)
    TipoPagamento tipoPrincipal = TipoPagamento.outro;
    if (pagamentosDoDialog.isNotEmpty) {
      tipoPrincipal = pagamentosDoDialog.first.tipo;
    }

    // Criar venda balcão (sem pagamento)
    final vendaBalcao = VendaBalcao(
      id: uuid.v4(),
      numero: dataService.getProximoNumeroVenda(),
      dataVenda: DateTime.now(),
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      clienteTelefone: _clienteSelecionado?.telefone,
      itens: itensVenda,
      tipoPagamento: tipoPrincipal,
      valorTotal: _totalCarrinho,
      valorRecebido: null, // Não recebido
      troco: null,
    );

    // Salvar venda balcão
    dataService.addVendaBalcao(vendaBalcao);

    // Criar pedido pendente
    final numero = vendaBalcao.numero;

    final produtos = _carrinho
        .where((item) => !item.isServico)
        .map(
          (item) => ItemPedido(
            id: item.id,
            nome: item.nome,
            quantidade: item.quantidade,
            preco: item.preco,
          ),
        )
        .toList();

    final List<ItemServico> servicos = _carrinho
        .where((item) => item.isServico)
        .map<ItemServico>(
          (item) => ItemServico(
            id: item.id,
            descricao: item.nome,
            valor: item.preco * item.quantidade,
          ),
        )
        .toList();

    // Usar os pagamentos do dialog, ou criar um pendente se estiver vazio
    final List<PagamentoPedido> pagamentos;
    if (pagamentosDoDialog.isNotEmpty) {
      // Marcar todos os pagamentos como não recebidos
      pagamentos = pagamentosDoDialog
          .map(
            (p) => PagamentoPedido(
              id: p.id,
              tipo: p.tipo,
              valor: p.valor,
              recebido: false, // Forçar como não recebido
              dataVencimento:
                  p.dataVencimento ??
                  DateTime.now().add(const Duration(days: 30)),
              parcelas: p.parcelas,
              numeroParcela: p.numeroParcela,
              parcelamentoId: p.parcelamentoId,
              observacao: p.observacao,
            ),
          )
          .toList();
    } else {
      // Se não tem pagamentos, criar um pendente padrão
      pagamentos = [
        PagamentoPedido(
          id: uuid.v4(),
          tipo: TipoPagamento.outro,
          valor: _totalCarrinho,
          recebido: false,
          dataVencimento: DateTime.now().add(const Duration(days: 30)),
        ),
      ];
    }

    final pedido = Pedido(
      id: uuid.v4(),
      numero: numero,
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      clienteTelefone: _clienteSelecionado?.telefone,
      clienteEndereco: _clienteSelecionado?.endereco,
      dataPedido: DateTime.now(),
      status: 'Pendente',
      produtos: produtos,
      servicos: servicos,
      pagamentos: pagamentos,
    );

    dataService.addPedido(pedido);

    // Se estava editando um pedido/venda salva, remover o antigo
    if (_pedidoOriginal != null) {
      dataService.deletePedido(_pedidoOriginal!.id);
      final vendaOriginal = dataService.vendasBalcao
          .where((v) => v.numero == _pedidoOriginal!.numero)
          .firstOrNull;
      if (vendaOriginal != null) {
        dataService.deleteVendaBalcao(vendaOriginal.id);
      }
      _pedidoOriginal = null;
    }

    // Chamar callback se existir
    widget.onVendaFinalizada?.call();

    // Mostrar sucesso
    _mostrarSucessoVendaSalva(vendaBalcao.numero);
  }

  void _mostrarSucessoVendaSalva(String numeroVenda) {
    _mostrarNotificacaoSucesso(
      icone: Icons.bookmark_added_rounded,
      titulo: 'Venda Salva',
      subtitulo: numeroVenda,
      cor: Colors.orange,
      info: 'Disponível em "Receber"',
    );

    // Limpar carrinho
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
      _pagamentosSalvos = [];
    });
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
  }

  /// Notificação elegante no canto superior direito
  void _mostrarNotificacaoSucesso({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    String? info,
    String? valorFormatado,
    Duration duracao = const Duration(seconds: 3),
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _NotificacaoSucesso(
        icone: icone,
        titulo: titulo,
        subtitulo: subtitulo,
        cor: cor,
        info: info,
        valorFormatado: valorFormatado,
        duracao: duracao,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  void _mostrarSucessoVendaCredito(
    double valor,
    String numeroVenda,
    TipoPagamento tipo,
    DateTime vencimento,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');
    final tipoNome = tipo == TipoPagamento.crediario ? 'Crediário' : 'Boleto';

    _mostrarNotificacaoSucesso(
      icone: Icons.schedule_rounded,
      titulo: '$tipoNome Registrado',
      subtitulo: numeroVenda,
      cor: Colors.blue,
      valorFormatado: formatoMoeda.format(valor),
      info: 'Vence: ${formatoData.format(vencimento)}',
      duracao: const Duration(seconds: 4),
    );

    // Limpar carrinho e resetar estados
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
      _pagamentosSalvos = [];
    });
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
  }

  void _mostrarSucessoVendaParcelada(
    int parcelas,
    double valorParcela,
    String numeroVenda,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    _mostrarNotificacaoSucesso(
      icone: Icons.calendar_month_rounded,
      titulo: 'Venda Parcelada',
      subtitulo: numeroVenda,
      cor: Colors.purple,
      valorFormatado: '${parcelas}x ${formatoMoeda.format(valorParcela)}',
      info: 'Total: ${formatoMoeda.format(_totalCarrinho)}',
      duracao: const Duration(seconds: 4),
    );

    // Limpar carrinho
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
    });
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
  }

  void _mostrarSucessoVendaParcial(
    double valorPago,
    double valorRestante,
    String numeroVenda,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    _mostrarNotificacaoSucesso(
      icone: Icons.pending_rounded,
      titulo: 'Pagamento Parcial',
      subtitulo: numeroVenda,
      cor: Colors.orange,
      valorFormatado: formatoMoeda.format(valorPago),
      info: 'Faltando: ${formatoMoeda.format(valorRestante)}',
    );

    _limparCarrinho();
    // Limpar carrinho e cliente salvos após finalizar
    _limparCarrinhoSalvo();
  }

  void _mostrarSucessoVenda(double valor, String numeroVenda) {
    // Popup animado com dinheiro caindo
    PopupSucessoVenda.mostrar(
      context,
      valor: valor,
      titulo: 'VENDA CONCLUÍDA!',
      subtitulo: numeroVenda,
      onDismiss: () {
        // Limpar carrinho e cliente após fechar
        if (mounted) {
          setState(() {
            _carrinho.clear();
            _clienteSelecionado = null;
          });
          _limparCarrinhoSalvo();
        }
      },
    );

    // Limpar carrinho e cliente imediatamente
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
    });
    _limparCarrinhoSalvo();
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }

  Widget _buildSeletorCliente(DataService dataService) {
    return _SeletorClienteWidget(
      dataService: dataService,
      clienteSelecionadoId: _clienteSelecionado?.id,
      onClienteSelecionado: (cliente) {
        setState(() => _clienteSelecionado = cliente);
        _salvarClienteSelecionado();
      },
      onRemoverCliente: () {
        setState(() => _clienteSelecionado = null);
        _salvarClienteSelecionado();
      },
    );
  }

  void _mostrarDetalhesCliente(Cliente cliente, DataService dataService) {
    // Buscar pedidos do cliente
    final pedidosCliente = dataService.pedidos
        .where((p) => p.clienteId == cliente.id)
        .toList();

    // Calcular estatísticas
    double totalCompras = 0;
    double totalAPrazo = 0;
    double totalPendente = 0;
    Map<String, int> produtosContagem = {};
    Map<String, int> servicosContagem = {};

    for (final pedido in pedidosCliente) {
      totalCompras += pedido.totalGeral;

      // Verificar se é venda a prazo
      final isPrazo = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.crediario ||
            p.tipo == TipoPagamento.boleto ||
            p.tipo == TipoPagamento.outro,
      );

      if (isPrazo) {
        totalAPrazo += pedido.totalGeral;
        totalPendente += pedido.totalGeral - pedido.totalRecebido;
      }

      // Contar produtos
      for (final prod in pedido.produtos) {
        produtosContagem[prod.nome] =
            (produtosContagem[prod.nome] ?? 0) + prod.quantidade;
      }

      // Contar serviços
      for (final serv in pedido.servicos) {
        servicosContagem[serv.descricao] =
            (servicosContagem[serv.descricao] ?? 0) + 1;
      }
    }

    // Ordenar produtos por quantidade
    final produtosOrdenados = produtosContagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Ordenar serviços por quantidade
    final servicosOrdenados = servicosContagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Cabeçalho com dados do cliente
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(0.2),
                    Colors.purple.withOpacity(0.1),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue.withOpacity(0.3),
                        child: Text(
                          cliente.nome.isNotEmpty
                              ? cliente.nome[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cliente.nome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  cliente.telefone,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if (cliente.email != null &&
                                cliente.email!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.email,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      cliente.email!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Botão selecionar
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _clienteSelecionado = cliente);
                          _salvarClienteSelecionado();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Selecionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Cards de estatísticas
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCardEstatisticaCliente(
                      'Total Compras',
                      formatoMoeda.format(totalCompras),
                      Icons.shopping_cart,
                      Colors.green,
                      '${pedidosCliente.length} pedidos',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCardEstatisticaCliente(
                      'Vendas a Prazo',
                      formatoMoeda.format(totalAPrazo),
                      Icons.schedule,
                      Colors.orange,
                      totalPendente > 0
                          ? 'Pendente: ${formatoMoeda.format(totalPendente)}'
                          : 'Tudo pago',
                    ),
                  ),
                ],
              ),
            ),

            // Limite de crédito se existir
            if (cliente.limiteCredito != null && cliente.limiteCredito! > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Limite de Crédito',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          formatoMoeda.format(cliente.limiteCredito),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Disponível',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          formatoMoeda.format(
                            cliente.limiteCredito! - totalPendente,
                          ),
                          style: TextStyle(
                            color: (cliente.limiteCredito! - totalPendente) > 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Título seção produtos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  const Text(
                    'Produtos Mais Comprados',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Lista de produtos mais comprados
            Expanded(
              child: produtosOrdenados.isEmpty && servicosOrdenados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 48,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma compra registrada',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // Top produtos
                        ...produtosOrdenados.take(10).map((entry) {
                          final porcentagem = produtosOrdenados.isNotEmpty
                              ? entry.value / produtosOrdenados.first.value
                              : 0.0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: porcentagem,
                                          backgroundColor: Colors.white
                                              .withOpacity(0.1),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.blue.withOpacity(0.7),
                                              ),
                                          minHeight: 4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${entry.value}x',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        // Top serviços
                        if (servicosOrdenados.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.build,
                                color: Colors.white.withOpacity(0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Serviços Mais Utilizados',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...servicosOrdenados.take(5).map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.build,
                                    color: Colors.purple,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${entry.value}x',
                                      style: const TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 16),
                      ],
                    ),
            ),

            // Botão de editar cadastro
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        final clienteAtualizado = await Navigator.push<Cliente>(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ClienteDetalhesPage(cliente: cliente),
                          ),
                        );
                        if (clienteAtualizado != null) {
                          setState(
                            () => _clienteSelecionado = clienteAtualizado,
                          );
                          _salvarClienteSelecionado();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar Cadastro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _clienteSelecionado = cliente);
                        _salvarClienteSelecionado();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text('Usar nesta Venda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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

  Widget _buildCardEstatisticaCliente(
    String titulo,
    String valor,
    IconData icone,
    Color cor,
    String subtitulo,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final itensEncontrados = _buscarItens(dataService);
    final categorias = _getCategorias(dataService);
    final produtosCategoria = _getProdutosPorCategoria(dataService);

    // Verificar se já existe um Scaffold no contexto (ex: quando está dentro do TabBarView do PdvPage)
    final hasScaffold = Scaffold.maybeOf(context) != null;

    final content = Column(
      children: [
        // Barra superior com busca, quantidade e cliente
        _buildBarraSuperior(dataService),
        // Área principal
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Lado esquerdo: Categorias + Produtos
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Categorias
                    _buildCategorias(categorias),
                    // Área de produtos
                    Expanded(
                      child: _termoBusca.isNotEmpty
                          ? (itensEncontrados.isEmpty
                                ? _buildNenhumResultado()
                                : _buildGridItens(itensEncontrados))
                          : _categoriaAtiva != null
                          ? _buildGridProdutos(produtosCategoria)
                          : _buildEstadoInicial(dataService),
                    ),
                  ],
                ),
              ),
              // Lado direito: Carrinho com efeito glow
              Container(
                width: 380,
                margin: const EdgeInsets.only(right: 16, bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [const Color(0xFF0D0D15), const Color(0xFF12121C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    // Glow ciano externo
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.15),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                    // Glow interno sutil
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                    // Sombra de profundidade
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: _buildCarrinhoMelhorado(dataService),
              ),
            ],
          ),
        ),
      ],
    );

    // Se não há Scaffold no contexto (chamado diretamente da home), envolver em um
    if (!hasScaffold) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('PDV - Venda Direta'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          actions: const [],
        ),
        body: content,
        ),
      );
    }

    // Se já existe Scaffold (dentro do TabBarView), retornar apenas o conteúdo
    return content;
  }

  Widget _buildBarraSuperior(DataService dataService) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Campo de busca principal
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: TextField(
                controller: _buscaController,
                focusNode: _buscaFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: '🔍 Buscar produto, código ou código de barras...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.blue,
                    size: 28,
                  ),
                  suffixIcon: _termoBusca.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() => _termoBusca = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                onChanged: (value) => setState(() {
                  _termoBusca = value;
                  _categoriaAtiva = null;
                }),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Indicador de quantidade
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _quantidadeDigitada > 1
                    ? Colors.orange
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'QTD:',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_quantidadeDigitada > 1) {
                      setState(() => _quantidadeDigitada--);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.remove,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$_quantidadeDigitada',
                    style: TextStyle(
                      color: _quantidadeDigitada > 1
                          ? Colors.orange
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _quantidadeDigitada++),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Seletor de cliente
          GestureDetector(
            onTap: () => _selecionarCliente(dataService),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
                border: _clienteSelecionado != null
                    ? Border.all(color: Colors.green, width: 2)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    _clienteSelecionado != null
                        ? Icons.person
                        : Icons.person_add,
                    color: _clienteSelecionado != null
                        ? Colors.greenAccent
                        : Colors.white54,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _clienteSelecionado?.nome ?? 'Cliente',
                    style: TextStyle(
                      color: _clienteSelecionado != null
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 14,
                      fontWeight: _clienteSelecionado != null
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Botão Histórico de Vendas
          GestureDetector(
            onTap: () => _abrirHistoricoVendas(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    color: Colors.amber.withOpacity(0.8),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Histórico',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorias(List<String> categorias) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          // Ícone indicando scroll
          Container(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.chevron_left_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ),
          // Lista de categorias com scroll
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: categorias.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Botão "Todos"
                    final isActive =
                        _categoriaAtiva == null && _termoBusca.isEmpty;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _categoriaAtiva = null;
                        _termoBusca = '';
                        _buscaController.clear();
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? LinearGradient(
                                  colors: [
                                    Colors.blue.shade600,
                                    Colors.blue.shade400,
                                  ],
                                )
                              : null,
                          color: isActive ? null : const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? Colors.blue
                                : Colors.white.withOpacity(0.1),
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apps_rounded,
                              color: isActive ? Colors.white : Colors.white60,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Todos',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white70,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final categoria = categorias[index - 1];
                  final isActive = _categoriaAtiva == categoria;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _categoriaAtiva = isActive ? null : categoria;
                      _termoBusca = '';
                      _buscaController.clear();
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: isActive
                            ? LinearGradient(
                                colors: [
                                  Colors.purple.shade600,
                                  Colors.purple.shade400,
                                ],
                              )
                            : null,
                        color: isActive ? null : const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? Colors.purple
                              : Colors.white.withOpacity(0.1),
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: Colors.purple.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        categoria,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Ícone indicando mais itens à direita
          Container(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoInicial(DataService dataService) {
    return Column(
      children: [
        // Conteúdo central
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.point_of_sale,
                    size: 80,
                    color: Colors.blue.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'PDV Venda Direta',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Busque um produto ou selecione uma categoria',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildDicaRapida(
                      Icons.search,
                      'Buscar',
                      'Digite nome ou código',
                    ),
                    const SizedBox(width: 24),
                    _buildDicaRapida(
                      Icons.category,
                      'Categorias',
                      'Clique acima',
                    ),
                    const SizedBox(width: 24),
                    _buildDicaRapida(Icons.person_add, 'Cliente', 'Opcional'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDicaRapida(IconData icon, String titulo, String subtitulo) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white38, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          titulo,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        ),
        Text(
          subtitulo,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildNenhumResultado() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 60,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum item encontrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
          Text(
            'para "$_termoBusca"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItens(List<dynamic> itens) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itens.length,
      itemBuilder: (context, index) {
        final item = itens[index];
        final isProduto = item is Produto;
        return _buildCardProduto(item, isProduto);
      },
    );
  }

  Widget _buildGridProdutos(List<Produto> produtos) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: produtos.length,
      itemBuilder: (context, index) {
        return _buildCardProduto(produtos[index], true);
      },
    );
  }

  Widget _buildCardProduto(dynamic item, bool isProduto) {
    final nome = item.nome as String;
    final preco = isProduto
        ? (item as Produto).precoAtual
        : (item as Servico).preco;
    final promocao = isProduto ? (item as Produto).promocaoAtiva : false;
    final codigo = isProduto ? (item as Produto).codigo : null;

    return GestureDetector(
      onTap: () => _adicionarAoCarrinho(item),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isProduto
                ? [const Color(0xFF1E3A5F), const Color(0xFF2C3E50)]
                : [const Color(0xFF4A1E5F), const Color(0xFF3E2C50)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: promocao
                ? Colors.orange.withOpacity(0.5)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone do tipo e código
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isProduto
                              ? Colors.blue.withOpacity(0.3)
                              : Colors.purple.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isProduto ? Icons.inventory_2 : Icons.build,
                          color: isProduto
                              ? Colors.lightBlueAccent
                              : Colors.purpleAccent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Código do produto
                      if (codigo != null && codigo.isNotEmpty)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              codigo,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      if (promocao) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PROMO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  // Nome
                  Text(
                    nome,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Preço
                  Text(
                    'R\$ ${preco.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: promocao ? Colors.orange : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            // Botão de adicionar
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.add_shopping_cart,
                  color: Colors.greenAccent,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarrinhoMelhorado(DataService dataService) {
    return Column(
      children: [
        // Cabeçalho do carrinho - compacto e elegante
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Ícone com glow
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Colors.cyanAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CARRINHO',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              // Badge de itens com glow
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.2),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  '$_totalItens',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_carrinho.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _limparCarrinho,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Linha divisória sutil com glow
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        // Lista de itens
        Expanded(
          child: _carrinho.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Carrinho vazio',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adicione produtos para começar',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _carrinho.length,
                  itemBuilder: (context, index) {
                    final item = _carrinho[index];
                    return Dismissible(
                      key: Key('${item.id}_$index'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _removerItem(index),
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade900.withOpacity(0.8),
                              Colors.red.shade700.withOpacity(0.9),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            // Ícone compacto com glow
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.isServico
                                    ? Colors.purple.withOpacity(0.15)
                                    : Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: item.isServico
                                        ? Colors.purpleAccent.withOpacity(0.2)
                                        : Colors.greenAccent.withOpacity(0.2),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                item.isServico
                                    ? Icons.build_rounded
                                    : Icons.inventory_2_rounded,
                                color: item.isServico
                                    ? Colors.purpleAccent
                                    : Colors.greenAccent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Info compacta
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.nome,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'R\$ ${item.preco.toStringAsFixed(2)} × ${item.quantidade}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Controles de quantidade minimalistas
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _alterarQuantidade(index, -1),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.remove_rounded,
                                      color: item.quantidade > 1
                                          ? Colors.white60
                                          : Colors.redAccent,
                                      size: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    '${item.quantidade}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _alterarQuantidade(index, 1),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withOpacity(
                                        0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.greenAccent,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            // Botão de desconto no item
                            GestureDetector(
                              onTap: () => _aplicarDescontoItem(index),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: item.desconto > 0
                                      ? Colors.orange.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.discount_rounded,
                                  color: item.desconto > 0
                                      ? Colors.orangeAccent
                                      : Colors.white60,
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Subtotal com glow
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (item.desconto > 0) ...[
                                  Text(
                                    'R\$ ${item.subtotalSemDesconto.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 10,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '-R\$ ${item.desconto.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.greenAccent.withOpacity(0.15),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    'R\$ ${item.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Linha divisória sutil antes do rodapé
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.greenAccent.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        // Rodapé compacto com glow
        Container(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Cliente selecionado - mais compacto
              if (_clienteSelecionado != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        color: Colors.greenAccent.withOpacity(0.7),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _clienteSelecionado!.nome,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _clienteSelecionado = null);
                          _salvarClienteSelecionado();
                        },
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.4),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              // Desconto total e Total com efeito glow
              Column(
                children: [
                  if (_descontoTotal > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _aplicarDescontoTotal(),
                              child: Icon(
                                Icons.discount_rounded,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Desconto Total',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '-R\$ ${_descontoTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtotal',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          'R\$ ${_totalCarrinhoSemDesconto.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TOTAL',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                          if (_descontoTotal == 0) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _aplicarDescontoTotal(),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.discount_rounded,
                                  color: Colors.orangeAccent,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          'R\$ ${_totalCarrinho.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Botões de ação compactos com glow
              Row(
                children: [
                  // Botão Receber
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PdvPage(
                              abaInicial: 0, // 0 = Aba Receber
                              esconderAbaVenda: true, // Esconde a aba Venda
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.receipt_long,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'RECEBER',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botão Salvar compacto
                  Expanded(
                    child: GestureDetector(
                      onTap: _carrinho.isEmpty
                          ? null
                          : () => _salvarVendaPendente(dataService, []),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _carrinho.isEmpty
                              ? Colors.white.withOpacity(0.05)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _carrinho.isEmpty
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.3),
                                    blurRadius: 12,
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bookmark_add_rounded,
                              color: _carrinho.isEmpty
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SALVAR',
                              style: TextStyle(
                                color: _carrinho.isEmpty
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botão Finalizar com glow verde
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _carrinho.isEmpty
                          ? null
                          : () => _finalizarVenda(dataService),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: _carrinho.isEmpty
                              ? null
                              : LinearGradient(
                                  colors: [
                                    Colors.greenAccent.withOpacity(0.3),
                                    Colors.green.withOpacity(0.3),
                                  ],
                                ),
                          color: _carrinho.isEmpty
                              ? Colors.white.withOpacity(0.05)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _carrinho.isEmpty
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.greenAccent.withOpacity(0.4),
                                    blurRadius: 15,
                                    spreadRadius: 1,
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_checkout_rounded,
                              color: _carrinho.isEmpty
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.greenAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'FINALIZAR',
                              style: TextStyle(
                                color: _carrinho.isEmpty
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget de notificação de sucesso elegante no canto superior direito
class _NotificacaoSucesso extends StatefulWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final String? info;
  final String? valorFormatado;
  final Duration duracao;
  final VoidCallback onDismiss;

  const _NotificacaoSucesso({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    this.info,
    this.valorFormatado,
    required this.duracao,
    required this.onDismiss,
  });

  @override
  State<_NotificacaoSucesso> createState() => _NotificacaoSucessoState();
}

class _NotificacaoSucessoState extends State<_NotificacaoSucesso>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto-dismiss após a duração
    Future.delayed(widget.duracao, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 0) {
                  _dismiss();
                }
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.cor.withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.cor.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone com animação de check
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.cor.withOpacity(0.3),
                                  widget.cor.withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icone,
                              color: widget.cor,
                              size: 28,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    // Conteúdo
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.titulo,
                            style: TextStyle(
                              color: widget.cor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitulo,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.valorFormatado != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.valorFormatado!,
                              style: TextStyle(
                                color: widget.cor,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (widget.info != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.info!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botão fechar
                    GestureDetector(
                      onTap: _dismiss,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withOpacity(0.4),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Widget separado para o seletor de cliente - evita problemas de renderização
class _SeletorClienteWidget extends StatefulWidget {
  final DataService dataService;
  final String? clienteSelecionadoId;
  final Function(Cliente) onClienteSelecionado;
  final VoidCallback onRemoverCliente;

  const _SeletorClienteWidget({
    required this.dataService,
    required this.clienteSelecionadoId,
    required this.onClienteSelecionado,
    required this.onRemoverCliente,
  });

  @override
  State<_SeletorClienteWidget> createState() => _SeletorClienteWidgetState();
}

class _SeletorClienteWidgetState extends State<_SeletorClienteWidget> {
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Cliente> get _clientesFiltrados {
    if (_busca.isEmpty) {
      return widget.dataService.clientes;
    }
    final termo = _busca.toLowerCase();
    return widget.dataService.clientes.where((c) {
      return c.nome.toLowerCase().contains(termo) ||
          c.telefone.contains(termo) ||
          (c.cpfCnpj?.contains(termo) ?? false);
    }).toList();
  }

  void _selecionarCliente(Cliente cliente) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onClienteSelecionado(cliente);
    });
  }

  void _removerCliente() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRemoverCliente();
    });
  }

  Future<void> _cadastrarNovoCliente() async {
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final novoCliente = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(builder: (context) => const ClienteDetalhesPage()),
    );

    if (novoCliente != null && mounted) {
      widget.onClienteSelecionado(novoCliente);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientesFiltrados;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Título
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.person_search, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Selecionar Cliente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (widget.clienteSelecionadoId != null)
                  GestureDetector(
                    onTap: _removerCliente,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_off,
                            color: Colors.orange,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Remover',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Campo de busca
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _buscaController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome, telefone ou CPF/CNPJ...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white54,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (value) => setState(() => _busca = value),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botão novo cliente
                GestureDetector(
                  onTap: _cadastrarNovoCliente,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Novo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Lista de clientes
          Expanded(
            child: clientes.isEmpty
                ? _buildEstadoVazio()
                : _buildListaClientes(clientes),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoVazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 48,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            _busca.isEmpty
                ? 'Nenhum cliente cadastrado'
                : 'Nenhum cliente encontrado',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _cadastrarNovoCliente,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _busca.isNotEmpty
                        ? 'Cadastrar "$_busca"'
                        : 'Cadastrar Cliente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaClientes(List<Cliente> clientes) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: clientes.length,
      itemBuilder: (context, index) {
        final cliente = clientes[index];
        final isSelected = widget.clienteSelecionadoId == cliente.id;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selecionarCliente(cliente),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green.withOpacity(0.2)
                  : const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: Colors.green, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                // Avatar simples
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.green
                        : Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cliente.nome.isNotEmpty
                        ? cliente.nome[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.blue,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Informações
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nome,
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white,
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cliente.telefone,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicador de seleção
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Dialog de pagamento do PDV - usa a mesma lógica do PagamentoWidget
class _DialogPagamentoPDV extends StatefulWidget {
  final double totalCarrinho;
  final List<PagamentoPedido> pagamentosIniciais;
  final Function(List<PagamentoPedido>) onConfirmar;
  final Function(List<PagamentoPedido>) onSalvarPendente;
  final Cliente? cliente; // Cliente para validar limite de crédito

  const _DialogPagamentoPDV({
    required this.totalCarrinho,
    required this.pagamentosIniciais,
    required this.onConfirmar,
    required this.onSalvarPendente,
    this.cliente,
  });

  @override
  State<_DialogPagamentoPDV> createState() => _DialogPagamentoPDVState();
}

class _DialogPagamentoPDVState extends State<_DialogPagamentoPDV> {
  late List<PagamentoPedido> _pagamentos;
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoData = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _pagamentos = List.from(widget.pagamentosIniciais);
  }

  double get _totalLancado => _pagamentos.fold(0.0, (sum, p) => sum + p.valor);
  double get _valorRestante => widget.totalCarrinho - _totalLancado;
  bool get _pagamentoCompleto => _valorRestante <= 0.01;

  void _adicionarPagamento(TipoPagamento tipo) {
    final valorSugerido = _valorRestante > 0 ? _valorRestante : 0.0;

    // Se for uma venda salva (tem pagamentos iniciais do tipo "outro") e o usuário
    // escolher um novo tipo de pagamento, limpar os pagamentos antigos do tipo "outro"
    if (widget.pagamentosIniciais.isNotEmpty && tipo != TipoPagamento.outro) {
      final temPagamentosOutro = _pagamentos.any(
        (p) => p.tipo == TipoPagamento.outro && !p.recebido,
      );
      
      if (temPagamentosOutro) {
        // Remover todos os pagamentos do tipo "outro" que não foram recebidos
        // Isso garante que o tipo escolhido pelo usuário seja respeitado
        setState(() {
          _pagamentos.removeWhere(
            (p) => p.tipo == TipoPagamento.outro && !p.recebido,
          );
        });
      }
    }

    // Validação especial para Fiado
    if (tipo == TipoPagamento.fiado) {
      // Verificar se tem cliente selecionado
      if (widget.cliente == null) {
        _mostrarErroSemClienteFiado();
        return;
      }

      // Verificar se o cliente tem limite de crédito
      if (widget.cliente!.limiteCredito == null ||
          widget.cliente!.limiteCredito! <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.cliente!.nome} não possui limite de crédito cadastrado',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 16,
              right: 16,
            ),
          ),
        );
        return;
      }

      if (widget.cliente!.bloqueado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.block, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.cliente!.nome} está bloqueado para compras fiado',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 16,
              right: 16,
            ),
          ),
        );
        return;
      }

      // Verificar se o cliente tem crédito disponível
      if (!widget.cliente!.podeFiar(valorSugerido)) {
        final disponivelFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.creditoDisponivel);
        final limiteFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.limiteCredito);
        final devedorFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.saldoDevedor);

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 12),
                Text('Limite Excedido', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.cliente!.nome} não possui crédito suficiente.',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                _buildInfoCredito('Limite Total', limiteFormatado, Colors.blue),
                _buildInfoCredito(
                  'Saldo Devedor',
                  devedorFormatado,
                  Colors.red,
                ),
                _buildInfoCredito(
                  'Disponível',
                  disponivelFormatado,
                  Colors.green,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // Validação especial para Crediário
    if (tipo == TipoPagamento.crediario) {
      // Verificar se tem cliente selecionado
      if (widget.cliente == null) {
        _mostrarErroSemClienteCrediario();
        return;
      }
    }

    _mostrarDialogPagamento(tipo, valorSugerido);
  }

  // Mostra mensagem de erro centralizada quando tenta usar crediário sem cliente
  void _mostrarErroSemClienteCrediario() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.pink.withOpacity(0.5), width: 2),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícone de erro grande
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.pink.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.pink.withOpacity(0.4),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.person_off,
                  color: Colors.pink,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),

              // Título do erro
              const Text(
                'CLIENTE OBRIGATÓRIO',
                style: TextStyle(
                  color: Colors.pink,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensagem explicativa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: Colors.pink,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Para lançar venda em Crediário, é necessário selecionar um cliente.',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selecione um cliente antes de escolher esta forma de pagamento.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text(
                'ENTENDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mostra mensagem de erro centralizada quando tenta usar fiado sem cliente
  void _mostrarErroSemClienteFiado() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícone de erro grande
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.4),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.person_off,
                  color: Colors.red,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),

              // Título do erro
              const Text(
                'CLIENTE OBRIGATÓRIO',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensagem explicativa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.handshake, color: Colors.red, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Para lançar venda Fiado, é necessário selecionar um cliente.',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selecione um cliente antes de escolher esta forma de pagamento.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text(
                'ENTENDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCredito(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          Text(
            valor,
            style: TextStyle(color: cor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogPagamento(
    TipoPagamento tipo,
    double valorSugerido, {
    PagamentoPedido? pagamentoExistente,
  }) {
    final valorController = TextEditingController(
      text: valorSugerido.toStringAsFixed(2),
    );
    final valorRecebidoController = TextEditingController();
    final observacaoController = TextEditingController(
      text: pagamentoExistente?.observacao ?? '',
    );

    int parcelas = 1;
    bool parcelar = false;
    DateTime primeiroVencimento = DateTime.now().add(const Duration(days: 30));
    int intervaloVencimento = 30;
    bool isDinheiro = tipo == TipoPagamento.dinheiro;
    bool isFiado = tipo == TipoPagamento.fiado;
    DateTime dataVencimentoFiado = DateTime.now().add(const Duration(days: 7));
    double troco = 0.0;

    final suportaParcelamento = [
      TipoPagamento.boleto,
      TipoPagamento.crediario,
    ].contains(tipo);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calcularTroco() {
            final valorPagar =
                double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0;
            final valorRecebido =
                double.tryParse(
                  valorRecebidoController.text.replaceAll(',', '.'),
                ) ??
                0;
            setDialogState(() {
              troco = valorRecebido - valorPagar;
              if (troco < 0) troco = 0;
            });
          }

          double valorTotal =
              double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0;
          double valorParcela = parcelas > 0
              ? valorTotal / parcelas
              : valorTotal;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getCorTipo(tipo).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconeTipo(tipo),
                    color: _getCorTipo(tipo),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tipo.nome,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Valor',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: valorController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      if (isDinheiro) calcularTroco();
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 20,
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  // Calculadora de troco para dinheiro
                  if (isDinheiro) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cliente entregou:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: valorRecebidoController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => calcularTroco(),
                            decoration: InputDecoration(
                              prefixText: 'R\$ ',
                              prefixStyle: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                              ),
                              hintText: '0,00',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                              ),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.3),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [10, 20, 50, 100, 200].map((valor) {
                              return GestureDetector(
                                onTap: () {
                                  valorRecebidoController.text = valor
                                      .toStringAsFixed(2);
                                  calcularTroco();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'R\$ $valor',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (troco > 0) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'TROCO',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${troco.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Parcelamento
                  if (suportaParcelamento) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_month,
                                color: Colors.purpleAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Parcelamento',
                                style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: parcelar,
                                onChanged: (value) => setDialogState(() {
                                  parcelar = value;
                                  if (!parcelar) parcelas = 1;
                                }),
                                activeThumbColor: Colors.purpleAccent,
                              ),
                            ],
                          ),
                          if (parcelar) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => setDialogState(() {
                                    if (parcelas > 2) parcelas--;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.remove,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${parcelas}x de ${_formatoMoeda.format(valorParcela)}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setDialogState(() {
                                    if (parcelas < 24) parcelas++;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.greenAccent,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () async {
                                final data = await showDatePicker(
                                  context: context,
                                  initialDate: primeiroVencimento,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                  builder: (context, child) => Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.purple,
                                        surface: Color(0xFF1E1E2E),
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (data != null) {
                                  setDialogState(
                                    () => primeiroVencimento = data,
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.white54,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '1º venc: ${_formatoData.format(primeiroVencimento)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Fiado - Data de vencimento
                  if (isFiado) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.event,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Data de Pagamento',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (widget.cliente != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Disp: ${_formatoMoeda.format(widget.cliente!.creditoDisponivel)}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () async {
                              final data = await showDatePicker(
                                context: context,
                                initialDate: dataVencimentoFiado,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                                builder: (context, child) => Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.red,
                                      surface: Color(0xFF1E1E2E),
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (data != null) {
                                setDialogState(
                                  () => dataVencimentoFiado = data,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _formatoData.format(dataVencimentoFiado),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.edit,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'O cliente deverá pagar até esta data',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Observação
                  const SizedBox(height: 16),
                  TextField(
                    controller: observacaoController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Observação (opcional)',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final valor =
                      double.tryParse(
                        valorController.text.replaceAll(',', '.'),
                      ) ??
                      0;
                  if (valor <= 0) return;

                  final String? obs = observacaoController.text.isNotEmpty
                      ? observacaoController.text
                      : null;
                  double? valorRecebidoFinal;
                  double? trocoFinal;
                  if (isDinheiro && troco > 0) {
                    valorRecebidoFinal = double.tryParse(
                      valorRecebidoController.text.replaceAll(',', '.'),
                    );
                    trocoFinal = troco;
                  }

                  // Se for uma venda salva e o usuário escolheu um novo tipo (não "outro"),
                  // remover pagamentos antigos do tipo "outro" que não foram recebidos
                  var novaLista = List<PagamentoPedido>.from(_pagamentos);
                  if (widget.pagamentosIniciais.isNotEmpty && 
                      tipo != TipoPagamento.outro) {
                    novaLista.removeWhere(
                      (p) => p.tipo == TipoPagamento.outro && !p.recebido,
                    );
                  }

                  if (parcelar && parcelas > 1) {
                    final parcelamentoId = DateTime.now().millisecondsSinceEpoch
                        .toString();
                    final valorCadaParcela = valor / parcelas;

                    for (int i = 0; i < parcelas; i++) {
                      final dataVenc = primeiroVencimento.add(
                        Duration(days: intervaloVencimento * i),
                      );
                      novaLista.add(
                        PagamentoPedido(
                          id: '${parcelamentoId}_$i',
                          tipo: tipo,
                          valor: valorCadaParcela,
                          parcelas: parcelas,
                          numeroParcela: i + 1,
                          parcelamentoId: parcelamentoId,
                          dataVencimento: dataVenc,
                          recebido: false,
                          observacao: i == 0 ? obs : null,
                        ),
                      );
                    }
                  } else {
                    // Determinar se já foi recebido baseado no tipo
                    final isRecebido =
                        tipo == TipoPagamento.dinheiro ||
                        tipo == TipoPagamento.pix ||
                        tipo == TipoPagamento.cartaoCredito ||
                        tipo == TipoPagamento.cartaoDebito;

                    // Data de vencimento: usar dataVencimentoFiado para fiado, primeiroVencimento para outros
                    DateTime? dataVenc;
                    if (isFiado) {
                      dataVenc = dataVencimentoFiado;
                    } else if (!isRecebido) {
                      dataVenc = primeiroVencimento;
                    }

                    novaLista.add(
                      PagamentoPedido(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        tipo: tipo,
                        valor: valor,
                        recebido: isRecebido,
                        dataRecebimento: isRecebido ? DateTime.now() : null,
                        dataVencimento: dataVenc,
                        observacao: obs,
                        valorRecebido: valorRecebidoFinal,
                        troco: trocoFinal,
                      ),
                    );
                  }

                  setState(() => _pagamentos = novaLista);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getCorTipo(tipo),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  parcelar && parcelas > 1
                      ? 'Criar $parcelas Parcelas'
                      : 'Adicionar',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removerPagamento(int index) {
    setState(() => _pagamentos.removeAt(index));
  }

  Color _getCorTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.blue;
      case TipoPagamento.cartaoDebito:
        return Colors.indigo;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.purple;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Título
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.payment, color: Colors.greenAccent, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Finalizar Venda',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatoMoeda.format(widget.totalCarrinho),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Status do pagamento
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _pagamentoCompleto
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _pagamentoCompleto ? Icons.check_circle : Icons.pending,
                  color: _pagamentoCompleto
                      ? Colors.greenAccent
                      : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pagamentoCompleto
                            ? 'Pagamento completo'
                            : 'Falta: ${_formatoMoeda.format(_valorRestante)}',
                        style: TextStyle(
                          color: _pagamentoCompleto
                              ? Colors.greenAccent
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_totalLancado > 0)
                        Text(
                          'Lançado: ${_formatoMoeda.format(_totalLancado)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Formas de pagamento
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adicionar Pagamento',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TipoPagamento.values.map((tipo) {
                    return GestureDetector(
                      onTap: () => _adicionarPagamento(tipo),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _getCorTipo(tipo).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _getCorTipo(tipo).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getIconeTipo(tipo),
                              color: _getCorTipo(tipo),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tipo.nome,
                              style: TextStyle(
                                color: _getCorTipo(tipo),
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Lista de pagamentos
          Expanded(
            child: _pagamentos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.payment_outlined,
                          size: 48,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum pagamento adicionado',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selecione uma forma de pagamento acima',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _pagamentos.length,
                    itemBuilder: (context, index) {
                      final pagamento = _pagamentos[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getCorTipo(
                                  pagamento.tipo,
                                ).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getIconeTipo(pagamento.tipo),
                                color: _getCorTipo(pagamento.tipo),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pagamento.tipo.nome,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (pagamento.isParcela)
                                    Text(
                                      'Parcela ${pagamento.numeroParcela}/${pagamento.parcelas}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (pagamento.troco != null &&
                                      pagamento.troco! > 0)
                                    Text(
                                      'Troco: ${_formatoMoeda.format(pagamento.troco)}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              _formatoMoeda.format(pagamento.valor),
                              style: TextStyle(
                                color: _getCorTipo(pagamento.tipo),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _removerPagamento(index),
                              child: Icon(
                                Icons.close,
                                color: Colors.white.withOpacity(0.3),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Botões de ação
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Botão Salvar
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onSalvarPendente(_pagamentos),
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text(
                      'Salvar (Receber Depois)',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Botão Finalizar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _pagamentos.isEmpty
                        ? null
                        : () => widget.onConfirmar(_pagamentos),
                    icon: const Icon(Icons.check_circle, size: 24),
                    label: Text(
                      _pagamentoCompleto
                          ? 'FINALIZAR VENDA'
                          : 'FINALIZAR (${_formatoMoeda.format(_valorRestante)} pendente)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pagamentoCompleto
                          ? Colors.green
                          : Colors.orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Popup animado de sucesso com dinheiro caindo - centralizado na tela
class PopupSucessoVenda extends StatefulWidget {
  final double valor;
  final String titulo;
  final String subtitulo;
  final VoidCallback? onDismiss;

  const PopupSucessoVenda({
    super.key,
    required this.valor,
    required this.titulo,
    required this.subtitulo,
    this.onDismiss,
  });

  /// Mostra o popup de sucesso
  static void mostrar(
    BuildContext context, {
    required double valor,
    required String titulo,
    required String subtitulo,
    VoidCallback? onDismiss,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => PopupSucessoVenda(
        valor: valor,
        titulo: titulo,
        subtitulo: subtitulo,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<PopupSucessoVenda> createState() => _PopupSucessoVendaState();
}

class _PopupSucessoVendaState extends State<PopupSucessoVenda>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _moneyController;
  late Animation<double> _scaleAnimation;
  final List<_DinheiroAnimado> _dinheiros = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Animação de escala do popup
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Animação de dinheiro caindo
    _moneyController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Gerar notas de dinheiro
    for (int i = 0; i < 20; i++) {
      _dinheiros.add(
        _DinheiroAnimado(
          x: _random.nextDouble(),
          delay: _random.nextDouble() * 0.5,
          speed: 0.5 + _random.nextDouble() * 0.5,
          rotation: _random.nextDouble() * 2 * math.pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 4,
          size: 24 + _random.nextDouble() * 16,
        ),
      );
    }

    _scaleController.forward();
    _moneyController.repeat();

    // Auto fechar após 2.5 segundos
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _fechar();
      }
    });
  }

  void _fechar() {
    _scaleController.reverse().then((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _moneyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dinheiro caindo por trás
          ...List.generate(_dinheiros.length, (index) {
            final dinheiro = _dinheiros[index];
            return AnimatedBuilder(
              animation: _moneyController,
              builder: (context, child) {
                final progress =
                    (_moneyController.value - dinheiro.delay).clamp(0.0, 1.0) *
                    dinheiro.speed;
                final y =
                    -50 +
                    (progress * (MediaQuery.of(context).size.height + 100));
                final rotation =
                    dinheiro.rotation +
                    (_moneyController.value * dinheiro.rotationSpeed);
                final opacity = progress < 0.1
                    ? progress * 10
                    : progress > 0.8
                    ? (1 - progress) * 5
                    : 1.0;

                return Positioned(
                  left: dinheiro.x * MediaQuery.of(context).size.width,
                  top: y,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rotation,
                      child: Text(
                        '💵',
                        style: TextStyle(fontSize: dinheiro.size),
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          // Popup central
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.green.shade800,
                      Colors.green.shade600,
                      Colors.green.shade700,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone animado
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Título
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtítulo (número da venda)
                    Text(
                      widget.subtitulo,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Valor com animação
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 0.5 + (value * 0.5),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.attach_money,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatoMoeda.format(widget.valor),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dados para animação de cada nota de dinheiro
class _DinheiroAnimado {
  final double x;
  final double delay;
  final double speed;
  final double rotation;
  final double rotationSpeed;
  final double size;

  _DinheiroAnimado({
    required this.x,
    required this.delay,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
  });
}

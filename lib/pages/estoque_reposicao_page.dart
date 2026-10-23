import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../models/venda_balcao.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../custom_app_bar.dart';
import 'pedidos_compra_page.dart';
import 'receber_pedido_compra_page.dart';

class EstoqueReposicaoPage extends StatefulWidget {
  const EstoqueReposicaoPage({super.key});

  @override
  State<EstoqueReposicaoPage> createState() => _EstoqueReposicaoPageState();
}

class _EstoqueReposicaoPageState extends State<EstoqueReposicaoPage> {
  String _busca = '';
  String? _fornecedorFiltro;
  final TextEditingController _buscaController = TextEditingController();
  final Set<String> _selecionados = {};
  bool _salvandoPedidos = false;

  /// Produtos com pedido em aberto e quantidade ainda pendente.
  ///
  /// O selo da tela é calculado daqui, e não do campo `pedidoCompraGerado` do
  /// produto: assim ele nunca fica preso por um valor antigo gravado pela
  /// versão anterior do relatório (que não salvava pedidos de verdade).
  Set<String> _produtosComPedidoAberto(DataService service) {
    final ids = <String>{};
    for (final pedido in service.pedidosCompra) {
      if (!pedido.emAberto) continue;
      for (final item in pedido.itens) {
        if (!item.recebido) ids.add(item.produtoId);
      }
    }
    return ids;
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }



  /// Salva os itens do diálogo como pedidos de compra de verdade.
  ///
  /// O relatório agrupa por fornecedor: cada fornecedor vira um pedido com
  /// número próprio (PC-0001, PC-0002...). A partir daí o pedido aparece na
  /// lista, pode ser impresso e recebido no estoque.
  Future<void> _salvarPedidos(
    List<Map<String, dynamic>> itensPedido, {
    bool enviar = false,
  }) async {
    // Dois toques rápidos nos botões do diálogo criavam o mesmo pedido duas
    // vezes (um PC-0001 duplicado por fornecedor). A trava fecha a janela
    // entre o toque e a gravação.
    if (_salvandoPedidos) return;
    setState(() => _salvandoPedidos = true);
    try {
      final service = Provider.of<DataService>(context, listen: false);
      final auth = Provider.of<AuthService>(context, listen: false);

      final itensPorFornecedor = <String, List<ItemPedidoCompra>>{};
      for (final item in itensPedido) {
        final produto = item['produto'] as Produto;
        final quantidade = (item['quantidade'] as num?)?.toDouble() ?? 0;
        if (quantidade <= 0) continue;
        final fornecedor = (produto.fornecedorNome ?? '').trim();
        final chave = fornecedor.isEmpty ? 'Não informado' : fornecedor;
        itensPorFornecedor
            .putIfAbsent(chave, () => [])
            .add(
              ItemPedidoCompra(
                id: '',
                produtoId: produto.id,
                produtoNome: produto.nome,
                codigo: produto.codigo,
                unidade: produto.unidade,
                quantidade: quantidade,
                precoCusto: (item['custo'] as num?)?.toDouble() ?? 0,
              ),
            );
      }

      if (itensPorFornecedor.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe pelo menos um produto com quantidade.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      try {
        final criados = await service.criarPedidosCompraPorFornecedor(
          itensPorFornecedor: itensPorFornecedor,
          usuario: auth.usuarioAtual?.nome ?? auth.usuarioAtual?.email,
          enviar: enviar,
        );
        if (!mounted) return;
        setState(() => _selecionados.clear());
        Navigator.pop(context);
        await _mostrarPedidosCriados(criados);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível salvar os pedidos: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvandoPedidos = false);
      } else {
        _salvandoPedidos = false;
      }
    }
  }

  Future<void> _mostrarPedidosCriados(List<PedidoCompra> pedidos) async {
    if (pedidos.isEmpty || !mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.tealAccent.withOpacity(0.2)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.tealAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pedidos.length == 1
                        ? 'Pedido salvo'
                        : '${pedidos.length} pedidos salvos',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Já aparecem em Pedidos de Compra.',
                    style: TextStyle(color: Colors.white38, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: pedidos
                .map(
                  (pedido) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          color: Colors.cyanAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${pedido.numero} — ${pedido.fornecedorNome}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${pedido.itens.length} item(ns) • '
                                '${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(pedido.valorTotal)}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fechar'),
            child: const Text(
              'FECHAR',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'lista'),
            icon: const Icon(Icons.list_alt_rounded, size: 17),
            label: const Text('VER PEDIDOS'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          if (pedidos.length == 1)
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'receber'),
              icon: const Icon(Icons.move_to_inbox_rounded, size: 17),
              label: const Text('DAR ENTRADA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
              ),
            ),
        ],
      ),
    );

    if (!mounted) return;
    if (acao == 'lista') {
      await _abrirListaPedidos();
    } else if (acao == 'receber' && pedidos.length == 1) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceberPedidoCompraPage(pedidoId: pedidos.first.id),
        ),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _abrirListaPedidos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PedidosCompraPage()),
    );
    if (mounted) setState(() {});
  }

  void _exibirPedidoCompra(List<Produto> produtosIniciais) {
    final service = Provider.of<DataService>(context, listen: false);
    final comPedidoAberto = _produtosComPedidoAberto(service);

    // Criar uma lista local de itens para edição dentro do diálogo
    final List<Map<String, dynamic>> itensPedido = produtosIniciais.map((p) {
      int faltamSugestao = (p.estoqueMinimo - p.estoque).toInt();
      if (faltamSugestao <= 0 && p.estoque <= 0) {
        faltamSugestao = 1; // Sugere 1 se zerado e sem mínimo definido
      }
      final faltam = faltamSugestao.clamp(0, 999999);
      return {
        'produto': p,
        'quantidade': faltam.toDouble(),
        'custo': p.precoCusto ?? 0.0,
        'controllerQtd': TextEditingController(text: faltam.toString()),
        'controllerCusto': TextEditingController(
          text: (p.precoCusto ?? 0.0).toStringAsFixed(2),
        ),
      };
    }).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double totalCusto = 0;
          for (var item in itensPedido) {
            totalCusto += item['quantidade'] * item['custo'];
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.blueAccent.withOpacity(0.2)),
            ),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shopping_basket_rounded,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finalizar Pedido de Compra',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Ajuste quantidades e custos antes de finalizar',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 700,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'INVESTIMENTO ESTIMADO:',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'R\$ ${totalCusto.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: const Color(0xFF00FF9D),
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF00FF9D).withOpacity(0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itensPedido.length,
                        itemBuilder: (context, index) {
                          final item = itensPedido[index];
                          final Produto p = item['produto'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.nome,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (comPedidoAberto.contains(p.id)) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'JÁ PEDIDO',
                                                style: TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 6,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        'Forn: ${p.fornecedorNome ?? "N/I"}',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: item['controllerQtd'],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Qtd Comprar',
                                      labelStyle: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                      fillColor: Colors.white.withOpacity(0.05),
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setDialogState(() {
                                        item['quantidade'] =
                                            double.tryParse(
                                              v.replaceAll(',', '.'),
                                            ) ??
                                            0.0;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: item['controllerCusto'],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Custo Unit.',
                                      labelStyle: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                      prefixText: 'R\$ ',
                                      prefixStyle: const TextStyle(
                                        color: Colors.white24,
                                        fontSize: 10,
                                      ),
                                      fillColor: Colors.white.withOpacity(0.05),
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setDialogState(() {
                                        item['custo'] =
                                            double.tryParse(
                                              v.replaceAll(',', '.'),
                                            ) ??
                                            0.0;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      itensPedido.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.all(20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(color: Colors.white24),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: itensPedido.isEmpty
                    ? null
                    : () => _salvarPedidos(itensPedido),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('SALVAR PEDIDOS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: itensPedido.isEmpty
                    ? null
                    : () => _salvarPedidos(itensPedido, enviar: true),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('SALVAR E ENVIAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final comPedidoAberto = _produtosComPedidoAberto(service);
    final produtosAviso = service.produtos
        .where(
          (p) =>
              (p.estoqueMinimo > 0 && p.estoque <= p.estoqueMinimo) ||
              p.estoque <= 0,
        )
        .toList();

    final fornecedores =
        produtosAviso
            .map((p) => p.fornecedorNome ?? 'Não informado')
            .toSet()
            .toList()
          ..sort();

    final filtrados = produtosAviso.where((p) {
      final matchingBusca =
          _busca.isEmpty ||
          p.nome.toLowerCase().contains(_busca.toLowerCase()) ||
          (p.codigo?.toLowerCase().contains(_busca.toLowerCase()) ?? false);

      final matchingForn =
          _fornecedorFiltro == null ||
          (p.fornecedorNome ?? 'Não informado') == _fornecedorFiltro;

      return matchingBusca && matchingForn;
    }).toList();

    filtrados.sort((a, b) {
      if (a.estoque == 0 && b.estoque > 0) return -1;
      if (b.estoque == 0 && a.estoque > 0) return 1;
      return a.estoque.compareTo(b.estoque);
    });

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Relatório de Reposição',
          actions: [
            IconButton(
              tooltip: 'Pedidos de compra salvos',
              onPressed: _abrirListaPedidos,
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.shade900.withOpacity(0.3),
                    Colors.orange.shade900.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selecionados.length} ITENS SELECIONADOS',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Filtre e selecione os itens que deseja comprar.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selecionados.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _exibirPedidoCompra(
                        service.produtos
                            .where((p) => _selecionados.contains(p.id))
                            .toList(),
                      ),
                      icon: const Icon(Icons.list_alt_rounded, size: 18),
                      label: const Text('GERAR PEDIDO'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (fornecedores.isNotEmpty)
              Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: fornecedores.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final forn = isAll ? null : fornecedores[index - 1];
                    final isSelected = _fornecedorFiltro == forn;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          isAll ? 'TODOS FORNECEDORES' : forn!,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: Colors.white.withOpacity(0.05),
                        selectedColor: Colors.cyanAccent,
                        showCheckmark: false,
                        onSelected: (val) =>
                            setState(() => _fornecedorFiltro = forn),
                      ),
                    );
                  },
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      onChanged: (v) => setState(() => _busca = v),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Filtrar produtos...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.white.withOpacity(0.3),
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => setState(() {
                      if (_selecionados.length == filtrados.length) {
                        _selecionados.clear();
                      } else {
                        _selecionados.addAll(filtrados.map((p) => p.id));
                      }
                    }),
                    icon: Icon(
                      _selecionados.isEmpty
                          ? Icons.select_all_rounded
                          : (_selecionados.length == filtrados.length
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded),
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.1),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _busca.isEmpty
                                ? 'Nenhum produto crítico.'
                                : 'Nenhum produto encontrado.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final p = filtrados[index];
                        final isCritico = p.estoque == 0;
                        final percent = p.estoqueMinimo > 0
                            ? (p.estoque / p.estoqueMinimo).clamp(0.0, 1.0)
                            : 0.0;
                        final isSelected = _selecionados.contains(p.id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.cyanAccent.withOpacity(0.05)
                                : Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.cyanAccent.withOpacity(0.3)
                                  : (isCritico
                                        ? Colors.redAccent.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.05)),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => setState(() {
                              if (isSelected)
                                _selecionados.remove(p.id);
                              else
                                _selecionados.add(p.id);
                            }),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (val) => setState(() {
                                          if (val == true)
                                            _selecionados.add(p.id);
                                          else
                                            _selecionados.remove(p.id);
                                        }),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        activeColor: Colors.cyanAccent,
                                        checkColor: Colors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  p.nome,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                if (comPedidoAberto.contains(p.id)) ...[
                                                  const SizedBox(width: 8),
                                                  Tooltip(
                                                    message:
                                                        'Existe pedido de compra em aberto para este produto.',
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .greenAccent
                                                            .withOpacity(0.2),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        'JÁ PEDIDO',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .greenAccent,
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'Forn: ${p.fornecedorNome ?? "?"}',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.6),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (p.precoCusto != null)
                                                  Text(
                                                    '• R\$ ${p.precoCusto!.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      color: const Color(
                                                        0xFF00FF9D,
                                                      ),
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      shadows: [
                                                        Shadow(
                                                          color: const Color(
                                                            0xFF00FF9D,
                                                          ).withOpacity(0.4),
                                                          blurRadius: 4,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      _buildGiroSuggestion(
                                        p,
                                        service.vendasBalcao,
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            p.estoque <= 0
                                                ? 'ZERADO'
                                                : '${p.estoque} / ${p.estoqueMinimo}',
                                            style: TextStyle(
                                              color: isCritico
                                                  ? Colors.redAccent
                                                  : Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            p.estoqueMinimo > 0
                                                ? 'Falta: ${p.estoqueMinimo - p.estoque}'
                                                : 'Mínimo: N/C',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      backgroundColor: Colors.white.withOpacity(
                                        0.05,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isCritico
                                            ? Colors.redAccent
                                            : Colors.orangeAccent,
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
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

  Widget _buildGiroSuggestion(Produto p, List<VendaBalcao> vendas) {
    final trintaDiasAtras = DateTime.now().subtract(const Duration(days: 30));
    double totalVendido = 0;

    for (var v in vendas) {
      if (v.dataVenda.isAfter(trintaDiasAtras) && !v.cancelado) {
        for (var item in v.itens) {
          if (item.id == p.id) {
            totalVendido += item.quantidade.toDouble();
          }
        }
      }
    }

    final sugestao = (totalVendido * 1.2).ceil();
    if (sugestao <= p.estoqueMinimo) return const SizedBox.shrink();

    return Tooltip(
      message:
          'Giro de 30 dias: $totalVendido. Sugerimos mínimo de $sugestao (+20%)',
      child: TextButton(
        onPressed: () => _confirmarAtualizacaoMinimo(p, sugestao.toDouble()),
        style: TextButton.styleFrom(
          backgroundColor: Colors.blueAccent.withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_graph_rounded,
              color: Colors.blueAccent,
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              'SUGESTÃO: $sugestao',
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarAtualizacaoMinimo(Produto p, double novoMinimo) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Confirmar Sugestão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja atualizar o estoque mínimo de "${p.nome}" para $novoMinimo unidades?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NÃO', style: TextStyle(color: Colors.white24)),
          ),
          ElevatedButton(
            onPressed: () async {
              final service = Provider.of<DataService>(context, listen: false);
              final updated = p.copyWith(
                estoqueMinimo: novoMinimo,
                updatedAt: DateTime.now(),
              );
              await service.updateProduto(updated);
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Estoque mínimo atualizado!')),
                );
              }
            },
            child: const Text('SIM, ATUALIZAR'),
          ),
        ],
      ),
    );
  }
}

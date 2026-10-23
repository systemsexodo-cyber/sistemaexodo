import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/pedido_compra.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../utils/units.dart' as units;
import '../widgets/pedido_compra_status_badge.dart';
import 'pedido_compra_detalhe_page.dart';
import 'pedido_compra_form_page.dart';
import 'receber_pedido_compra_page.dart';

/// Lista de todos os pedidos de compra salvos no sistema.
class PedidosCompraPage extends StatefulWidget {
  const PedidosCompraPage({super.key});

  @override
  State<PedidosCompraPage> createState() => _PedidosCompraPageState();
}

class _PedidosCompraPageState extends State<PedidosCompraPage> {
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';
  String? _statusFiltro;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  static final DateFormat _data = DateFormat('dd/MM/yyyy');

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _novoPedido() async {
    final criado = await Navigator.push<PedidoCompra>(
      context,
      MaterialPageRoute(builder: (_) => const PedidoCompraFormPage()),
    );
    if (criado == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoCompraDetalhePage(pedidoId: criado.id),
      ),
    );
  }

  void _abrirDetalhe(PedidoCompra pedido) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoCompraDetalhePage(pedidoId: pedido.id),
      ),
    );
  }

  Future<void> _editar(PedidoCompra pedido) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PedidoCompraFormPage(pedido: pedido)),
    );
  }

  Future<void> _receber(PedidoCompra pedido) async {
    final recebeu = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceberPedidoCompraPage(pedidoId: pedido.id),
      ),
    );
    if (recebeu == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrada registrada no estoque.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _enviar(PedidoCompra pedido) async {
    final service = Provider.of<DataService>(context, listen: false);
    await service.marcarPedidoCompraEnviado(pedido.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pedido marcado como enviado ao fornecedor.'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _acaoRapida(PedidoCompra pedido, String acao) {
    switch (acao) {
      case 'detalhes':
        _abrirDetalhe(pedido);
        break;
      case 'editar':
        _editar(pedido);
        break;
      case 'enviar':
        _enviar(pedido);
        break;
      case 'receber':
        _receber(pedido);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final pedidos = [...service.pedidosCompra]
      ..sort((a, b) => b.dataCriacao.compareTo(a.dataCriacao));

    final termo = _busca.trim().toLowerCase();
    final filtrados = pedidos.where((pedido) {
      final combinaStatus =
          _statusFiltro == null || pedido.status == _statusFiltro;
      if (!combinaStatus) return false;
      if (termo.isEmpty) return true;
      if (pedido.numero.toLowerCase().contains(termo)) return true;
      if (pedido.fornecedorNome.toLowerCase().contains(termo)) return true;
      return pedido.itens.any(
        (item) => item.produtoNome.toLowerCase().contains(termo),
      );
    }).toList();

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Pedidos de Compra',
          actions: [
            IconButton(
              tooltip: 'Novo pedido',
              onPressed: _novoPedido,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _novoPedido,
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text(
            'NOVO PEDIDO',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        body: Column(
          children: [
            _resumo(pedidos),
            _filtros(pedidos),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _buscaController,
                onChanged: (valor) => setState(() => _busca = valor),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por número, fornecedor ou produto...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.white.withOpacity(0.3),
                    size: 20,
                  ),
                  suffixIcon: _busca.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() {
                            _buscaController.clear();
                            _busca = '';
                          }),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtrados.isEmpty
                  ? _estadoVazio(pedidos.isEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) =>
                          _cardPedido(filtrados[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumo(List<PedidoCompra> pedidos) {
    final abertos = pedidos.where((pedido) => pedido.emAberto).toList();
    final parciais = pedidos
        .where((pedido) => pedido.status == StatusPedidoCompra.recebidoParcial)
        .length;
    final valorAberto = abertos.fold(
      0.0,
      (total, pedido) => total + pedido.valorTotal,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.tealAccent.withOpacity(0.12),
            Colors.blueAccent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _estatistica(
              'EM ABERTO',
              abertos.length.toString(),
              Colors.tealAccent,
            ),
          ),
          _divisor(),
          Expanded(
            child: _estatistica(
              'RECEBENDO',
              parciais.toString(),
              Colors.orangeAccent,
            ),
          ),
          _divisor(),
          Expanded(
            child: _estatistica(
              'VALOR EM ABERTO',
              _moeda.format(valorAberto),
              const Color(0xFF00FF9D),
              pequeno: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estatistica(
    String rotulo,
    String valor,
    Color cor, {
    bool pequeno = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          valor,
          style: TextStyle(
            color: cor,
            fontSize: pequeno ? 13 : 20,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _divisor() {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white.withOpacity(0.07),
    );
  }

  Widget _filtros(List<PedidoCompra> pedidos) {
    final contagens = <String, int>{};
    for (final pedido in pedidos) {
      contagens[pedido.status] = (contagens[pedido.status] ?? 0) + 1;
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chipFiltro('TODOS', pedidos.length, null),
          ...StatusPedidoCompra.todos.map(
            (status) => _chipFiltro(
              StatusPedidoCompra.rotulo(status).toUpperCase(),
              contagens[status] ?? 0,
              status,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro(String rotulo, int quantidade, String? status) {
    final selecionado = _statusFiltro == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selecionado,
        label: Text(
          quantidade > 0 ? '$rotulo ($quantidade)' : rotulo,
          style: TextStyle(
            color: selecionado ? Colors.black : Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white.withOpacity(0.05),
        selectedColor: status == null
            ? Colors.cyanAccent
            : corStatusPedidoCompra(status),
        showCheckmark: false,
        onSelected: (_) => setState(() => _statusFiltro = status),
      ),
    );
  }

  Widget _cardPedido(PedidoCompra pedido) {
    final cor = corStatusPedidoCompra(pedido.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.16)),
      ),
      child: InkWell(
        onTap: () => _abrirDetalhe(pedido),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      iconeStatusPedidoCompra(pedido.status),
                      color: cor,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              pedido.numero,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PedidoCompraStatusBadge(
                              status: pedido.status,
                              compacto: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pedido.fornecedorNome}  •  '
                          '${pedido.itens.length} item(ns)  •  '
                          '${_data.format(pedido.dataCriacao)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _moeda.format(pedido.valorTotal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pedido.quantidadePendente > 0
                            ? '${units.formatarNumero(pedido.quantidadePendente)} pendente(s)'
                            : 'Completo',
                        style: TextStyle(
                          color: pedido.quantidadePendente > 0
                              ? Colors.orangeAccent
                              : const Color(0xFF00C853),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Ações do pedido',
                    color: const Color(0xFF1E1E2E),
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onSelected: (acao) => _acaoRapida(pedido, acao),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'detalhes',
                        child: _ItemMenu(
                          icone: Icons.visibility_outlined,
                          texto: 'Abrir detalhes',
                        ),
                      ),
                      if (pedido.status == StatusPedidoCompra.rascunho)
                        const PopupMenuItem(
                          value: 'editar',
                          child: _ItemMenu(
                            icone: Icons.edit_outlined,
                            texto: 'Editar rascunho',
                          ),
                        ),
                      if (pedido.status == StatusPedidoCompra.rascunho)
                        const PopupMenuItem(
                          value: 'enviar',
                          child: _ItemMenu(
                            icone: Icons.send_rounded,
                            texto: 'Marcar como enviado',
                          ),
                        ),
                      if (pedido.podeReceber)
                        const PopupMenuItem(
                          value: 'receber',
                          child: _ItemMenu(
                            icone: Icons.move_to_inbox_rounded,
                            texto: 'Receber no estoque',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (pedido.quantidadeRecebida > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pedido.percentualRecebido / 100)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    minHeight: 4,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(cor),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoVazio(bool nenhumPedido) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.12),
            ),
            const SizedBox(height: 16),
            Text(
              nenhumPedido
                  ? 'Nenhum pedido de compra ainda.\nCrie um pedido ou use o relatório de reposição.'
                  : 'Nenhum pedido encontrado com esse filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            if (nenhumPedido) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _novoPedido,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('CRIAR PEDIDO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _ItemMenu({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 17, color: Colors.white54),
        const SizedBox(width: 9),
        Text(
          texto,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/pedido_compra.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/pedido_compra_pdf_service.dart';
import '../theme.dart';
import '../utils/units.dart' as units;
import '../widgets/pedido_compra_status_badge.dart';
import 'pedido_compra_form_page.dart';
import 'receber_pedido_compra_page.dart';

/// Ficha completa de um pedido de compra salvo.
class PedidoCompraDetalhePage extends StatefulWidget {
  final String pedidoId;

  const PedidoCompraDetalhePage({super.key, required this.pedidoId});

  @override
  State<PedidoCompraDetalhePage> createState() =>
      _PedidoCompraDetalhePageState();
}

class _PedidoCompraDetalhePageState extends State<PedidoCompraDetalhePage> {
  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  static final DateFormat _data = DateFormat('dd/MM/yyyy');
  static final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');

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

  Future<void> _cancelar(PedidoCompra pedido) async {
    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: Text(
          'Cancelar ${pedido.numero}?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O pedido fica encerrado e o selo "JÁ PEDIDO" dos produtos é '
              'recalculado. Nenhuma mercadoria é movimentada.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Ex.: fornecedor sem estoque',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'VOLTAR',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('CANCELAR PEDIDO'),
          ),
        ],
      ),
    );
    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (confirmar != true || !mounted) return;

    final service = Provider.of<DataService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    await service.cancelarPedidoCompra(
      pedido.id,
      motivo: motivo.isEmpty ? null : motivo,
      usuario: auth.usuarioAtual?.nome ?? auth.usuarioAtual?.email,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pedido cancelado.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _excluir(PedidoCompra pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: Text(
          'Excluir ${pedido.numero}?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          pedido.quantidadeRecebida > 0
              ? 'Este pedido já tem mercadoria recebida. Excluir o pedido NÃO '
                    'estorna o estoque — as entradas continuam no histórico. '
                    'Para devolver mercadoria use uma saída/ajuste de estoque.'
              : 'O pedido será removido definitivamente.',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'VOLTAR',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final service = Provider.of<DataService>(context, listen: false);
    await service.deletePedidoCompra(pedido.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _imprimir(PedidoCompra pedido) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await PedidoCompraPdfService.imprimir(
        pedido: pedido,
        empresa: auth.empresaAtual,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível gerar o PDF: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _copiar(PedidoCompra pedido) async {
    await Clipboard.setData(
      ClipboardData(text: PedidoCompraPdfService.textoParaCompartilhar(pedido)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Texto do pedido copiado! Cole no WhatsApp ou e-mail.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final pedido = service.pedidoCompraPorId(widget.pedidoId);

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: pedido == null
              ? 'Pedido de Compra'
              : 'Pedido ${pedido.numero}',
          actions: pedido == null
              ? null
              : [
                  IconButton(
                    tooltip: 'Imprimir PDF',
                    onPressed: () => _imprimir(pedido),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                  IconButton(
                    tooltip: 'Copiar texto do pedido',
                    onPressed: () => _copiar(pedido),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
        ),
        body: pedido == null
            ? const Center(
                child: Text(
                  'Pedido não encontrado.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _cabecalho(pedido),
                  const SizedBox(height: 14),
                  _acoes(pedido),
                  const SizedBox(height: 14),
                  _itens(pedido),
                  const SizedBox(height: 14),
                  _totais(pedido),
                  if ((pedido.observacao ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _observacao(pedido),
                  ],
                  if (pedido.motivoCancelamento != null &&
                      pedido.motivoCancelamento!.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _motivoCancelamento(pedido),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _cabecalho(PedidoCompra pedido) {
    final cor = corStatusPedidoCompra(pedido.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cor.withOpacity(0.18), Colors.white.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  iconeStatusPedidoCompra(pedido.status),
                  color: cor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.numero,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pedido.fornecedorNome,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              PedidoCompraStatusBadge(status: pedido.status),
            ],
          ),
          const SizedBox(height: 16),
          _barraProgresso(pedido, cor),
          const SizedBox(height: 14),
          Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              _info(
                Icons.event_outlined,
                'Criado em',
                _dataHora.format(pedido.dataCriacao),
              ),
              _info(
                Icons.local_shipping_outlined,
                pedido.dataRecebimento != null
                    ? 'Recebido em'
                    : 'Previsão de entrega',
                pedido.dataRecebimento != null
                    ? _dataHora.format(pedido.dataRecebimento!)
                    : pedido.previsaoEntrega == null
                    ? 'Sem data'
                    : _data.format(pedido.previsaoEntrega!),
              ),
              _info(
                Icons.warehouse_outlined,
                'Estoque de destino',
                (pedido.estoqueDestinoNome ?? '').trim().isEmpty
                    ? 'Estoque principal'
                    : pedido.estoqueDestinoNome!,
              ),
              if ((pedido.usuario ?? '').trim().isNotEmpty)
                _info(Icons.person_outline, 'Comprador', pedido.usuario!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barraProgresso(PedidoCompra pedido, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${units.formatarNumero(pedido.quantidadeRecebida)} de '
              '${units.formatarNumero(pedido.quantidadeTotal)} recebidos',
              style: const TextStyle(color: Colors.white54, fontSize: 10.5),
            ),
            const Spacer(),
            Text(
              '${pedido.percentualRecebido.toStringAsFixed(0)}%',
              style: TextStyle(
                color: cor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pedido.percentualRecebido / 100,
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation<Color>(cor),
          ),
        ),
      ],
    );
  }

  Widget _info(IconData icone, String rotulo, String valor) {
    return SizedBox(
      width: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: Colors.white38, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 7.5,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  valor,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _acoes(PedidoCompra pedido) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (pedido.status == StatusPedidoCompra.rascunho)
          _botaoAcao(
            'Editar',
            Icons.edit_outlined,
            Colors.blueAccent,
            () => _editar(pedido),
          ),
        if (pedido.status == StatusPedidoCompra.rascunho)
          _botaoAcao(
            'Enviar ao fornecedor',
            Icons.send_rounded,
            Colors.blueAccent,
            () => _enviar(pedido),
          ),
        if (pedido.podeReceber)
          _botaoAcao(
            'Receber no estoque',
            Icons.move_to_inbox_rounded,
            Colors.tealAccent,
            () => _receber(pedido),
          ),
        _botaoAcao(
          'PDF',
          Icons.picture_as_pdf_outlined,
          Colors.white70,
          () => _imprimir(pedido),
        ),
        _botaoAcao(
          'Copiar texto',
          Icons.copy_all_outlined,
          Colors.white70,
          () => _copiar(pedido),
        ),
        if (pedido.emAberto)
          _botaoAcao(
            'Cancelar',
            Icons.cancel_outlined,
            Colors.orangeAccent,
            () => _cancelar(pedido),
          ),
        _botaoAcao(
          'Excluir',
          Icons.delete_outline_rounded,
          Colors.redAccent,
          () => _excluir(pedido),
        ),
      ],
    );
  }

  Widget _botaoAcao(
    String rotulo,
    IconData icone,
    Color cor,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icone, size: 16),
      label: Text(rotulo, style: const TextStyle(fontSize: 10.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: cor,
        side: BorderSide(color: cor.withOpacity(0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _itens(PedidoCompra pedido) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shopping_basket_outlined,
                color: Colors.cyanAccent,
                size: 17,
              ),
              const SizedBox(width: 7),
              const Text(
                'ITENS DO PEDIDO',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${pedido.itens.length} item(ns)',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...pedido.itens.map(_item),
        ],
      ),
    );
  }

  Widget _item(ItemPedidoCompra item) {
    final cor = item.recebido
        ? const Color(0xFF00C853)
        : item.parcial
        ? Colors.orangeAccent
        : Colors.white38;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.produtoNome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((item.codigo ?? '').isNotEmpty)
                          'Cód.: ${item.codigo}',
                        '${units.formatarNumero(item.quantidade)} ${item.unidade}',
                        'x ${_moeda.format(item.precoCusto)}',
                      ].join('  •  '),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _moeda.format(item.valorTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.recebido
                        ? 'Recebido'
                        : item.parcial
                        ? 'Falta ${units.formatarNumero(item.quantidadePendente)}'
                        : 'Pendente',
                    style: TextStyle(
                      color: cor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (item.quantidadeRecebida > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.quantidade > 0
                    ? (item.quantidadeRecebida / item.quantidade).clamp(
                        0.0,
                        1.0,
                      )
                    : 0,
                minHeight: 4,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation<Color>(cor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totais(PedidoCompra pedido) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00FF9D).withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00FF9D).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL DO PEDIDO',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _moeda.format(pedido.valorTotal),
                  style: const TextStyle(
                    color: Color(0xFF00FF9D),
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${units.formatarNumero(pedido.quantidadeTotal)} un. pedidas',
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
              const SizedBox(height: 3),
              Text(
                '${units.formatarNumero(pedido.quantidadePendente)} un. pendentes',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _observacao(PedidoCompra pedido) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OBSERVAÇÃO',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pedido.observacao!.trim(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _motivoCancelamento(PedidoCompra pedido) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MOTIVO DO CANCELAMENTO',
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pedido.motivoCancelamento!.trim(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (pedido.dataCancelamento != null) ...[
            const SizedBox(height: 3),
            Text(
              _dataHora.format(pedido.dataCancelamento!),
              style: const TextStyle(color: Colors.white38, fontSize: 9.5),
            ),
          ],
        ],
      ),
    );
  }
}

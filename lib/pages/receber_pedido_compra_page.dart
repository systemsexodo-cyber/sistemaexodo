import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/pedido_compra.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../utils/units.dart' as units;
import '../widgets/pedido_compra_status_badge.dart';

/// Recebimento (total ou parcial) de um pedido de compra.
///
/// Cada item recebido passa pelo fluxo normal de entrada de estoque, então o
/// saldo do produto, o saldo por fornecedor/estoque e o histórico continuam
/// registrados como qualquer outra entrada.
class ReceberPedidoCompraPage extends StatefulWidget {
  final String pedidoId;

  const ReceberPedidoCompraPage({super.key, required this.pedidoId});

  @override
  State<ReceberPedidoCompraPage> createState() =>
      _ReceberPedidoCompraPageState();
}

class _ReceberPedidoCompraPageState extends State<ReceberPedidoCompraPage> {
  final Map<String, TextEditingController> _controllers = {};
  String? _estoqueId;
  bool _atualizarCusto = true;
  bool _processando = false;
  bool _inicializado = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inicializado) return;
    _inicializado = true;

    final service = Provider.of<DataService>(context, listen: false);
    final pedido = service.pedidoCompraPorId(widget.pedidoId);
    if (pedido == null) return;

    for (final item in pedido.itens) {
      if (item.recebido) continue;
      _controllers[item.id] = TextEditingController(
        text: units.formatarNumero(item.quantidadePendente),
      );
    }
    _estoqueId = pedido.estoqueDestinoId;
    if (_estoqueId == null || _estoqueId!.isEmpty) {
      _estoqueId = service.estoquePrincipalAtual?.id;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _quantidadeDe(ItemPedidoCompra item) {
    final texto = _controllers[item.id]?.text ?? '';
    final valor = double.tryParse(texto.trim().replaceAll(',', '.')) ?? 0;
    if (valor <= 0) return 0;
    return valor > item.quantidadePendente ? item.quantidadePendente : valor;
  }

  double _totalRecebendo(PedidoCompra pedido) {
    return pedido.itens.fold(
      0.0,
      (total, item) => total + (_quantidadeDe(item) * item.precoCusto),
    );
  }

  void _receberTudo(PedidoCompra pedido) {
    setState(() {
      for (final item in pedido.itens) {
        if (item.recebido) continue;
        _controllers[item.id]?.text = units.formatarNumero(
          item.quantidadePendente,
        );
      }
    });
  }

  Future<void> _confirmar(PedidoCompra pedido) async {
    if (_processando) return;

    final quantidades = <String, double>{};
    for (final item in pedido.itens) {
      if (item.recebido) continue;
      final quantidade = _quantidadeDe(item);
      if (quantidade > 0) quantidades[item.id] = quantidade;
    }
    if (quantidades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a quantidade recebida de pelo menos um item.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _processando = true);
    final service = Provider.of<DataService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    final usuario = auth.usuarioAtual?.nome ?? auth.usuarioAtual?.email;

    try {
      final resultado = await service.receberPedidoCompra(
        pedidoId: pedido.id,
        quantidadesPorItem: quantidades,
        estoqueId: _estoqueId,
        usuario: usuario,
        atualizarCusto: _atualizarCusto,
      );
      if (!mounted) return;

      if (resultado.itensRecebidos == 0) {
        setState(() => _processando = false);
        _mostrarAvisos(resultado);
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          title: Row(
            children: [
              Icon(
                resultado.completo
                    ? Icons.check_circle_rounded
                    : Icons.inventory_2_rounded,
                color: resultado.completo
                    ? const Color(0xFF00FF9D)
                    : Colors.orangeAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  resultado.completo
                      ? 'Pedido recebido'
                      : 'Recebimento parcial',
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${resultado.itensRecebidos} item(ns) recebido(s) — '
                '${units.formatarNumero(resultado.quantidadeRecebida)} unidade(s).',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                resultado.completo
                    ? 'A entrada foi lançada no estoque e o pedido está concluído.'
                    : 'O saldo que faltava continua pendente neste pedido.',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              if (resultado.avisos.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...resultado.avisos.map(
                  (aviso) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $aviso',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF9D),
                foregroundColor: Colors.black,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível receber o pedido: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _mostrarAvisos(ResultadoRecebimentoPedidoCompra resultado) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: const Text(
          'Nenhum item recebido',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          resultado.avisos.isEmpty
              ? 'Confira as quantidades informadas.'
              : resultado.avisos.join('\n'),
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'FECHAR',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Receber Pedido de Compra'),
        body: Consumer<DataService>(
          builder: (context, service, _) {
            final pedido = service.pedidoCompraPorId(widget.pedidoId);
            if (pedido == null) {
              return const Center(
                child: Text(
                  'Pedido não encontrado.',
                  style: TextStyle(color: Colors.white54),
                ),
              );
            }
            final pendentes = pedido.itens
                .where((item) => !item.recebido)
                .toList();

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _cabecalho(pedido),
                      const SizedBox(height: 14),
                      if (pendentes.isEmpty)
                        _tudoRecebido()
                      else ...[
                        Row(
                          children: [
                            const Text(
                              'ITENS A RECEBER',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _processando
                                  ? null
                                  : () => _receberTudo(pedido),
                              icon: const Icon(
                                Icons.done_all_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'RECEBER TUDO',
                                style: TextStyle(fontSize: 10.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ...pendentes.map(
                          (item) => _construirItem(pedido, item),
                        ),
                        const SizedBox(height: 6),
                        _cardDestino(service),
                        const SizedBox(height: 10),
                        _cardCusto(),
                      ],
                    ],
                  ),
                ),
                if (pendentes.isNotEmpty) _barraConfirmar(pedido),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalho(PedidoCompra pedido) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.move_to_inbox_rounded,
                  color: Colors.tealAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.numero,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      pedido.fornecedorNome,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PedidoCompraStatusBadge(status: pedido.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Recebido até agora: '
            '${units.formatarNumero(pedido.quantidadeRecebida)} de '
            '${units.formatarNumero(pedido.quantidadeTotal)}. '
            'Ajuste abaixo somente o que chegou nesta entrega.',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tudoRecebido() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF00FF9D),
            size: 48,
          ),
          SizedBox(height: 12),
          Text(
            'Todos os itens deste pedido já foram recebidos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _construirItem(PedidoCompra pedido, ItemPedidoCompra item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.produtoNome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'Falta ${units.formatarNumero(item.quantidadePendente)} ${item.unidade}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Pedido: ${units.formatarNumero(item.quantidade)} ${item.unidade}'
            '  •  Já recebido: ${units.formatarNumero(item.quantidadeRecebida)}'
            '  •  Custo: ${_moeda.format(item.precoCusto)}',
            style: const TextStyle(color: Colors.white38, fontSize: 9.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controllers[item.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Receber agora (${item.unidade})',
                    hintText: units.formatarNumero(item.quantidadePendente),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Preencher com o total pendente',
                      onPressed: () => setState(() {
                        _controllers[item.id]?.text = units.formatarNumero(
                          item.quantidadePendente,
                        );
                      }),
                      icon: const Icon(Icons.done_all_rounded, size: 17),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'VALOR',
                      style: TextStyle(color: Colors.white38, fontSize: 8),
                    ),
                    Text(
                      _moeda.format(_quantidadeDe(item) * item.precoCusto),
                      style: const TextStyle(
                        color: Color(0xFF00FF9D),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardDestino(DataService service) {
    final estoqueSelecionado =
        service.estoques.any((estoque) => estoque.id == _estoqueId)
        ? _estoqueId
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: DropdownButtonFormField<String?>(
        value: estoqueSelecionado,
        isExpanded: true,
        dropdownColor: const Color(0xFF1E1E2E),
        decoration: const InputDecoration(
          labelText: 'Dar entrada no estoque',
          prefixIcon: Icon(Icons.warehouse_outlined),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Estoque principal'),
          ),
          ...service.estoques.map(
            (estoque) => DropdownMenuItem<String?>(
              value: estoque.id,
              child: Text(
                estoque.principal
                    ? '${estoque.nome} (principal)'
                    : estoque.nome,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: _processando
            ? null
            : (valor) => setState(() => _estoqueId = valor),
      ),
    );
  }

  Widget _cardCusto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: CheckboxListTile(
        value: _atualizarCusto,
        onChanged: _processando
            ? null
            : (valor) => setState(() => _atualizarCusto = valor == true),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: Colors.tealAccent,
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Atualizar o custo do produto',
          style: TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        subtitle: const Text(
          'Usa o custo informado neste pedido no cadastro do produto.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ),
    );
  }

  Widget _barraConfirmar(PedidoCompra pedido) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'VALOR RECEBENDO: ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  _moeda.format(_totalRecebendo(pedido)),
                  style: const TextStyle(
                    color: Color(0xFF00FF9D),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processando ? null : () => _confirmar(pedido),
                icon: _processando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: const Text('CONFIRMAR ENTRADA NO ESTOQUE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

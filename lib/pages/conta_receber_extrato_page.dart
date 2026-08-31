import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/cliente.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';

/// Página de extrato detalhado do cliente — estilo "pedidos tela grande".
/// Mostra todas as transações de um cliente com valores pagos, em aberto
/// e opção de expandir para ver itens de cada venda/pedido.
class ContaReceberExtratoPage extends StatefulWidget {
  final String clienteNome;
  final String? clienteId;

  const ContaReceberExtratoPage({
    super.key,
    required this.clienteNome,
    this.clienteId,
  });

  @override
  State<ContaReceberExtratoPage> createState() =>
      _ContaReceberExtratoPageState();
}

class _ContaReceberExtratoPageState extends State<ContaReceberExtratoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _fmtData = DateFormat('dd/MM/yyyy');
  final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');
  final NumberFormat _fmtMoeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Set<String> _expandidas = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);

    // 1. Buscar contas vinculadas ao cliente
    final contas = _buscarContasCliente(dataService);

    // 2. Buscar vendas/pedidos vinculados ao cliente
    final vendas = _buscarVendasCliente(dataService, contas);
    final pedidos = _buscarPedidosCliente(dataService, contas);

    // 3. Calcular totais
    double totalVendas = 0;
    double totalPago = 0;
    double totalPendente = 0;
    int qtdVendas = vendas.length + pedidos.length;

    for (final c in contas) {
      totalVendas += c.valor;
      totalPago += c.valorPago ?? 0;
      totalPendente += c.valorPendente;
    }

    // 4. Contas atrasadas
    final contasAtrasadas =
        contas.where((c) => c.statusAtualizado == StatusContaPagar.vencido).toList();
    final totalAtrasado = contasAtrasadas.fold<double>(
        0.0, (sum, c) => sum + c.valorPendente);

    // 5. Dias de atraso médio
    final hoje = DateTime.now();
    int diasAtrasoMedio = 0;
    if (contasAtrasadas.isNotEmpty) {
      int somaDias = 0;
      for (final c in contasAtrasadas) {
        final diff = hoje.difference(c.dataVencimento).inDays;
        somaDias += diff;
      }
      diasAtrasoMedio = (somaDias / contasAtrasadas.length).round();
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.clienteNome,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (widget.clienteId != null)
                Text(
                  'ID: ${widget.clienteId!.substring(0, widget.clienteId!.length > 8 ? 8 : widget.clienteId!.length)}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withOpacity(0.5)),
                ),
            ],
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.summarize, size: 18), text: 'Resumo'),
              Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Extrato'),
              Tab(icon: Icon(Icons.warning_amber, size: 18), text: 'Atrasados'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Dashboard resumo
            _buildDashboardResumo(
                totalVendas, totalPago, totalPendente, qtdVendas,
                totalAtrasado, diasAtrasoMedio, contasAtrasadas.length),
            // Conteúdo
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAbaResumo(contas, dataService),
                  _buildAbaExtrato(contas, dataService),
                  _buildAbaAtrasados(contasAtrasadas, dataService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DASHBOARD ──────────────────────────────────────────────────────

  Widget _buildDashboardResumo(
    double totalVendas,
    double totalPago,
    double totalPendente,
    int qtdVendas,
    double totalAtrasado,
    int diasAtrasoMedio,
    int qtdAtrasadas,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _miniCard(Icons.shopping_bag, 'Vendas',
                  '$qtdVendas', Colors.blueAccent, _fmtMoeda.format(totalVendas)),
              const SizedBox(width: 8),
              _miniCard(Icons.check_circle, 'Pago',
                  '', Colors.greenAccent, _fmtMoeda.format(totalPago)),
              const SizedBox(width: 8),
              _miniCard(Icons.pending, 'Aberto',
                  '', Colors.orangeAccent, _fmtMoeda.format(totalPendente)),
            ],
          ),
          if (qtdAtrasadas > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$qtdAtrasadas conta(s) atrasada(s) — média $diasAtrasoMedio dias',
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  Text(
                    _fmtMoeda.format(totalAtrasado),
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniCard(IconData icon, String label, String sub, Color cor,
      String valor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(valor,
                style: TextStyle(
                    color: cor, fontSize: 15, fontWeight: FontWeight.bold)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── ABA RESUMO ─────────────────────────────────────────────────────

  Widget _buildAbaResumo(List<ContaPagar> contas, DataService ds) {
    if (contas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64,
                color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('Nenhuma conta encontrada',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 16)),
          ],
        ),
      );
    }

    // Agrupar por tipo (Fiado / Crediário / Avulsa)
    final fiado = contas.where((c) {
      if (c.id.startsWith('venda_')) {
        final idReal = c.id.replaceFirst('venda_', '');
        try {
          final v = ds.vendasBalcao.firstWhere((v) => v.id == idReal);
          return v.tipoPagamento == TipoPagamento.fiado;
        } catch (_) {}
      } else if (c.id.startsWith('pedido_')) {
        final idReal = c.id.replaceFirst('pedido_', '');
        try {
          final p = ds.pedidos.firstWhere((p) => p.id == idReal);
          return p.pagamentos
              .any((pag) => pag.tipo == TipoPagamento.fiado);
        } catch (_) {}
      }
      return false;
    }).toList();

    final crediario = contas.where((c) {
      if (c.id.startsWith('venda_')) {
        final idReal = c.id.replaceFirst('venda_', '');
        try {
          final v = ds.vendasBalcao.firstWhere((v) => v.id == idReal);
          return v.tipoPagamento == TipoPagamento.crediario;
        } catch (_) {}
      } else if (c.id.startsWith('pedido_')) {
        final idReal = c.id.replaceFirst('pedido_', '');
        try {
          final p = ds.pedidos.firstWhere((p) => p.id == idReal);
          return p.pagamentos
              .any((pag) => pag.tipo == TipoPagamento.crediario);
        } catch (_) {}
      }
      return false;
    }).toList();

    final avulsas =
        contas.where((c) => !fiado.contains(c) && !crediario.contains(c)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fiado.isNotEmpty) ...[
            _secaoResumo('Fiado', Icons.handshake,
                const Color(0xFFD84315), fiado),
            const SizedBox(height: 16),
          ],
          if (crediario.isNotEmpty) ...[
            _secaoResumo('Crediário', Icons.credit_score,
                const Color(0xFFE91E63), crediario),
            const SizedBox(height: 16),
          ],
          if (avulsas.isNotEmpty) ...[
            _secaoResumo(
                'Avulsas', Icons.receipt, Colors.blueAccent, avulsas),
          ],
        ],
      ),
    );
  }

  Widget _secaoResumo(
      String titulo, IconData icone, Color cor, List<ContaPagar> contas) {
    final total = contas.fold<double>(0, (s, c) => s + c.valor);
    final pago = contas.fold<double>(0, (s, c) => s + (c.valorPago ?? 0));
    final pendente = contas.fold<double>(0, (s, c) => s + c.valorPendente);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Text(titulo,
                  style: TextStyle(
                      color: cor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${contas.length} conta(s)',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metricaColuna('Total', _fmtMoeda.format(total), Colors.white),
              const SizedBox(width: 16),
              _metricaColuna('Pago', _fmtMoeda.format(pago), Colors.greenAccent),
              const SizedBox(width: 16),
              _metricaColuna(
                  'Aberto', _fmtMoeda.format(pendente), Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 12),
          // Barra de progresso
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? (pago / total).clamp(0.0, 1.0) : 0,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(cor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${total > 0 ? ((pago / total) * 100).toStringAsFixed(0) : 0}% recebido',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _metricaColuna(String label, String valor, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 10)),
        const SizedBox(height: 2),
        Text(valor,
            style: TextStyle(
                color: cor, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─── ABA EXTRATO ────────────────────────────────────────────────────

  Widget _buildAbaExtrato(List<ContaPagar> contas, DataService ds) {
    if (contas.isEmpty) {
      return Center(
        child: Text('Nenhuma transação encontrada',
            style: TextStyle(color: Colors.white.withOpacity(0.5))),
      );
    }

    // Ordenar por data de vencimento (mais antigo primeiro)
    contas.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    // Calcular saldo acumulado
    double saldoAcumulado = 0;
    final List<Map<String, dynamic>> extrato = [];
    for (final c in contas) {
      saldoAcumulado += c.valorPendente;
      extrato.add({'conta': c, 'saldo': saldoAcumulado});
    }

    return Column(
      children: [
        // Cabeçalho do extrato
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                  child: Text('Data',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Descrição',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Venc.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 80,
                  child: Text('Valor',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 80,
                  child: Text('Status',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              const SizedBox(width: 30),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: extrato.length,
            itemBuilder: (context, index) {
              final item = extrato[index];
              final conta = item['conta'] as ContaPagar;
              return _buildLinhaExtrato(conta, ds);
            },
          ),
        ),
        // Total
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1B5E20).withOpacity(0.8),
                const Color(0xFF2E7D32).withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL EM ABERTO',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(
                _fmtMoeda.format(
                    contas.fold<double>(0, (s, c) => s + c.valorPendente)),
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinhaExtrato(ContaPagar conta, DataService ds) {
    final status = conta.statusAtualizado;
    final isVencida = conta.isVencida;
    final isPago = status == StatusContaPagar.pago;
    final isExpandida = _expandidas.contains(conta.id);

    final cor = isPago
        ? Colors.greenAccent
        : isVencida
            ? Colors.redAccent
            : Colors.orangeAccent;

    // Buscar itens da venda/pedido
    List<Map<String, dynamic>> itens = _buscarItens(conta, ds);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isVencida && !isPago
            ? Colors.red.withOpacity(0.08)
            : isPago
                ? Colors.green.withOpacity(0.06)
                : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: cor.withOpacity(0.2),
            width: isVencida && !isPago ? 1.5 : 0.5),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: itens.isNotEmpty
                ? () {
                    setState(() {
                      if (isExpandida) {
                        _expandidas.remove(conta.id);
                      } else {
                        _expandidas.add(conta.id);
                      }
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Data
                  SizedBox(
                    width: 70,
                    child: Text(
                      _fmtData.format(conta.dataCriacao),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 11),
                    ),
                  ),
                  // Descrição
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conta.descricao,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (itens.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.shopping_bag,
                                  size: 10,
                                  color: Colors.white.withOpacity(0.3)),
                              const SizedBox(width: 4),
                              Text(
                                '${itens.length} item(ns)',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.3),
                                    fontSize: 9),
                              ),
                              if (!isExpandida) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.3)),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Vencimento
                  SizedBox(
                    width: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtData.format(conta.dataVencimento),
                          style: TextStyle(
                              color: isVencida && !isPago
                                  ? Colors.redAccent
                                  : Colors.white.withOpacity(0.6),
                              fontSize: 11,
                              fontWeight: isVencida && !isPago
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                        ),
                        if (isVencida && !isPago)
                          Text(
                            '${DateTime.now().difference(conta.dataVencimento).inDays}d',
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  // Valor
                  SizedBox(
                    width: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmtMoeda.format(conta.valor),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        if ((conta.valorPago ?? 0) > 0 && !isPago)
                          Text(
                            '-${_fmtMoeda.format(conta.valorPago)}',
                            style: const TextStyle(
                                color: Colors.greenAccent, fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  // Status
                  SizedBox(
                    width: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isPago
                                ? 'PAGO'
                                : isVencida
                                    ? 'ATRASO'
                                    : 'ABERTO',
                            style: TextStyle(
                                color: cor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (itens.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isExpandida
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white.withOpacity(0.3),
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Itens expandidos
          if (isExpandida && itens.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 70, right: 12, bottom: 10),
              child: Column(
                children: itens.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['qtd']}x ${item['nome']}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11),
                          ),
                        ),
                        Text(
                          _fmtMoeda.format(item['subtotal']),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buscarItens(ContaPagar conta, DataService ds) {
    if (conta.id.startsWith('venda_')) {
      final idReal = conta.id.replaceFirst('venda_', '');
      try {
        final venda = ds.vendasBalcao.firstWhere((v) => v.id == idReal);
        return venda.itens
            .map((i) => {
                  'qtd': i.quantidade,
                  'nome': i.nome,
                  'subtotal': i.quantidade * i.precoUnitario,
                })
            .toList();
      } catch (_) {}
    } else if (conta.id.startsWith('pedido_')) {
      final idReal = conta.id.replaceFirst('pedido_', '');
      try {
        final pedido = ds.pedidos.firstWhere((p) => p.id == idReal);
        final itens = <Map<String, dynamic>>[];
        for (final p in pedido.produtos) {
          itens.add({
            'qtd': p.quantidade,
            'nome': p.nome,
            'subtotal': p.quantidade * p.preco,
          });
        }
        for (final s in pedido.servicos) {
          itens.add({
            'qtd': 1,
            'nome': s.descricao,
            'subtotal': s.valor + s.valorAdicional,
          });
        }
        return itens;
      } catch (_) {}
    }
    return [];
  }

  // ─── ABA ATRASADOS ──────────────────────────────────────────────────

  Widget _buildAbaAtrasados(
      List<ContaPagar> atrasadas, DataService ds) {
    if (atrasadas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64,
                color: Colors.greenAccent.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma conta atrasada!',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Todos os pagamentos estão em dia',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Ordenar por dias de atraso (mais antigo primeiro)
    atrasadas.sort(
        (a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    final hoje = DateTime.now();
    final totalAtrasado =
        atrasadas.fold<double>(0, (s, c) => s + c.valorPendente);

    // Faixas de atraso
    final ate7 = atrasadas
        .where((c) => hoje.difference(c.dataVencimento).inDays <= 7)
        .toList();
    final de8a30 = atrasadas
        .where((c) {
      final d = hoje.difference(c.dataVencimento).inDays;
      return d > 7 && d <= 30;
    }).toList();
    final mais30 = atrasadas
        .where((c) => hoje.difference(c.dataVencimento).inDays > 30)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumo de risco
          _buildRiscoHeader(totalAtrasado, atrasadas.length),
          const SizedBox(height: 16),

          if (ate7.isNotEmpty) ...[
            _secaoAtraso('Até 7 dias', Colors.orangeAccent, ate7),
            const SizedBox(height: 12),
          ],
          if (de8a30.isNotEmpty) ...[
            _secaoAtraso('8 a 30 dias', Colors.deepOrangeAccent, de8a30),
            const SizedBox(height: 12),
          ],
          if (mais30.isNotEmpty) ...[
            _secaoAtraso('Mais de 30 dias', Colors.redAccent, mais30),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRiscoHeader(double totalAtrasado, int qtd) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8B0000).withOpacity(0.8),
            const Color(0xFFB71C1C).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 32),
          const SizedBox(height: 8),
          Text(
            _fmtMoeda.format(totalAtrasado),
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 28,
                fontWeight: FontWeight.bold),
          ),
          Text(
            '$qtd conta(s) atrasada(s)',
            style: TextStyle(
                color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _secaoAtraso(
      String faixa, Color cor, List<ContaPagar> contas) {
    final total = contas.fold<double>(0, (s, c) => s + c.valorPendente);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                  color: cor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(faixa,
                style: TextStyle(
                    color: cor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${contas.length} — ${_fmtMoeda.format(total)}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        ...contas.map((c) => _buildCardAtraso(c, cor)),
      ],
    );
  }

  Widget _buildCardAtraso(ContaPagar conta, Color cor) {
    final hoje = DateTime.now();
    final diasAtraso = hoje.difference(conta.dataVencimento).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Badge de dias
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$diasAtraso',
                    style: TextStyle(
                        color: cor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text('dias',
                    style: TextStyle(
                        color: cor.withOpacity(0.6), fontSize: 8)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conta.descricao,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Venc: ${_fmtData.format(conta.dataVencimento)}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
                if (conta.fornecedorNome != null)
                  Text(
                    conta.fornecedorNome!,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtMoeda.format(conta.valorPendente),
                style: TextStyle(
                    color: cor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              if ((conta.valorPago ?? 0) > 0)
                Text(
                  'Pago: ${_fmtMoeda.format(conta.valorPago)}',
                  style: TextStyle(
                      color: Colors.greenAccent.withOpacity(0.6),
                      fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────

  List<ContaPagar> _buscarContasCliente(DataService ds) {
    final contasBase =
        ds.contasPagar.where((c) => c.categoria == 'Recebível' && c.ativo);

    // Filtrar por nome do cliente
    if (widget.clienteNome.isNotEmpty) {
      return contasBase.where((c) {
        final nome = c.fornecedorNome ?? '';
        return nome.toLowerCase() == widget.clienteNome.toLowerCase();
      }).toList();
    }
    return contasBase.toList();
  }

  List<VendaBalcao> _buscarVendasCliente(
      DataService ds, List<ContaPagar> contas) {
    final ids = contas
        .where((c) => c.id.startsWith('venda_'))
        .map((c) => c.id.replaceFirst('venda_', ''))
        .toSet();
    return ds.vendasBalcao.where((v) => ids.contains(v.id)).toList();
  }

  List<Pedido> _buscarPedidosCliente(
      DataService ds, List<ContaPagar> contas) {
    final ids = contas
        .where((c) => c.id.startsWith('pedido_'))
        .map((c) => c.id.replaceFirst('pedido_', ''))
        .toSet();
    return ds.pedidos.where((p) => ids.contains(p.id)).toList();
  }
}

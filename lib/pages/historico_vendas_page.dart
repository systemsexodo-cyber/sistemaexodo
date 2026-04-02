import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../models/troca_devolucao.dart';
import '../models/caixa.dart';
import 'home_page.dart';
import '../widgets/sync_status_widget.dart';

class _ProdutoVendido {
  final String nome;
  final String? produtoId;
  int quantidadeTotal = 0;
  double valorTotal = 0.0;
  double? custoTotal;
  String abc = 'C';
  List<_VendaProduto> vendas = [];
  _ProdutoVendido({required this.nome, this.produtoId});

  double get lucroTotal => valorTotal - (custoTotal ?? 0.0);
  
  // Markup: Lucro / Custo (Quanto adicionamos sobre o custo)
  double get markupPercentual => (custoTotal != null && custoTotal! > 0) ? (lucroTotal / custoTotal!) * 100 : 0;
  
  // Margem: Lucro / Venda (Quanto do preço final é lucro)
  double get margemPercentual => (valorTotal > 0) ? (lucroTotal / valorTotal) * 100 : 0;
  
  bool get temCusto => custoTotal != null && custoTotal! > 0;
}

class _VendaProduto {
  final String numeroVenda;
  final DateTime data;
  final int quantidade;
  final double precoUnitario;
  final double valorTotal;
  final String? clienteNome;
  _VendaProduto({required this.numeroVenda, required this.data, required this.quantidade, required this.precoUnitario, required this.valorTotal, this.clienteNome});
}

bool _identificarMesaComanda(String? numero, String? clienteNome, String? status, [String? observacoes, String? origem]) {
  final n = (numero ?? '').toUpperCase();
  final c = (clienteNome ?? '').toUpperCase();
  final st = (status ?? '').toUpperCase();
  final obs = (observacoes ?? '').toUpperCase();
  final ori = (origem ?? '').toUpperCase();
  final allText = '$n $c $st $obs $ori';
  return allText.contains('MESA') || allText.contains('COMANDA') || allText.contains('CMD') || allText.contains('CO-') || allText.contains('[VIP-MC]');
}

String _limparNomeCliente(String nome, String? destaque) {
  String res = nome;
  if (destaque != null) {
    res = res.replaceAll(destaque, '');
  }
  // Limpar colchetes vazios, hifens e espaços extras
  res = res.replaceAll('[]', '')
           .replaceAll('[[', '[')
           .replaceAll(']]', ']')
           .replaceAll('[ ]', '')
           .replaceAll('- ', '')
           .trim();
  
  if (res.startsWith('•')) res = res.substring(1).trim();
  return res;
}

class ItemHistorico {
  final String id;
  final String numero;
  final DateTime data;
  final String? clienteNome;
  final double valorTotal;
  final TipoPagamento? tipoPagamento;
  final String tipo;
  final VendaBalcao? vendaBalcao;
  final Pedido? pedido;
  final TrocaDevolucao? trocaDevolucao;
  final FechamentoCaixa? fechamentoCaixa;
  final SangriaCaixa? sangria;
  final SuprimentoCaixa? suprimento;
  final bool isCancelada;
  final bool isSangria;
  final bool isSuprimento;

  ItemHistorico({
    required this.id,
    required this.numero,
    required this.data,
    this.clienteNome,
    required this.valorTotal,
    this.tipoPagamento,
    required this.tipo,
    this.vendaBalcao,
    this.pedido,
    this.trocaDevolucao,
    this.fechamentoCaixa,
    this.sangria,
    this.suprimento,
    this.isCancelada = false,
    this.isSangria = false,
    this.isSuprimento = false,
  });

  factory ItemHistorico.fromVendaBalcao(VendaBalcao v) => ItemHistorico(id: v.id, numero: v.numero, data: v.dataVenda, clienteNome: v.clienteNome, valorTotal: v.valorTotal, tipoPagamento: v.tipoPagamento, tipo: 'Venda Direta', vendaBalcao: v, isCancelada: v.isCancelada);
  factory ItemHistorico.fromPedido(Pedido p) => ItemHistorico(id: p.id, numero: p.numero, data: p.dataPedido, clienteNome: p.clienteNome, valorTotal: p.totalGeral, tipoPagamento: p.pagamentos.isNotEmpty ? p.pagamentos.first.tipo : null, tipo: 'Pedido', pedido: p, isCancelada: p.status.toLowerCase() == 'cancelado');
  factory ItemHistorico.fromTrocaDevolucao(TrocaDevolucao t) => ItemHistorico(id: t.id, numero: 'TD-${t.numeroPedido}', data: t.dataOperacao, clienteNome: t.clienteNome, valorTotal: t.diferenca, tipo: t.tipo == TipoOperacao.troca ? 'Troca' : 'Devolução', trocaDevolucao: t, isCancelada: t.status.toLowerCase() == 'cancelado');
  factory ItemHistorico.fromFechamentoCaixa(FechamentoCaixa f) => ItemHistorico(id: f.id, numero: 'FECH-CAIXA', data: f.dataFechamento, valorTotal: f.valorReal, tipo: 'Fechamento de Caixa', fechamentoCaixa: f);
  factory ItemHistorico.fromSangria(SangriaCaixa s) => ItemHistorico(id: s.id, numero: 'SANGRIA', data: s.data, valorTotal: s.valor, tipo: 'Sangria', sangria: s, isSangria: true);
  factory ItemHistorico.fromSuprimento(SuprimentoCaixa s) => ItemHistorico(id: s.id, numero: 'SUPRIMENTO', data: s.data, valorTotal: s.valor, tipo: 'Suprimento', suprimento: s, isSuprimento: true);
}

class HistoricoVendasPage extends StatefulWidget {
  const HistoricoVendasPage({super.key});
  @override
  State<HistoricoVendasPage> createState() => _HistoricoVendasPageState();
}

class _HistoricoVendasPageState extends State<HistoricoVendasPage> {
  final TextEditingController _buscaController = TextEditingController();
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _formatoData = DateFormat('dd/MM HH:mm');
  DateTime _dataInicio = DateTime.now().copyWith(hour: 0, minute: 0);
  DateTime _dataFim = DateTime.now().copyWith(hour: 23, minute: 59);
  String _termoBusca = '';
  String _filtroProdutoBusca = '';
  int _limiteLocal = 50;

  @override
  void dispose() { _buscaController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final Map<String, ItemHistorico> mapItens = {};

    // 1. Vendas Balcão (Prioridade para exibição correta de valores do PDV)
    for (var v in dataService.vendasBalcao.where((v) => v.dataVenda.isAfter(_dataInicio) && v.dataVenda.isBefore(_dataFim))) {
      mapItens[v.id] = ItemHistorico.fromVendaBalcao(v);
    }

    // 2. Pedidos (Adicionar apenas se o ID ainda não existir no mapa)
    for (var p in dataService.pedidos.where((p) => p.dataPedido.isAfter(_dataInicio) && p.dataPedido.isBefore(_dataFim))) {
      if (!mapItens.containsKey(p.id)) {
        mapItens[p.id] = ItemHistorico.fromPedido(p);
      }
    }

    // 3. Demais itens operacionais (Caixa, Sangrias, Suprimentos)
    for (var f in dataService.fechamentosCaixa.where((f) => f.dataFechamento.isAfter(_dataInicio) && f.dataFechamento.isBefore(_dataFim))) {
      mapItens['FECH-${f.id}'] = ItemHistorico.fromFechamentoCaixa(f);
    }
    for (var s in dataService.sangrias.where((s) => s.data.isAfter(_dataInicio) && s.data.isBefore(_dataFim))) {
      mapItens['SANG-${s.id}'] = ItemHistorico.fromSangria(s);
    }
    for (var s in dataService.suprimentos.where((s) => s.data.isAfter(_dataInicio) && s.data.isBefore(_dataFim))) {
      mapItens['SUPR-${s.id}'] = ItemHistorico.fromSuprimento(s);
    }
    
    // 4. Trocas e Devoluções
    try {
      final trocasDevolucoes = dataService.getTrocasDevolucoesPorPeriodo(_dataInicio, _dataFim);
      for (var t in trocasDevolucoes) {
        mapItens['TD-${t.id}'] = ItemHistorico.fromTrocaDevolucao(t);
      }
    } catch (e) {
      final trocas = (dataService as dynamic).trocasDevolucoes as List<TrocaDevolucao>;
      for (var t in trocas.where((t) => t.dataOperacao.isAfter(_dataInicio) && t.dataOperacao.isBefore(_dataFim))) {
        mapItens['TD-${t.id}'] = ItemHistorico.fromTrocaDevolucao(t);
      }
    }

    List<ItemHistorico> itens = mapItens.values.toList();
    
    if (_termoBusca.isNotEmpty) {
      final t = _termoBusca.toLowerCase();
      itens = itens.where((i) {
         final matchesBase = i.numero.toLowerCase().contains(t) || (i.clienteNome ?? '').toLowerCase().contains(t) || i.tipo.toLowerCase().contains(t);
         bool matchesProd = false;
         if (i.vendaBalcao != null) matchesProd = i.vendaBalcao!.itens.any((iv) => iv.nome.toLowerCase().contains(t));
         else if (i.pedido != null) matchesProd = i.pedido!.produtos.any((ip) => ip.nome.toLowerCase().contains(t));
         else if (i.trocaDevolucao != null) matchesProd = i.trocaDevolucao!.itensDevolvidos.any((id) => id.produtoNome.toLowerCase().contains(t)) || (i.trocaDevolucao!.itensNovos?.any((inew) => inew.produtoNome.toLowerCase().contains(t)) ?? false);
         return matchesBase || matchesProd;
      }).toList();
    }
    
    itens.sort((a, b) => b.data.compareTo(a.data));
    
    // Calcular total líquido (apenas vendas e trocas/devoluções)
    final double totalVendas = itens.where((i) {
      if (i.isCancelada) return false;
      // Não incluir operações de caixa no total de "Vendas"
      if (i.fechamentoCaixa != null || i.isSangria || i.isSuprimento) return false;
      return true;
    }).fold(0.0, (sum, i) => sum + i.valorTotal);

    return Scaffold(
      backgroundColor: const Color(0xFF161621),
      appBar: AppBar(
        title: const Text('Historico de Vendas', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          const SyncStatusWidget(),
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: Colors.greenAccent),
            onPressed: () => _mostrarResumoCaixas(context, itens, dataService),
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2, color: Colors.blueAccent),
            onPressed: () => _mostrarVendasPorProduto(context, dataService, itens),
          ),
        ],
      ),
      body: Column(children: [
        _buildFiltros(),
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
             _buildStatCard('TOTAL LÍQUIDO', totalVendas, Colors.greenAccent),
             const SizedBox(width: 8),
             _buildStatCard('VENDAS', itens.length.toDouble(), Colors.blueAccent, isMoeda: false),
          ]),
        ),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: itens.length > _limiteLocal ? _limiteLocal + 1 : itens.length,
          itemBuilder: (context, index) {
            if (index == _limiteLocal) return Center(child: TextButton(onPressed: () => setState(() => _limiteLocal += 50), child: const Text('Carregar mais...')));
            return _buildCardItem(itens[index]);
          },
        )),
      ]),
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(child: _buildDatePicker(_dataInicio, 'Inicio', true)),
          const SizedBox(width: 8),
          Expanded(child: _buildDatePicker(_dataFim, 'Fim', false)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _buscaController,
          onChanged: (v) => setState(() => _termoBusca = v),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar...',
            prefixIcon: const Icon(Icons.search, color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF2D2D44),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.zero
          ),
        ),
      ]),
    );
  }

  Widget _buildDatePicker(DateTime date, String label, bool isInicio) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (d != null) setState(() => isInicio ? _dataInicio = d.copyWith(hour: 0, minute: 0) : _dataFim = d.copyWith(hour: 23, minute: 59));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF2D2D44), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildStatCard(String label, double val, Color col, {bool isMoeda = true}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: col.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
        Text(isMoeda ? _formatoMoeda.format(val) : val.toInt().toString(), style: TextStyle(color: col, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    ));
  }

  Widget _buildCardItem(ItemHistorico item) {
    final bool isVip = _identificarMesaComanda(item.numero, item.clienteNome, item.pedido?.status, item.vendaBalcao?.observacoes ?? item.pedido?.observacoes, item.vendaBalcao?.origem ?? item.pedido?.origem);
    
    // Tentar extrair o número da comanda/mesa para destaque
    String? mcDestaque;
    bool isRealComanda = false;
    
    if (isVip) {
      final t = (item.clienteNome ?? '').toUpperCase();
      final n = item.numero.toUpperCase();
      final obs = (item.vendaBalcao?.observacoes ?? item.pedido?.observacoes ?? '').toUpperCase();
      final ori = (item.vendaBalcao?.origem ?? item.pedido?.origem ?? '').toUpperCase();
      final fullData = '$t $n $obs $ori';
      
      // Prioridade 1: Buscar padrão MESA XX ou CMD XX nas observações ou cliente
      final match = RegExp(r'(MESA \d+|CMD-\d+|COMANDA \d+)').firstMatch(fullData);
      if (match != null) {
        mcDestaque = match.group(0);
      } else if (t.contains('CMD-') || t.contains('COMANDA')) {
        mcDestaque = t.split(' • ').first;
      } else if (n.contains('CMD-') || n.contains('MESA')) {
        mcDestaque = item.numero;
      }
    }
      
    // Diferenciar Ícone e Cor: Comanda vs Mesa vs Venda Direta
    if (isVip) {
      isRealComanda = (mcDestaque ?? '').contains('CMD') || (mcDestaque ?? '').contains('COMANDA');
    }

    IconData icon = item.isCancelada 
        ? Icons.cancel_outlined 
        : (isVip 
            ? (isRealComanda ? Icons.receipt_long_rounded : Icons.table_restaurant_rounded) 
            : Icons.shopping_bag_rounded);
            
    Color color = item.isCancelada 
        ? Colors.redAccent 
        : (isVip 
            ? (isRealComanda ? Colors.purpleAccent : Colors.orangeAccent) 
            : Colors.blueAccent);
    
    if (item.isSangria) { icon = Icons.money_off_rounded; color = Colors.orangeAccent; }
    else if (item.isSuprimento) { icon = Icons.add_circle_outline_rounded; color = Colors.cyanAccent; }
    else if (item.fechamentoCaixa != null) { icon = Icons.lock_clock_rounded; color = Colors.deepPurpleAccent; }
    else if (item.trocaDevolucao != null) { 
      icon = item.trocaDevolucao!.tipo == TipoOperacao.troca ? Icons.swap_horizontal_circle_outlined : Icons.history_rounded;
      color = Colors.amber;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E), 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarDetalhesVenda(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            item.numero,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          if (mcDestaque != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Text(
                                mcDestaque,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            child: Text(
                              item.tipo.toUpperCase(),
                              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatoData.format(item.data)}${item.clienteNome != null ? ' • ${_limparNomeCliente(item.clienteNome!, mcDestaque)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatoMoeda.format(item.valorTotal),
                      style: TextStyle(
                        color: item.isCancelada ? Colors.white24 : (item.isSangria ? Colors.redAccent : Colors.greenAccent),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (item.isCancelada)
                      const Text(
                        'CANCELADO',
                        style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhesVenda(ItemHistorico item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Detalhes ${item.numero}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(item.tipo, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(color: Colors.white10),
          Expanded(child: ListView(children: [
            if (item.vendaBalcao != null) ...item.vendaBalcao!.itens.map((iv) => ListTile(
              title: Text(iv.nome, style: const TextStyle(color: Colors.white)), 
              subtitle: iv.fornecedorNome != null ? Text('Fornecedor: ${iv.fornecedorNome}', style: const TextStyle(color: Colors.white38, fontSize: 10)) : null,
              trailing: Text('${iv.quantidade}x ${_formatoMoeda.format(iv.precoUnitario)}'),
            )),
            if (item.pedido != null) ...item.pedido!.produtos.map((pp) => ListTile(title: Text(pp.nome, style: const TextStyle(color: Colors.white)), trailing: Text('${pp.quantidade}x ${_formatoMoeda.format(pp.preco)}'))),
            if (item.trocaDevolucao != null) ...[
               const ListTile(title: Text('ITENS DEVOLVIDOS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
               ...item.trocaDevolucao!.itensDevolvidos.map((id) => ListTile(title: Text(id.produtoNome, style: const TextStyle(color: Colors.white)), trailing: Text('${id.quantidade}x ${_formatoMoeda.format(id.precoUnitario)}'))),
               if (item.trocaDevolucao!.itensNovos != null && item.trocaDevolucao!.itensNovos!.isNotEmpty) ...[
                 const ListTile(title: Text('NOVOS ITENS', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                 ...item.trocaDevolucao!.itensNovos!.map((inew) => ListTile(title: Text(inew.produtoNome, style: const TextStyle(color: Colors.white)), trailing: Text('${inew.quantidade}x ${_formatoMoeda.format(inew.precoUnitario)}'))),
               ]
            ],
            if (item.fechamentoCaixa != null) ...[
              ListTile(title: const Text('Valor Esperado', style: TextStyle(color: Colors.white70)), trailing: Text(_formatoMoeda.format(item.fechamentoCaixa!.valorEsperado))),
              ListTile(title: const Text('Valor Real', style: TextStyle(color: Colors.white70)), trailing: Text(_formatoMoeda.format(item.fechamentoCaixa!.valorReal), style: const TextStyle(color: Colors.greenAccent))),
              ListTile(title: const Text('Diferença', style: TextStyle(color: Colors.white70)), trailing: Text(_formatoMoeda.format(item.fechamentoCaixa!.diferenca), style: TextStyle(color: item.fechamentoCaixa!.diferenca < 0 ? Colors.redAccent : Colors.greenAccent))),
            ],
            if (item.sangria != null || item.suprimento != null) ...[
              ListTile(title: const Text('Motivo', style: TextStyle(color: Colors.white70)), subtitle: Text(item.sangria?.motivo ?? item.suprimento?.motivo ?? '', style: const TextStyle(color: Colors.white))),
              if (item.sangria?.observacao != null || item.suprimento?.observacao != null)
                ListTile(title: const Text('Observação', style: TextStyle(color: Colors.white70)), subtitle: Text(item.sangria?.observacao ?? item.suprimento?.observacao ?? '', style: const TextStyle(color: Colors.white))),
            ],
            if (item.vendaBalcao?.observacoes != null) ListTile(title: const Text('Observações', style: TextStyle(color: Colors.white70)), subtitle: Text(item.vendaBalcao!.observacoes!, style: const TextStyle(color: Colors.white))),
            if (item.pedido?.observacoes != null) ListTile(title: const Text('Observações', style: TextStyle(color: Colors.white70)), subtitle: Text(item.pedido!.observacoes!, style: const TextStyle(color: Colors.white))),
          ])),
          const Divider(color: Colors.white10),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'VALOR TOTAL:',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatoMoeda.format(item.valorTotal),
                  style: TextStyle(
                    color: item.isCancelada ? Colors.white24 : (item.isSangria ? Colors.redAccent : Colors.greenAccent),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Botão de Cancelamento (Apenas se não estiver cancelado e for venda/pedido)
          if (!item.isCancelada && (item.vendaBalcao != null || item.pedido != null) && !item.isSangria && !item.isSuprimento && item.fechamentoCaixa == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmarCancelamento(item),
                icon: const Icon(Icons.cancel, color: Colors.white),
                label: const Text('CANCELAR ESTA VENDA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  void _confirmarCancelamento(ItemHistorico item) {
    final dataService = Provider.of<DataService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Confirmar Cancelamento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja realmente cancelar ${item.tipo} ${item.numero}?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta ação irá reverter os valores no sistema e no caixa. Esta operação não pode ser desfeita.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('BOA, MANTER', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Fecha o dialog
              Navigator.pop(context); // Fecha o modal de detalhes
              
              try {
                if (item.vendaBalcao != null) {
                  await dataService.cancelarVendaBalcao(item.id);
                } else if (item.pedido != null) {
                  await dataService.cancelarPedido(item.id);
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${item.tipo} cancelado(a) com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao cancelar: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('SIM, CANCELAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _mostrarResumoCaixas(BuildContext context, List<ItemHistorico> itens, DataService dataService) {
    final todasSangrias = dataService.getSangriasCaixaAtual();
    final pagamentos = todasSangrias.where((s) => s.motivo.startsWith('[PAGAMENTO]')).toList();
    final sangriasGeral = todasSangrias.where((s) => !s.motivo.startsWith('[PAGAMENTO]')).toList();
    
    final suprimentos = dataService.getSuprimentosCaixaAtual();
    final vendasValidas = itens.where((i) => !i.isCancelada).toList();
    
    final totalPagamentos = pagamentos.fold(0.0, (sum, s) => sum + s.valor);
    final totalS = sangriasGeral.fold(0.0, (sum, s) => sum + s.valor);
    final totalSup = suprimentos.fold(0.0, (sum, s) => sum + s.valor);
    final abertura = dataService.aberturaCaixaAtual?.valorInicial ?? 0.0;
    final totalVendas = vendasValidas.fold(0.0, (sum, i) => sum + i.valorTotal);
    
    final Map<TipoPagamento, double> totaisPorTipo = {};
    for (var v in vendasValidas) {
      if (v.tipoPagamento != null) {
        totaisPorTipo[v.tipoPagamento!] = (totaisPorTipo[v.tipoPagamento!] ?? 0.0) + v.valorTotal;
      }
    }

    showModalBottomSheet(
      context: context, 
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Resumo de Caixa Inteligente', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: ListView(
              children: [
                _tileResumo('Abertura de Caixa', abertura, Colors.blueAccent),
                _tileResumo('Entradas (Suprimentos)', totalSup, Colors.cyanAccent),
                
                if (totalPagamentos > 0)
                  InkWell(
                    onTap: () => _mostrarDetalhesSaidas(context, 'Pagamentos Efetuados', pagamentos),
                    child: _tileResumo('Pagamentos (Saídas)', -totalPagamentos, Colors.purpleAccent, showChevron: true),
                  ),

                if (totalS > 0)
                  InkWell(
                    onTap: () => _mostrarDetalhesSaidas(context, 'Sangrias Realizadas', sangriasGeral),
                    child: _tileResumo('Sangrias (Retiradas)', -totalS, Colors.orangeAccent, showChevron: true),
                  ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('VENDAS POR FORMA DE PAGAMENTO', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                ...totaisPorTipo.entries.map((e) => InkWell(
                  onTap: () => _mostrarVendasDoTipo(context, e.key, vendasValidas),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(_getIconePagamento(e.key), color: Colors.white70, size: 16),
                            const SizedBox(width: 8),
                            Text(e.key.toString().split('.').last.toUpperCase(), style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                        Row(
                          children: [
                            Text(_formatoMoeda.format(e.value), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
                const Divider(color: Colors.white10, height: 32),
                _tileResumo('TOTAL ESPERADO EM CAIXA', abertura + totalVendas + totalSup - totalPagamentos - totalS, Colors.white, isTotal: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (dataService.caixaAberto)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmarFechamentoInteligente(context, dataService, abertura, totaisPorTipo, totalSup, totalS);
                },
                icon: const Icon(Icons.lock_outline, color: Colors.white),
                label: const Text('REALIZAR FECHAMENTO DETALHADO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent.withOpacity(0.2))),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 12),
                  Text('CAIXA FECHADO', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  IconData _getIconePagamento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro: return Icons.payments_outlined;
      case TipoPagamento.pix: return Icons.qr_code_2_rounded;
      case TipoPagamento.cartaoCredito: return Icons.credit_card_rounded;
      case TipoPagamento.cartaoDebito: return Icons.credit_score_rounded;
      default: return Icons.account_balance_wallet_outlined;
    }
  }

  void _mostrarVendasDoTipo(BuildContext context, TipoPagamento tipo, List<ItemHistorico> vendas) {
    final filtradas = vendas.where((v) => v.tipoPagamento == tipo).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Vendas em ${tipo.toString().split('.').last.toUpperCase()}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: filtradas.length,
                itemBuilder: (context, index) {
                  final v = filtradas[index];
                  return ListTile(
                    title: Text(v.numero, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(DateFormat('HH:mm').format(v.data), style: const TextStyle(color: Colors.white38)),
                    trailing: Text(_formatoMoeda.format(v.valorTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalhesSaidas(BuildContext context, String titulo, List<SangriaCaixa> lista) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: lista.length,
                itemBuilder: (context, index) {
                  final s = lista[index];
                  String motivo = s.motivo.replaceAll('[PAGAMENTO] ', '');
                  return ListTile(
                    title: Text(motivo, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(DateFormat('HH:mm').format(s.data), style: const TextStyle(color: Colors.white38)),
                    trailing: Text(_formatoMoeda.format(s.valor), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarFechamentoInteligente(BuildContext context, DataService ds, double abertura, Map<TipoPagamento, double> totaisEsperados, double suprimentos, double sangriasTotais) {
    final Map<TipoPagamento, TextEditingController> controllers = {};
    
    // Inicializar controllers com valor esperado (preenchimento automático para agilizar)
    for (var tipo in TipoPagamento.values) {
       double esperado = totaisEsperados[tipo] ?? 0.0;
       if (tipo == TipoPagamento.dinheiro) {
         esperado += abertura + suprimentos - sangriasTotais;
       }
       controllers[tipo] = TextEditingController(text: esperado > 0 ? esperado.toStringAsFixed(2).replaceAll('.', ',') : '0,00');
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double somaReal = 0;
          double somaEsperada = 0;
          
          controllers.forEach((tipo, ctrl) {
            somaReal += double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
            double esperado = totaisEsperados[tipo] ?? 0;
            if (tipo == TipoPagamento.dinheiro) esperado += abertura + suprimentos - sangriasTotais;
            somaEsperada += esperado;
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Conferência de Valores', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...TipoPagamento.values.map((tipo) {
                      double esperado = totaisEsperados[tipo] ?? 0;
                      if (tipo == TipoPagamento.dinheiro) esperado += abertura + suprimentos - sangriasTotais;
                      if (esperado <= 0 && (double.tryParse(controllers[tipo]!.text) ?? 0) == 0) return const SizedBox.shrink();
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(tipo.toString().split('.').last.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                Text('Esperado: ${_formatoMoeda.format(esperado)}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: controllers[tipo],
                              onChanged: (_) => setDialogState(() {}),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixText: r'R$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(color: Colors.white10),
                    _tileResumoDialog('TOTAL ESPERADO', somaEsperada, Colors.white38),
                    _tileResumoDialog('TOTAL INFORMADO', somaReal, Colors.white),
                    _tileResumoDialog('DIFERENÇA GERAL', somaReal - somaEsperada, (somaReal - somaEsperada) >= 0 ? Colors.greenAccent : Colors.redAccent, isTotal: true),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('VOLTAR', style: TextStyle(color: Colors.white38))),
              ElevatedButton(
                onPressed: () async {
                  String obsDetalhada = 'Fechamento Inteligente:\n';
                  controllers.forEach((tipo, ctrl) {
                     double real = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
                     double esp = totaisEsperados[tipo] ?? 0;
                     if (tipo == TipoPagamento.dinheiro) esp += abertura + suprimentos - sangriasTotais;
                     if (esp > 0 || real > 0) {
                        obsDetalhada += '${tipo.toString().split('.').last.toUpperCase()}: Real ${_formatoMoeda.format(real)} (Exp ${_formatoMoeda.format(esp)})\n';
                     }
                  });

                  await ds.registrarFechamentoCaixa(
                    valorEsperado: somaEsperada,
                    valorReal: somaReal,
                    diferenca: somaReal - somaEsperada,
                    observacao: obsDetalhada,
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caixa fechado com sucesso!'), backgroundColor: Colors.green));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                child: const Text('CONFIRMAR E FECHAR', style: TextStyle(color: Color(0xFF1E1E2E), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _tileResumoDialog(String L, double v, Color c, {bool isTotal = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(L, style: TextStyle(color: Colors.white54, fontSize: isTotal ? 14 : 12, fontWeight: isTotal ? FontWeight.bold : null)),
      Text(_formatoMoeda.format(v), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: isTotal ? 16 : 13)),
    ]),
  );

  Widget _tileResumo(String L, double v, Color c, {bool isTotal = false, bool showChevron = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(
        children: [
          Text(L, style: TextStyle(color: Colors.white70, fontWeight: isTotal ? FontWeight.bold : null)),
          if (showChevron) const Icon(Icons.chevron_right, color: Colors.white24, size: 14),
        ],
      ),
      Text(_formatoMoeda.format(v), style: TextStyle(color: c, fontWeight: FontWeight.bold)),
    ]),
  );



  void _mostrarVendasPorProduto(BuildContext context, DataService dataService, List<ItemHistorico> itens) {
    if (itens.isEmpty) return;
    
    final Map<String, _ProdutoVendido> produtosMap = {};
    for (var i in itens) {
      if (i.isCancelada || i.isSangria || i.isSuprimento || i.fechamentoCaixa != null) continue;
      
      final vendidas = <_VendaProduto>[];
      if (i.vendaBalcao != null) {
        for (var iv in i.vendaBalcao!.itens) {
          final id = iv.id ?? iv.nome;
          produtosMap.putIfAbsent(id, () => _ProdutoVendido(nome: iv.nome, produtoId: iv.id));
          produtosMap[id]!.quantidadeTotal += iv.quantidade.toInt();
          produtosMap[id]!.valorTotal += (iv.precoUnitario * iv.quantidade);
          
          final prod = dataService.produtos.where((p) => p.id == iv.id || p.nome == iv.nome).firstOrNull;
          if (prod != null && prod.precoCusto != null) {
            produtosMap[id]!.custoTotal = (produtosMap[id]!.custoTotal ?? 0.0) + (prod.precoCusto! * iv.quantidade);
          }
          produtosMap[id]!.vendas.add(_VendaProduto(numeroVenda: i.numero, data: i.data, quantidade: iv.quantidade.toInt(), precoUnitario: iv.precoUnitario, valorTotal: iv.precoUnitario * iv.quantidade, clienteNome: i.clienteNome));
        }
      } else if (i.pedido != null) {
        for (var ip in i.pedido!.produtos) {
          final id = ip.nome;
          produtosMap.putIfAbsent(id, () => _ProdutoVendido(nome: ip.nome));
          produtosMap[id]!.quantidadeTotal += ip.quantidade.toInt();
          produtosMap[id]!.valorTotal += (ip.preco * ip.quantidade);

          final prod = dataService.produtos.where((p) => p.nome == ip.nome).firstOrNull;
          if (prod != null && prod.precoCusto != null) {
            produtosMap[id]!.custoTotal = (produtosMap[id]!.custoTotal ?? 0.0) + (prod.precoCusto! * ip.quantidade);
          }
          produtosMap[id]!.vendas.add(_VendaProduto(numeroVenda: i.numero, data: i.data, quantidade: ip.quantidade.toInt(), precoUnitario: ip.preco, valorTotal: ip.preco * ip.quantidade, clienteNome: i.clienteNome));
        }
      }
    }
    
    final listaBase = produtosMap.values.toList();
    
    // Calcular Curva ABC baseada em faturamento
    final double totalVendasGeral = listaBase.fold(0.0, (s, p) => s + p.valorTotal);
    final listaABC = List<_ProdutoVendido>.from(listaBase)..sort((a, b) => b.valorTotal.compareTo(a.valorTotal));
    
    double acumulado = 0;
    for (var p in listaABC) {
      if (totalVendasGeral > 0) {
        acumulado += p.valorTotal;
        double percentual = (acumulado / totalVendasGeral) * 100;
        if (percentual <= 80.1) p.abc = 'A';
        else if (percentual <= 95.1) p.abc = 'B';
        else p.abc = 'C';
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => DefaultTabController(
        length: 2,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final filtradosLucro = listaBase.where((p) => p.nome.toLowerCase().contains(_filtroProdutoBusca.toLowerCase())).toList();
            final filtradosABC = listaABC.where((p) => p.nome.toLowerCase().contains(_filtroProdutoBusca.toLowerCase())).toList();
            
            final int totalUnidades = listaBase.fold(0, (sum, p) => sum + p.quantidadeTotal);
            final double totalLucro = listaBase.where((p) => p.temCusto).fold(0.0, (sum, p) => sum + p.lucroTotal);
            
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Análise de Produtos', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('$totalUnidades unidades vendidas no período', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  const TabBar(
                    indicatorColor: Colors.orangeAccent,
                    labelColor: Colors.orangeAccent,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'LUCRATIVIDADE', icon: Icon(Icons.monetization_on_outlined)),
                      Tab(text: 'CURVA ABC / RANKING', icon: Icon(Icons.analytics_outlined)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (v) => setModalState(() => _filtroProdutoBusca = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Filtrar produto...',
                        prefixIcon: const Icon(Icons.search, color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF2D2D44),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Aba Lucratividade
                        _buildListaLucratividade(filtradosLucro, totalLucro),
                        // Aba Curva ABC
                        _buildListaABC(filtradosABC, totalVendasGeral),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildListaLucratividade(List<_ProdutoVendido> produtos, double totalLucro) {
    produtos.sort((a, b) => b.lucroTotal.compareTo(a.lucroTotal));
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Text('LUCRO TOTAL: ${_formatoMoeda.format(totalLucro)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('FATURAMENTO TOTAL: ${_formatoMoeda.format(produtos.fold(0.0, (s, p) => s + p.valorTotal))}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              final p = produtos[index];
              return _buildCardProdutoLucro(p);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListaABC(List<_ProdutoVendido> produtos, double totalGeral) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Text('FATURAMENTO TOTAL: ${_formatoMoeda.format(totalGeral)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Ranking baseado no volume de vendas em reais', style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
        final p = produtos[index];
        final perc = totalGeral > 0 ? (p.valorTotal / totalGeral) * 100 : 0.0;
        
        Color abcColor = Colors.greenAccent;
        String abcDesc = 'Essencial (80%)';
        if (p.abc == 'B') { abcColor = Colors.orangeAccent; abcDesc = 'Intermediário (15%)'; }
        else if (p.abc == 'C') { abcColor = Colors.redAccent; abcDesc = 'Baixo Impacto (5%)'; }

        return Card(
          color: const Color(0xFF2D2D44).withOpacity(0.5),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () => _mostrarVendasDatalhadasDoProduto(context, p),
            leading: CircleAvatar(
              backgroundColor: abcColor.withOpacity(0.2),
              child: Text(p.abc, style: TextStyle(color: abcColor, fontWeight: FontWeight.w900)),
            ),
            title: Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.quantidadeTotal} unidades • ${perc.toStringAsFixed(1)}% do faturamento', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Text(abcDesc, style: TextStyle(color: abcColor.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: Text(_formatoMoeda.format(p.valorTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          );
        },
      ),
    ),
  ],
);
}

  Widget _buildCardProdutoLucro(_ProdutoVendido p) {
    return Card(
      color: const Color(0xFF2D2D44).withOpacity(0.5),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _mostrarVendasDatalhadasDoProduto(context, p),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                  Text(_formatoMoeda.format(p.valorTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.quantidadeTotal} unidades vendidas', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      if (p.temCusto)
                        Text('Custo Total: ${_formatoMoeda.format(p.custoTotal)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (p.temCusto) ...[
                        Text('Lucro: ${_formatoMoeda.format(p.lucroTotal)}', style: TextStyle(color: p.lucroTotal >= 0 ? Colors.orangeAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Margem: ${p.margemPercentual.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            const Text(' • ', style: TextStyle(color: Colors.white24)),
                            Text('Markup: ${p.markupPercentual.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ] else
                        const Text('Custo não informado', style: TextStyle(color: Colors.white24, fontSize: 11, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarVendasDatalhadasDoProduto(BuildContext context, _ProdutoVendido p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vendas de ${p.nome}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${p.vendas.length} operações realizadas', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: p.vendas.length,
                itemBuilder: (context, index) {
                  final v = p.vendas[index];
                  return Card(
                    color: const Color(0xFF2D2D44).withOpacity(0.5),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(v.numeroVenda, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          Text(DateFormat('dd/MM HH:mm').format(v.data), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(v.clienteNome ?? 'Venda Direta', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text('${v.quantidade}x ${_formatoMoeda.format(v.precoUnitario)}'),
                        ],
                      ),
                      trailing: Text(_formatoMoeda.format(v.valorTotal), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
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

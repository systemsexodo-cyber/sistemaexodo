import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/estoque_historico.dart';
import '../models/produto.dart';
import '../theme.dart';
import '../custom_app_bar.dart';

class EstoqueRelatorioGeralPage extends StatefulWidget {
  const EstoqueRelatorioGeralPage({super.key});

  @override
  State<EstoqueRelatorioGeralPage> createState() => _EstoqueRelatorioGeralPageState();
}

class _EstoqueRelatorioGeralPageState extends State<EstoqueRelatorioGeralPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  String? _tipoFiltro; // null = todos, 'entrada', 'saida', 'ajuste'
  String? _fornecedorFiltro;
  String? _desempenhoFiltro; // null = todos, 'sem_giro', 'giro_normal', 'giro_rapido'
  String _buscaProduto = '';
  final _buscaController = TextEditingController();
  bool _agruparPorFornecedor = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Iniciar com o mês atual por padrão (para giro usamos histórico mais longo se possível)
    final agora = DateTime.now();
    _dataInicial = DateTime(agora.year, agora.month, 1);
    _dataFinal = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final historico = service.estoqueHistorico;
    final produtos = service.produtos;

    // Extrair fornecedores únicos para o filtro
    final fornecedores = historico
        .map((h) => h.fornecedorNome)
        .where((f) => f != null && f.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    fornecedores.sort();

    // Aplicar filtros no HISTÓRICO (Aba 1)
    List<EstoqueHistorico> filtrado = historico.where((h) {
      if (_dataInicial != null && h.data.isBefore(_dataInicial!)) return false;
      if (_dataFinal != null && h.data.isAfter(_dataFinal!)) return false;
      if (_tipoFiltro != null && h.tipo != _tipoFiltro) return false;
      if (_fornecedorFiltro != null && h.fornecedorNome != _fornecedorFiltro) return false;
      if (_buscaProduto.isNotEmpty) {
        final prod = produtos.firstWhere((p) => p.id == h.produtoId, orElse: () => _produtoExcluido());
        if (!prod.nome.toLowerCase().contains(_buscaProduto.toLowerCase()) &&
            !(prod.codigo?.toLowerCase().contains(_buscaProduto.toLowerCase()) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtrado.sort((a, b) => b.data.compareTo(a.data));

    final totalEntradas = filtrado.where((h) => h.tipo == 'entrada').fold<int>(0, (p, e) => p + e.quantidade);
    final totalSaidas = filtrado.where((h) => h.tipo == 'saida').fold<int>(0, (p, e) => p + e.quantidade);

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'ESTOQUE NÍVEL PROFISSIONAL',
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.blueAccent,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'HISTÓRICO', icon: Icon(Icons.history_rounded, size: 20)),
              Tab(text: 'ANÁLISE DE GIRO', icon: Icon(Icons.analytics_rounded, size: 20)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // ABA 1: HISTÓRICO
            Column(
              children: [
                _buildFiltros(fornecedores, true),
                _buildResumoMovimentacao(totalEntradas, totalSaidas),
                const SizedBox(height: 10),
                Expanded(
                  child: filtrado.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtrado.length,
                          itemBuilder: (context, index) => _buildItemRelatorio(filtrado[index], produtos),
                        ),
                ),
              ],
            ),
            // ABA 2: INVENTÁRIO INTELIGENTE
            _buildAbaInventario(produtos, historico),
          ],
        ),
      ),
    );
  }

  Produto _produtoExcluido() => Produto(id: '', nome: 'Produto Excluído', preco: 0, estoque: 0, unidade: 'un', grupo: 'Geral', createdAt: DateTime.now(), updatedAt: DateTime.now());

  Widget _buildAbaInventario(List<Produto> todosProdutos, List<EstoqueHistorico> historico) {
    // 1. Calcular giro e autonomia para TODOS antes de filtrar
    final List<Map<String, dynamic>> analiseCompleta = todosProdutos.map((p) {
      final saidasTotal = historico.where((h) => h.produtoId == p.id && h.tipo == 'saida').toList();
      saidasTotal.sort((a, b) => b.data.compareTo(a.data));
      
      DateTime? ultimaSaida = saidasTotal.isNotEmpty ? saidasTotal.first.data : null;
      int diasSemGiro = ultimaSaida != null ? DateTime.now().difference(ultimaSaida).inDays : 999;
      
      // Média de vendas diárias nos últimos 30 dias
      final trintaDiasAtras = DateTime.now().subtract(const Duration(days: 30));
      final saidasRecentes = saidasTotal.where((h) => h.data.isAfter(trintaDiasAtras)).toList();
      double totalVendidoRecente = saidasRecentes.fold(0.0, (sum, h) => sum + h.quantidade);
      double mediaVendaDiaria = totalVendidoRecente / 30;
      
      // Autonomia (Estoque / Média)
      int autonomiaDias = mediaVendaDiaria > 0 ? (p.estoque / mediaVendaDiaria).round() : (p.estoque > 0 ? 999 : 0);
      
      String statusGiro = 'sem_giro';
      if (diasSemGiro <= 7) statusGiro = 'giro_rapido';
      else if (diasSemGiro <= 30) statusGiro = 'giro_normal';

      return {
        'produto': p,
        'statusGiro': statusGiro,
        'diasSemGiro': diasSemGiro,
        'ultimaSaida': ultimaSaida,
        'autonomiaDias': autonomiaDias,
        'custoTotal': p.estoque * (p.precoCusto ?? 0),
      };
    }).toList();

    // 2. Aplicar FILTROS da UI
    final filtrados = analiseCompleta.where((map) {
      final p = map['produto'] as Produto;
      
      // Filtro de Busca
      if (_buscaProduto.isNotEmpty && 
          !p.nome.toLowerCase().contains(_buscaProduto.toLowerCase()) && 
          !(p.codigo?.toLowerCase().contains(_buscaProduto.toLowerCase()) ?? false)) {
        return false;
      }
      
      // Filtro de Desempenho
      if (_desempenhoFiltro != null && map['statusGiro'] != _desempenhoFiltro) {
        return false;
      }

      return true;
    }).toList();

    double custoTotalGeral = filtrados.fold(0.0, (sum, m) => sum + (m['custoTotal'] as double));

    return Column(
      children: [
        _buildFiltrosInventario(),
        _buildResumoInventario(filtrados.length, custoTotalGeral),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtrados.length,
            itemBuilder: (context, index) => _buildItemInventario(filtrados[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltrosInventario() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            onChanged: (v) => setState(() => _buscaProduto = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Filtrar por produto...',
              prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _desempenhoFiltro,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A2E),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                hint: const Text('Filtro de Desempenho (Giro)', style: TextStyle(color: Colors.white30, fontSize: 12)),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos os Produtos')),
                  DropdownMenuItem(value: 'giro_rapido', child: Text('🔥 Giro Rápido (Top Vendas)')),
                  DropdownMenuItem(value: 'giro_normal', child: Text('✅ Giro Normal')),
                  DropdownMenuItem(value: 'sem_giro', child: Text('⚠️ Sem Giro (Estoque Parado)')),
                ],
                onChanged: (v) => setState(() => _desempenhoFiltro = v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoInventario(int qtdItens, double valorTotal) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blueAccent.withOpacity(0.2), Colors.purpleAccent.withOpacity(0.1)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('INVESTIMENTO EM PRODUTOS (CUSTO)', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(valorTotal),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TOTAL ITENS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              Text(qtdItens.toString(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemInventario(Map<String, dynamic> analise) {
    final Produto p = analise['produto'];
    final int diasSemGiro = analise['diasSemGiro'];
    final DateTime? ultimaSaida = analise['ultimaSaida'];
    final int autonomiaDias = analise['autonomiaDias'];
    final double custoTotal = analise['custoTotal'];
    final String statusGiro = analise['statusGiro'];
    
    double custoItem = p.precoCusto ?? 0;
    bool riscoEstoqueParado = statusGiro == 'sem_giro' && p.estoque > 0;
    bool riscoRuptura = autonomiaDias < 7 && p.estoque > 0 && statusGiro != 'sem_giro';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: riscoRuptura ? Colors.redAccent.withOpacity(0.5) : 
                 (riscoEstoqueParado ? Colors.orangeAccent.withOpacity(0.5) : Colors.white.withOpacity(0.1)),
          width: riscoRuptura ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                    Text('Grupo: ${p.grupo}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p.estoque} ${p.unidade}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('Custo: ${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(custoItem)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AUTONOMIA DO ESTOQUE', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  _buildAutonomiaTexto(autonomiaDias, statusGiro),
                ],
              ),
              _buildTagStatusCompleto(diasSemGiro, ultimaSaida, statusGiro, riscoEstoqueParado, riscoRuptura),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('VALOR TOTAL (CUSTO):', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
              Text(NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(custoTotal),
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutonomiaTexto(int dias, String status) {
    if (status == 'sem_giro') return const Text('SEM GIRO (PREVISÃO INDISP.)', style: TextStyle(color: Colors.white30, fontSize: 13));
    if (dias > 365) return const Text('MAIS DE 1 ANO', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold));
    
    Color cor = dias < 7 ? Colors.redAccent : (dias < 15 ? Colors.orangeAccent : Colors.greenAccent);
    return Text('DURA APROX. $dias DIAS', style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.bold));
  }

  Widget _buildTagStatusCompleto(int dias, DateTime? ultima, String status, bool riscoParado, bool riscoRuptura) {
    if (riscoRuptura) return _tag('⚡ RUPTURA IMINENTE (RECOMPRAR JÁ)', Colors.redAccent);
    if (riscoParado) return _tag('⚠️ ESTOQUE PARADO ($dias d)', Colors.orangeAccent);
    if (status == 'giro_rapido') return _tag('🔥 GIRO RÁPIDO', Colors.greenAccent);
    return _tag('✅ GIRO NORMAL', Colors.blueAccent);
  }

  Widget _tag(String txt, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.2), // Fundo mais sólido
        borderRadius: BorderRadius.circular(6), 
        border: Border.all(color: cor.withOpacity(0.5))
      ),
      child: Text(txt, style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w900)), // w900 é o ultra-bold
    );
  }

  Widget _buildFiltros(List<String> fornecedores, bool mostrarDatas) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            onChanged: (v) => setState(() => _buscaProduto = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar produto...',
              prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          if (mostrarDatas) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildDateBtn()),
                const SizedBox(width: 8),
                Expanded(child: _buildTipoDropdown()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateBtn() {
    return InkWell(
      onTap: _selecionarPeriodo,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 16),
            const SizedBox(width: 8),
            Text(_dataInicial == null ? 'Período' : '${DateFormat('dd/MM').format(_dataInicial!)} - ${DateFormat('dd/MM').format(_dataFinal!)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _tipoFiltro,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A2E),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos')),
            DropdownMenuItem(value: 'entrada', child: Text('Entradas')),
            DropdownMenuItem(value: 'saida', child: Text('Saídas')),
          ],
          onChanged: (v) => setState(() => _tipoFiltro = v),
        ),
      ),
    );
  }

  Widget _buildResumoMovimentacao(int ent, int sai) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _cardRes('ENTRADAS', ent, Colors.greenAccent),
          const SizedBox(width: 12),
          _cardRes('SAÍDAS', sai, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _cardRes(String label, int val, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cor.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: cor.withOpacity(0.6), fontSize: 9)),
            Text(val.toString(), style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRelatorio(EstoqueHistorico h, List<Produto> produtos) {
    final p = produtos.firstWhere((prod) => prod.id == h.produtoId, orElse: () => _produtoExcluido());
    final isEntrada = h.tipo == 'entrada';
    final cor = isEntrada ? Colors.greenAccent : Colors.redAccent;
    return ListTile(
      leading: Icon(isEntrada ? Icons.add_circle_outline : Icons.remove_circle_outline, color: cor),
      title: Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(DateFormat('dd/MM/yy HH:mm').format(h.data), style: const TextStyle(color: Colors.white30, fontSize: 11)),
      trailing: Text('${isEntrada ? "+" : "-"}${h.quantidade}', style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() => const Center(child: Text('Nenhuma movimentação', style: TextStyle(color: Colors.white24)));
  Widget _buildToolbarMov() => const SizedBox(height: 10);

  Widget _buildListaAgrupada(List<EstoqueHistorico> f, List<Produto> p) {
    return const Center(child: Text('Recurso em atualização...', style: TextStyle(color: Colors.white24)));
  }

  Future<void> _selecionarPeriodo() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _dataInicial!, end: _dataFinal!),
    );
    if (picked != null) {
      setState(() {
        _dataInicial = picked.start;
        _dataFinal = picked.end.add(const Duration(hours: 23, minutes: 59));
      });
    }
  }
}

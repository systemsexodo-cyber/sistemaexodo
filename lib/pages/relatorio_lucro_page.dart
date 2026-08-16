import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/venda_balcao.dart';
import '../services/data_service.dart';
import '../services/lucro_calculator.dart';
import '../theme.dart';
import 'html_helper_web.dart' if (dart.library.io) '../services/local_storage_service_stub.dart';

/// Relatório de Lucro / DRE
///
/// Calcula receita, custo das mercadorias vendidas e lucro bruto a partir das
/// vendas de balcão (PDV, venda direta, mesas/comandas), usando o custo atual
/// cadastrado nos produtos (os itens de venda não persistem o custo histórico).
class RelatorioLucroPage extends StatefulWidget {
  const RelatorioLucroPage({super.key});

  @override
  State<RelatorioLucroPage> createState() => _RelatorioLucroPageState();
}

class _RelatorioLucroPageState extends State<RelatorioLucroPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _periodoSelecionado = 'mes'; // hoje | 7d | mes | personalizado
  DateTime? _dataInicialPersonalizada;
  DateTime? _dataFinalPersonalizada;

  // Cache de custo por produto (id -> custo unitário)
  final Map<String, double> _cacheCusto = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ===================================================================
  // PERÍODO
  // ===================================================================
  DateTime get _inicioPeriodo {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    switch (_periodoSelecionado) {
      case 'hoje':
        return hoje;
      case '7d':
        return hoje.subtract(const Duration(days: 6));
      case 'personalizado':
        return _dataInicialPersonalizada ?? hoje;
      default: // mes
        return DateTime(agora.year, agora.month, 1);
    }
  }

  DateTime get _fimPeriodo {
    final agora = DateTime.now();
    if (_periodoSelecionado == 'personalizado') {
      final fim = _dataFinalPersonalizada;
      if (fim != null) {
        return DateTime(fim.year, fim.month, fim.day, 23, 59, 59);
      }
    }
    return DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
  }

  String get _tituloPeriodo {
    switch (_periodoSelecionado) {
      case 'hoje':
        return 'Hoje';
      case '7d':
        return 'Últimos 7 dias';
      case 'personalizado':
        final ini = _dataInicialPersonalizada;
        final fim = _dataFinalPersonalizada;
        if (ini != null && fim != null) {
          return '${DateFormat('dd/MM').format(ini)} a ${DateFormat('dd/MM/yyyy').format(fim)}';
        }
        return 'Personalizado';
      default:
        return DateFormat('MMMM/yyyy').format(DateTime.now());
    }
  }

  // ===================================================================
  // CÁLCULOS
  // ===================================================================
  /// Vendas válidas do período (não canceladas). Resultado memoizado por build.
  List<VendaBalcao> _vendasDoPeriodo(DataService dataService) {
    if (_vendasFiltradas != null) return _vendasFiltradas!;
    // O LucroCalculator usa fim exclusivo (padrão do Dashboard); o +1s garante
    // que todas as vendas do último dia do período sejam incluídas.
    _vendasFiltradas = LucroCalculator.vendasDoPeriodo(
        dataService, _inicioPeriodo, _fimPeriodo.add(const Duration(seconds: 1)));
    return _vendasFiltradas!;
  }

  List<VendaBalcao>? _vendasFiltradas;

  // Totais gerais do período
  Map<String, double> _totais(DataService dataService) =>
      LucroCalculator.totais(dataService, _vendasDoPeriodo(dataService), _cacheCusto);

  // Ranking por produto
  List<Map<String, dynamic>> _porProduto(DataService dataService) =>
      LucroCalculator.porProduto(dataService, _vendasDoPeriodo(dataService), _cacheCusto);

  // Ranking por vendedor
  List<Map<String, dynamic>> _porVendedor(DataService dataService) =>
      LucroCalculator.porVendedor(dataService, _vendasDoPeriodo(dataService), _cacheCusto);

  // Ranking por grupo/categoria
  List<Map<String, dynamic>> _porCategoria(DataService dataService) =>
      LucroCalculator.porCategoria(dataService, _vendasDoPeriodo(dataService), _cacheCusto);

  // ===================================================================
  // EXPORTAÇÃO CSV
  // ===================================================================
  String _fixCsv(String? texto) {
    if (texto == null) return '';
    return texto
        .replaceAll('\n', ' ')
        .replaceAll(';', ',')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _exportarCsv(DataService dataService) {
    final buffer = StringBuffer();
    // Resumo
    final totais = _totais(dataService);
    buffer.writeln('RELATORIO DE LUCRO / DRE');
    buffer.writeln('Periodo;${_fixCsv(_tituloPeriodo)}');
    buffer.writeln('');
    buffer.writeln('Indicador;Valor');
    buffer.writeln('Receita Bruta;${totais['receita']!.toStringAsFixed(2).replaceAll('.', ',')}');
    buffer.writeln('Custo das Vendas (CMV);${totais['custo']!.toStringAsFixed(2).replaceAll('.', ',')}');
    buffer.writeln('Lucro Bruto;${totais['lucro']!.toStringAsFixed(2).replaceAll('.', ',')}');
    buffer.writeln('Margem Bruta (%);${totais['margem']!.toStringAsFixed(1).replaceAll('.', ',')}');
    buffer.writeln('Numero de Vendas;${(totais['qtdVendas'] as double).toInt()}');
    buffer.writeln('Ticket Medio;${totais['ticket']!.toStringAsFixed(2).replaceAll('.', ',')}');
    buffer.writeln('');
    buffer.writeln('');

    // Por produto
    buffer.writeln('LUCRO POR PRODUTO');
    buffer.writeln('Produto;Grupo;Quantidade;Receita;Custo;Lucro;Margem(%)');
    for (final p in _porProduto(dataService)) {
      buffer.writeln(
          '${_fixCsv(p['nome'])};${_fixCsv(p['grupo'])};${p['quantidade']};'
          '${(p['receita'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['custo'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['lucro'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['margem'] as double).toStringAsFixed(1).replaceAll('.', ',')}');
    }
    buffer.writeln('');

    // Por vendedor
    buffer.writeln('LUCRO POR VENDEDOR');
    buffer.writeln('Vendedor;Vendas;Receita;Custo;Lucro;Margem(%)');
    for (final p in _porVendedor(dataService)) {
      buffer.writeln(
          '${_fixCsv(p['nome'])};${(p['quantidade'] as double).toInt()};'
          '${(p['receita'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['custo'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['lucro'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['margem'] as double).toStringAsFixed(1).replaceAll('.', ',')}');
    }
    buffer.writeln('');

    // Por categoria
    buffer.writeln('LUCRO POR CATEGORIA');
    buffer.writeln('Categoria;Quantidade;Receita;Custo;Lucro;Margem(%)');
    for (final p in _porCategoria(dataService)) {
      buffer.writeln(
          '${_fixCsv(p['nome'])};${p['quantidade']};'
          '${(p['receita'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['custo'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['lucro'] as double).toStringAsFixed(2).replaceAll('.', ',')};'
          '${(p['margem'] as double).toStringAsFixed(1).replaceAll('.', ',')}');
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final nomeArquivo = 'relatorio_lucro_${DateTime.now().millisecondsSinceEpoch}.csv';
    downloadBytes(bytes, nomeArquivo, 'text/csv;charset=utf-8');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório CSV exportado com sucesso!')),
      );
    }
  }

  Future<void> _selecionarPeriodoPersonalizado() async {
    final agora = DateTime.now();
    final inicioPadrao = DateTime(agora.year, agora.month, 1);
    final inicio = await showDatePicker(
      context: context,
      initialDate: inicioPadrao,
      firstDate: DateTime(2020),
      lastDate: agora,
      helpText: 'Data inicial',
    );
    if (inicio == null || !mounted) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: agora,
      firstDate: inicio,
      lastDate: agora,
      helpText: 'Data final',
    );
    if (fim == null) return;
    setState(() {
      _periodoSelecionado = 'personalizado';
      _dataInicialPersonalizada = inicio;
      _dataFinalPersonalizada = fim;
    });
  }

  // ===================================================================
  // UI
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    _cacheCusto.clear();
    _vendasFiltradas = null;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: CustomAppBar(
          title: 'Relatório de Lucro / DRE',
          actions: [
            IconButton(
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _exportarCsv(dataService),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            isScrollable: true,
            tabs: const [
              Tab(text: 'RESUMO'),
              Tab(text: 'POR PRODUTO'),
              Tab(text: 'POR VENDEDOR'),
              Tab(text: 'POR CATEGORIA'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildFiltros(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildResumo(dataService),
                  _buildRanking(dataService, _porProduto(dataService)),
                  _buildRanking(dataService, _porVendedor(dataService)),
                  _buildRanking(dataService, _porCategoria(dataService)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    final chips = <Widget>[
      _chipPeriodo('hoje', 'Hoje'),
      _chipPeriodo('7d', '7 dias'),
      _chipPeriodo('mes', 'Mês'),
      ActionChip(
        label: const Text('Personalizado'),
        backgroundColor: _periodoSelecionado == 'personalizado'
            ? Colors.green.withValues(alpha: 0.9)
            : Colors.white12,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        onPressed: _selecionarPeriodoPersonalizado,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                _tituloPeriodo,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _chipPeriodo(String id, String rotulo) {
    return ChoiceChip(
      label: Text(rotulo),
      selected: _periodoSelecionado == id,
      selectedColor: Colors.green,
      backgroundColor: Colors.white12,
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      onSelected: (_) => setState(() => _periodoSelecionado = id),
    );
  }

  // ---------- ABA RESUMO / DRE ----------
  Widget _buildResumo(DataService dataService) {
    final totais = _totais(dataService);
    final receita = totais['receita']!;
    final custo = totais['custo']!;
    final lucro = totais['lucro']!;
    final margem = totais['margem']!;
    final qtdVendas = (totais['qtdVendas'] as double).toInt();
    final ticket = totais['ticket']!;
    final corLucro = lucro >= 0 ? Colors.greenAccent : Colors.redAccent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cards principais
        Row(
          children: [
            _cardResumo(
              titulo: 'Receita Bruta',
              valor: receita,
              cor: Colors.lightBlueAccent,
              icone: Icons.attach_money_rounded,
              flex: 1,
            ),
            const SizedBox(width: 12),
            _cardResumo(
              titulo: 'Custo (CMV)',
              valor: custo,
              cor: Colors.orangeAccent,
              icone: Icons.shopping_cart_rounded,
              flex: 1,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _cardResumo(
              titulo: 'Lucro Bruto',
              valor: lucro,
              cor: corLucro,
              icone: Icons.trending_up_rounded,
              flex: 1,
            ),
            const SizedBox(width: 12),
            _cardResumo(
              titulo: 'Margem',
              valor: margem,
              ehPercentual: true,
              cor: Colors.purpleAccent,
              icone: Icons.pie_chart_rounded,
              flex: 1,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // DRE simplificado
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_rounded, color: Colors.greenAccent),
                  SizedBox(width: 8),
                  Text(
                    'DEMONSTRATIVO DE RESULTADO (DRE)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _linhaDre('Receita Bruta', receita, cor: Colors.white),
              _linhaDre('(-) Custo das Vendas (CMV)', -custo, cor: Colors.orangeAccent),
              const Divider(color: Colors.white24, height: 20),
              _linhaDre('= LUCRO BRUTO', lucro, cor: corLucro, bold: true),
              _linhaDre('Margem Bruta', margem, cor: Colors.purpleAccent, ehPercentual: true),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Métricas secundárias
        Row(
          children: [
            _cardMetrica('Vendas no período', '$qtdVendas', Icons.receipt_long_rounded, Colors.tealAccent),
            const SizedBox(width: 12),
            _cardMetrica('Ticket médio', _fmt(ticket), Icons.local_atm_rounded, Colors.amberAccent),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O custo é calculado pelo preço de custo ATUAL cadastrado em cada produto '
                  '(produtos sem custo e serviços entram com custo zero). A receita usa o total '
                  'final da venda (já com descontos); os rankings usam o subtotal dos itens.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linhaDre(String rotulo, double valor,
      {Color cor = Colors.white, bool bold = false, bool ehPercentual = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(
                color: cor,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                fontSize: bold ? 15 : 13,
              ),
            ),
          ),
          Text(
            ehPercentual ? '${valor.toStringAsFixed(1)}%' : _fmt(valor),
            style: TextStyle(
              color: cor,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: bold ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardResumo({
    required String titulo,
    required double valor,
    required Color cor,
    required IconData icone,
    bool ehPercentual = false,
    required int flex,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cor.withValues(alpha: 0.25), cor.withValues(alpha: 0.08)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor, size: 22),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                ehPercentual ? '${valor.toStringAsFixed(1)}%' : _fmt(valor),
                style: TextStyle(
                  color: cor,
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMetrica(String titulo, String valor, IconData icone, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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

  // ---------- ABA RANKING ----------
  Widget _buildRanking(DataService dataService, List<Map<String, dynamic>> itens) {
    if (itens.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.query_stats_rounded, color: Colors.white38, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Sem dados no período selecionado',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: itens.length,
      itemBuilder: (context, index) {
        final item = itens[index];
        final lucro = item['lucro'] as double;
        final receita = item['receita'] as double;
        final margem = item['margem'] as double;
        final cor = lucro >= 0 ? Colors.greenAccent : Colors.redAccent;
        final temGrupo = item.containsKey('grupo');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index < 3
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.9)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['nome'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      temGrupo
                          ? '${item['grupo']}  •  ${item['quantidade']} un vendidas'
                          : '${(item['quantidade'] as double).toInt()} vendas',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(lucro),
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${margem.toStringAsFixed(0)}% margem',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(double valor) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return formato.format(valor);
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/caixa.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'home_page.dart';
import '../widgets/sync_status_widget.dart';
import '../services/caixa_pdf_service.dart';
import '../services/auth_service.dart';
import '../models/venda_balcao.dart';
import '../models/empresa.dart';
import 'package:printing/printing.dart';


/// Página de gerenciamento de caixa
class CaixaPage extends StatefulWidget {
  const CaixaPage({super.key});

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  final NumberFormat formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat formatoData = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat formatoHora = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Fluxo de Caixa'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: const [SyncStatusWidget()],
        ),
        body: Consumer<DataService>(
          builder: (context, dataService, child) {
            final caixaAberto = dataService.caixaAberto;
            final aberturaAtual = dataService.aberturaCaixaAtual;

            return CustomScrollView(
              slivers: [
                // 1. Card de Status do Caixa
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildStatusHeader(caixaAberto, aberturaAtual, dataService),
                  ),
                ),

                // 2. Seção de Resumo (Apenas se aberto)
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildResumoSession(dataService, aberturaAtual),
                    ),
                  ),

                // 3. Título do Fluxo de Caixa Atual
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Movimentações do Dia',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Sessão Atual',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 4. Lista do Fluxo de Caixa Atual
                if (caixaAberto && aberturaAtual != null)
                  _buildSliverFluxoLista(dataService, aberturaAtual),

                // 5. Histórico Separador
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                    child: Text(
                      'Histórico de Encerramentos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 6. Lista do Histórico
                _buildSliverHistorico(dataService),
                
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool aberto, AberturaCaixa? abertura, DataService ds) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: aberto
              ? [Colors.blueAccent.withOpacity(0.4), Colors.blue.withOpacity(0.1)]
              : [Colors.grey.withOpacity(0.3), Colors.black.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: aberto ? Colors.blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (aberto ? Colors.blueAccent : Colors.black).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                _buildAnimatedIcon(aberto),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aberto ? 'Caixa Operacional' : 'Caixa Encerrado',
                        style: TextStyle(
                          color: aberto ? Colors.blueAccent : Colors.white60,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        abertura?.numero ?? '--',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (aberto && abertura != null)
                        Text(
                          'Iniciado em: ${formatoHora.format(abertura.dataAbertura)}',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildQuickActions(aberto, ds),
        ],
      ),
    );
  }

  Widget _buildAnimatedIcon(bool aberto) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: (aberto ? Colors.blueAccent : Colors.grey).withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: (aberto ? Colors.blueAccent : Colors.grey).withOpacity(0.3),
        ),
      ),
      child: Icon(
        aberto ? Icons.point_of_sale_rounded : Icons.lock_clock_rounded,
        color: aberto ? Colors.blueAccent : Colors.grey,
        size: 32,
      ),
    );
  }

  Future<void> _imprimirFechamento(AberturaCaixa ab, FechamentoCaixa fe) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = authService.empresaAtual;
      
      if (empresa == null) throw Exception('Empresa não selecionada');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Gerando Impressão do Caixa...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Obter vendas entre abertura e fechamento
      final vendas = dataService.vendasBalcao.where((v) {
        return (v.dataVenda.isAfter(ab.dataAbertura) || v.dataVenda.isAtSameMomentAs(ab.dataAbertura)) &&
               v.dataVenda.isBefore(fe.dataFechamento.add(const Duration(seconds: 1)));
      }).toList();

      await CaixaPDFService.gerarPDFTermico(
        abertura: ab,
        fechamento: fe,
        empresa: empresa,
        vendas: vendas,
      ).then((pdfData) async {
        if (context.mounted) Navigator.pop(context);
        
        await Printing.layoutPdf(
          onLayout: (format) async => pdfData,
          name: 'Fechamento_Caixa_${ab.numero}.pdf',
        );
      });
      
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildQuickActions(bool aberto, DataService ds) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (!aberto)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _mostrarDialogoAbertura(context, ds),
                icon: const Icon(Icons.play_circle_filled_rounded, size: 28),
                label: const Text('INICIAR NOVA SESSÃO DE CAIXA', style: TextStyle(letterSpacing: 1.1, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: Colors.blueAccent.withOpacity(0.4),
                ),
              ),
            )
          else ...[
            _buildActionButton(
              label: 'Pagamento',
              icon: Icons.remove_circle_rounded,
              color: Colors.orangeAccent,
              onTap: () => _mostrarDialogoSangria(context, ds, isPagamento: true),
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              label: 'Suprimento',
              icon: Icons.add_circle_rounded,
              color: Colors.lightBlueAccent,
              onTap: () => _mostrarDialogoSuprimento(context, ds),
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              label: 'Fechar',
              icon: Icons.stop_circle_rounded,
              color: Colors.redAccent,
              onTap: () => _mostrarDialogoFechamento(context, ds),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResumoSession(DataService ds, AberturaCaixa abertura) {
    // Pegar totais reais do DS
    final sangrias = ds.getSangriasCaixaAtual();
    final suprimentos = ds.getSuprimentosCaixaAtual();
    final totalSangrias = sangrias.fold(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos = suprimentos.fold(0.0, (sum, s) => sum + s.valor);

    // Calcular Vendas
    final vendas = ds.vendasBalcao.where((v) => !v.cancelado && (v.dataVenda.isAfter(abertura.dataAbertura) || v.dataVenda.isAtSameMomentAs(abertura.dataAbertura)));
    final totalVendas = vendas.fold(0.0, (sum, v) => sum + v.valorTotal);

    // Saldo Atual
    final saldo = abertura.valorInicial + totalVendas + totalSuprimentos - totalSangrias;

    return Row(
      children: [
        _buildStatCard('Entradas', formatoMoeda.format(totalVendas + totalSuprimentos), Icons.trending_up, Colors.greenAccent),
        const SizedBox(width: 12),
        _buildStatCard('Saídas', formatoMoeda.format(totalSangrias), Icons.trending_down, Colors.redAccent),
        const SizedBox(width: 12),
        _buildStatCard('Saldo', formatoMoeda.format(saldo), Icons.account_balance_wallet, Colors.blueAccent),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.02),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  color: color.withOpacity(0.9), 
                  fontWeight: FontWeight.w900, 
                  fontSize: 16,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverFluxoLista(DataService ds, AberturaCaixa abertura) {
    final movs = _getMovimentacoesExt(ds, abertura);

    if (movs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.1), size: 48),
              const SizedBox(height: 12),
              Text('Nenhuma movimentação registrada', style: TextStyle(color: Colors.white.withOpacity(0.3))),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final m = movs[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (m['cor'] as Color).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(m['icone'] as IconData, color: m['cor'] as Color, size: 20),
                ),
                title: Text(
                  m['descricao'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${formatoHora.format(m['data'] as DateTime)} • ${m['forma']}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
                trailing: Text(
                  formatoMoeda.format(m['valor']),
                  style: TextStyle(
                    color: (m['valor'] as double) >= 0 ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          },
          childCount: movs.length,
        ),
      ),
    );
  }

  Widget _buildSliverHistorico(DataService ds) {
    final hist = ds.aberturasCaixa.map((ab) {
      final fe = ds.fechamentosCaixa.firstWhereOrNull((f) => f.aberturaCaixaId == ab.id);
      return MapEntry(ab, fe);
    }).where((e) => e.value != null).toList();

    hist.sort((a, b) => b.key.dataAbertura.compareTo(a.key.dataAbertura));

    if (hist.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(child: Text('Nenhum fechamento passado', style: TextStyle(color: Colors.white30))),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = hist[index];
            return _buildCardCaixaModerno(item.key, item.value!);
          },
          childCount: hist.length,
        ),
      ),
    );
  }

  Widget _buildCardCaixaModerno(AberturaCaixa ab, FechamentoCaixa fe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('dd MMM').format(ab.dataAbertura),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (fe.diferenca >= 0 ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fe.diferenca >= 0 ? 'Conforme' : 'Divergente',
                      style: TextStyle(color: fe.diferenca >= 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.blueAccent, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _imprimirFechamento(ab, fe),
                      tooltip: 'Imprimir Fechamento',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniInfo('Entrada', formatoMoeda.format(fe.valorEsperado))),
              Expanded(child: _miniInfo('Real', formatoMoeda.format(fe.valorReal))),
              Expanded(child: _miniInfo('Dif.', formatoMoeda.format(fe.diferenca))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white30, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  List<Map<String, dynamic>> _getMovimentacoesExt(DataService ds, AberturaCaixa ab) {
    final list = <Map<String, dynamic>>[];

    // Vendas
    for (final v in ds.vendasBalcao) {
      if (!v.cancelado && (v.dataVenda.isAfter(ab.dataAbertura) || v.dataVenda.isAtSameMomentAs(ab.dataAbertura))) {
        list.add({
          'data': v.dataVenda,
          'descricao': 'Venda PDV ${v.numero}',
          'valor': v.valorTotal,
          'forma': _formatForma(v.tipoPagamento),
          'icone': Icons.shopping_basket_rounded,
          'cor': Colors.greenAccent,
        });
      }
    }

    // Sangrias
    for (final s in ds.getSangriasCaixaAtual()) {
      list.add({
        'data': s.data,
        'descricao': s.motivo,
        'valor': -s.valor,
        'forma': 'Dinheiro',
        'icone': Icons.outbox_rounded,
        'cor': Colors.orangeAccent,
      });
    }

    // Suprimentos
    for (final s in ds.getSuprimentosCaixaAtual()) {
      list.add({
        'data': s.data,
        'descricao': s.motivo,
        'valor': s.valor,
        'forma': 'Dinheiro',
        'icone': Icons.move_to_inbox_rounded,
        'cor': Colors.blueAccent,
      });
    }

    list.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));
    return list;
  }

  String _formatForma(TipoPagamento t) {
    switch (t) {
      case TipoPagamento.dinheiro: return 'Dinheiro';
      case TipoPagamento.cartaoCredito: return 'Crédito';
      case TipoPagamento.cartaoDebito: return 'Débito';
      case TipoPagamento.pix: return 'PIX';
      case TipoPagamento.alimentacao: return 'Ticket';
      default: return 'Outro';
    }
  }

  Widget _buildCardCaixa(
    AberturaCaixa abertura,
    FechamentoCaixa? fechamento,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isAberto = fechamento == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isAberto ? Icons.lock_open : Icons.lock,
                    color: isAberto ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abertura.numero,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        formatoData.format(abertura.dataAbertura),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAberto ? 'Aberto' : 'Fechado',
                    style: TextStyle(
                      color: isAberto ? Colors.green : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valor Inicial',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(abertura.valorInicial),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (fechamento != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Valor Real',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorReal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (fechamento != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valor Esperado',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorEsperado),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Diferença',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.diferenca),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: fechamento.diferenca >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Fechado em: ${formatoData.format(fechamento.dataFechamento)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoAbertura(BuildContext context, DataService dataService) {
    final valorController = TextEditingController(text: '0.00');
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Abrir Caixa', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor Inicial (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
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
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
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
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
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
                  ),
                  maxLines: 3,
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
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.abrirCaixaComValor(
                    valor,
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Caixa aberto com ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao abrir caixa: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Abrir Caixa'),
          ),
        ],
      ),
    );
  }

  // Função auxiliar para construir linha de informação
  Widget _buildInfoRow(String label, String value, IconData icon, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.6), size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white.withOpacity(0.9),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoFechamento(BuildContext context, DataService dataService) {
    final abertura = dataService.aberturaCaixaAtual;
    if (abertura == null) return;

    final valorEsperadoController = TextEditingController();
    final valorRealController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    // Calcular valor esperado baseado nas vendas desde a abertura do caixa
    final vendasDoCaixa = dataService.vendasBalcao.where((v) {
      return v.dataVenda.isAfter(abertura.dataAbertura) ||
          v.dataVenda.isAtSameMomentAs(abertura.dataAbertura);
    }).toList();

    // --- Novos cálculos para detalhamento ---
    final totaisPorForma = <TipoPagamento, double>{};
    int totalItensVendidos = 0;
    double valorTotalProdutos = 0.0;
    int totalVendasRealizadas = 0;

    // Inicializar mapa de totais
    for (var tipo in TipoPagamento.values) {
      if (tipo != TipoPagamento.outro) {
        totaisPorForma[tipo] = 0.0;
      }
    }

    // Processar Vendas Balcão
    for (var v in vendasDoCaixa) {
      if (v.isCancelada || v.tipoPagamento == TipoPagamento.outro) continue;
      
      totalVendasRealizadas++;
      totaisPorForma[v.tipoPagamento] = (totaisPorForma[v.tipoPagamento] ?? 0.0) + v.valorTotal;
      
      for (var item in v.itens) {
        totalItensVendidos += item.quantidade;
        valorTotalProdutos += item.subtotal;
      }
    }

    // Processar Pedidos (Mesas/Comandas)
    for (var p in dataService.pedidos) {
      for (var pag in p.pagamentos) {
        if (!pag.recebido || pag.dataRecebimento == null) continue;
        if (pag.dataRecebimento!.isBefore(abertura.dataAbertura)) continue;
        if (pag.tipo == TipoPagamento.outro) continue;

        totaisPorForma[pag.tipo] = (totaisPorForma[pag.tipo] ?? 0.0) + pag.valor;
      }
      
      // Contabilizar itens dos pedidos recebidos no período
      // (Aproximação: se o pedido teve pagamento no período, contamos seus itens)
      final tevePagamentoNoPeriodo = p.pagamentos.any((pag) => 
        pag.recebido && 
        pag.dataRecebimento != null && 
        !pag.dataRecebimento!.isBefore(abertura.dataAbertura)
      );
      
      if (tevePagamentoNoPeriodo) {
        for (var item in p.produtos) {
          totalItensVendidos += item.quantidade.toInt();
          valorTotalProdutos += (item.preco * item.quantidade);
        }
        for (var item in p.servicos) {
          totalItensVendidos += 1;
          valorTotalProdutos += (item.valor + item.valorAdicional);
        }
      }
    }

    // Calcular sangrias e suprimentos do caixa atual
    final sangriasCaixaAtual = dataService.getSangriasCaixaAtual();
    final suprimentosCaixaAtual = dataService.getSuprimentosCaixaAtual();
    final totalSangrias = sangriasCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos = suprimentosCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    
    // Valor esperado no caixa FÍSICO (Dinheiro + Inicial + Suprimentos - Sangrias)
    // Nota: PIX/Cartão não ficam no caixa físico, mas o sistema pode querer rastrear
    // Aqui mantemos a lógica original de "Dinheiro + PIX" se assim estava,
    // mas geralmente PIX não entra na conferência de "dinheiro na gaveta".
    // Vou ajustar para ser apenas DINHEIRO + INICIAL para o "Esperado" físico.
    final totalDinheiro = totaisPorForma[TipoPagamento.dinheiro] ?? 0.0;
    final valorEsperadoCalculado = abertura.valorInicial + totalDinheiro - totalSangrias + totalSuprimentos;
    
    valorEsperadoController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');
    valorRealController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.redAccent.withOpacity(0.3),
                Colors.red.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fechar Caixa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Preencha os dados para finalizar',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Informações da abertura - Card melhorado
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.2),
                        Colors.blue.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.4), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.point_of_sale, color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            abertura.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEstatsCard(
                              'Itens Vendidos',
                              totalItensVendidos.toString(),
                              Icons.inventory_2,
                              Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEstatsCard(
                              'Total em Itens',
                              formatoMoeda.format(valorTotalProdutos),
                              Icons.monetization_on,
                              Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Resumo por Forma de Pagamento',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Lista de formas de pagamento
                      ...totaisPorForma.entries.where((e) => e.value > 0).map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildInfoRow(
                            e.key.nome,
                            formatoMoeda.format(e.value),
                            e.key.icone,
                            e.key.cor,
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Movimentações (Sangria/Sup.)',
                        formatoMoeda.format(totalSuprimentos - totalSangrias),
                        Icons.swap_vert,
                        (totalSuprimentos - totalSangrias) >= 0 ? Colors.blueAccent : Colors.orangeAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Fundo de Caixa Inicial',
                        formatoMoeda.format(abertura.valorInicial),
                        Icons.account_balance_wallet,
                        Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calculate, color: Colors.greenAccent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Valor Esperado',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              formatoMoeda.format(valorEsperadoCalculado),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Seção de Valores
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.attach_money, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Valores do Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: valorEsperadoController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Esperado (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.calculate, color: Colors.blueAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor esperado';
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
                      TextFormField(
                        controller: valorRealController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Real no Caixa (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.account_balance_wallet, color: Colors.greenAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor real';
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
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Informações do Responsável
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withOpacity(0.15),
                        Colors.purple.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline, color: Colors.purpleAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Responsável pelo Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: responsavelController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Nome Completo',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Ex: João Silva',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.person, color: Colors.purpleAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                        // Campo agora é opcional - sem validação obrigatória
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Observações
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.note_alt, color: Colors.orangeAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Observações',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: observacaoController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Informe observações sobre o fechamento:\n• Diferenças encontradas\n• Problemas identificados\n• Observações importantes',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          prefixIcon: const Icon(Icons.edit_note, color: Colors.orangeAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
                          ),
                        ),
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Informação sobre campos obrigatórios
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Certifique-se de preencher todos os campos obrigatórios antes de fechar o caixa.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              print('>>> [Fechar Caixa] ========== BOTÃO PRESSIONADO ==========');
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Processando fechamento...'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
              
              if (formKey.currentState == null) {
                print('>>> [Fechar Caixa] ERRO: formKey.currentState é null!');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Erro: Formulário não inicializado'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              
              final isValid = formKey.currentState!.validate();
              if (!isValid) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, preencha todos os campos obrigatórios corretamente'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
                return;
              }
              
              formKey.currentState!.save();
              
              try {
                final valorEsperadoStr = valorEsperadoController.text.replaceAll('.', '').replaceAll(',', '.');
                final valorRealStr = valorRealController.text.replaceAll('.', '').replaceAll(',', '.');
                
                final valorEsperado = double.tryParse(valorEsperadoStr) ?? 0.0;
                final valorReal = double.tryParse(valorRealStr) ?? 0.0;
                
                final diferenca = valorReal - valorEsperado;
                final responsavel = responsavelController.text.trim().isEmpty 
                    ? null 
                    : responsavelController.text.trim();
                
                if (diferenca.abs() > 0.01) {
                  final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (confirmContext) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Row(
                          children: [
                            Icon(
                              diferenca > 0 ? Icons.add_circle : Icons.remove_circle,
                              color: diferenca > 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 12),
                            const Text('Diferença Detectada', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Diferença detectada: ${formatoMoeda.format(diferenca.abs())}', style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 12),
                            const Text('Deseja continuar?', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmContext, false),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(confirmContext, true),
                            style: ElevatedButton.styleFrom(backgroundColor: diferenca > 0 ? Colors.green : Colors.red),
                            child: const Text('Confirmar'),
                          ),
                        ],
                      ),
                    );

                  if (confirmar != true) return;
                }

                print('>>> [Fechar Caixa] Chamando registrarFechamentoCaixa...');
                final AberturaCaixa? aberturaParaPrint = dataService.aberturaCaixaAtual;
                
                print('>>> [Fechar Caixa] Abertura capturada: ${aberturaParaPrint?.numero}');

                final fechamento = await dataService.registrarFechamentoCaixa(
                  valorEsperado: valorEsperado,
                  valorReal: valorReal,
                  observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
                  responsavel: responsavel,
                );
                
                if (fechamento == null) {
                  print('>>> [Fechar Caixa] ERRO: Fechamento retornou null');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Erro ao fechar caixa.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                print('>>> [Fechar Caixa] Fechamento realizado com sucesso: ${fechamento.id}');

                if (context.mounted) {
                  // Primeiro removemos o diálogo de formulário
                  Navigator.pop(dialogContext);
                  
                  if (aberturaParaPrint != null) {
                    print('>>> [Fechar Caixa] Exibindo Diálogo de Sucesso e Impressão...');
                    
                    // Exibimos um diálogo de sucesso com opção de imprimir
                    await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: Column(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'Caixa Encerrado!',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'O caixa ${aberturaParaPrint.numero} foi fechado com sucesso.',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Diferença: ${formatoMoeda.format(fechamento.diferenca)}',
                              style: TextStyle(
                                color: fechamento.diferenca >= 0 ? Colors.greenAccent : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _imprimirFechamento(aberturaParaPrint, fechamento);
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.print),
                                  label: const Text('IMPRIMIR FECHAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('CONCLUIR E SAIR', style: TextStyle(color: Colors.white54)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                    
                    print('>>> [Fechar Caixa] Diálogo de sucesso fechado, navegando para Home...');
                  }

                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomePage()),
                      (route) => false,
                    );
                  }
                }
              } catch (e) {
                print('>>> [Fechar Caixa] EXCEÇÃO: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao fechar caixa: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Fechar Caixa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSangria(BuildContext context, DataService dataService, {bool isPagamento = false}) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isPagamento ? Icons.outbox : Icons.remove_circle, color: isPagamento ? Colors.purpleAccent : Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text(isPagamento ? 'Registrar Pagamento' : 'Registrar Sangria', style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSangria(
                    valor: valor,
                    motivo: isPagamento ? '[PAGAMENTO] ${motivoController.text.trim()}' : motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isPagamento 
                            ? 'Pagamento registrado: ${formatoMoeda.format(valor)}'
                            : 'Sangria registrada: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: isPagamento ? Colors.purple : Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar sangria: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSuprimento(BuildContext context, DataService dataService) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text('Registrar Suprimento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSuprimento(
                    valor: valor,
                    motivo: motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Suprimento registrado: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar suprimento: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEstatsCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}


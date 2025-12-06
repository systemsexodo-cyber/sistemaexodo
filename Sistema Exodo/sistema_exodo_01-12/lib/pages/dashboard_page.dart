import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../models/conta_pagar.dart';

class DashboardPage extends StatefulWidget {
  final bool showAppBar;
  
  const DashboardPage({super.key, this.showAppBar = true});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _periodoSelecionado = 'mês'; // 'hoje', 'semana', 'mês', 'personalizado'
  DateTime? _dataInicioCustomizada;
  DateTime? _dataFimCustomizada;

  DateTime _getInicioPeriodo() {
    final agora = DateTime.now();
    switch (_periodoSelecionado) {
      case 'hoje':
        return DateTime(agora.year, agora.month, agora.day);
      case 'semana':
        final diasDaSemana = agora.weekday - 1; // 0 = segunda-feira
        return DateTime(agora.year, agora.month, agora.day).subtract(Duration(days: diasDaSemana));
      case 'mês':
        return DateTime(agora.year, agora.month, 1);
      case 'personalizado':
        return _dataInicioCustomizada ?? DateTime(agora.year, agora.month, 1);
      default:
        return DateTime(agora.year, agora.month, 1);
    }
  }

  DateTime _getFimPeriodo() {
    final agora = DateTime.now();
    switch (_periodoSelecionado) {
      case 'hoje':
        return DateTime(agora.year, agora.month, agora.day).add(const Duration(days: 1));
      case 'semana':
        final diasDaSemana = agora.weekday - 1;
        final inicioSemana = DateTime(agora.year, agora.month, agora.day).subtract(Duration(days: diasDaSemana));
        return inicioSemana.add(const Duration(days: 7));
      case 'mês':
        return DateTime(agora.year, agora.month + 1, 1);
      case 'personalizado':
        return _dataFimCustomizada ?? DateTime(agora.year, agora.month + 1, 1);
      default:
        return DateTime(agora.year, agora.month + 1, 1);
    }
  }

  String _getTituloPeriodo() {
    final formato = DateFormat('dd/MM/yyyy');
    final inicio = _getInicioPeriodo();
    final fim = _getFimPeriodo().subtract(const Duration(days: 1));
    
    switch (_periodoSelecionado) {
      case 'hoje':
        return 'Hoje - ${formato.format(inicio)}';
      case 'semana':
        return '${formato.format(inicio)} - ${formato.format(fim)}';
      case 'mês':
        final meses = ['JANEIRO', 'FEVEREIRO', 'MARÇO', 'ABRIL', 'MAIO', 'JUNHO', 
                      'JULHO', 'AGOSTO', 'SETEMBRO', 'OUTUBRO', 'NOVEMBRO', 'DEZEMBRO'];
        return '${meses[inicio.month - 1]} ${inicio.year}';
      case 'personalizado':
        return '${formato.format(inicio)} - ${formato.format(fim)}';
      default:
        return 'Período';
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Consumer<DataService>(
          builder: (context, dataService, _) {
            final inicioPeriodo = _getInicioPeriodo();
            final fimPeriodo = _getFimPeriodo();
            final agora = DateTime.now();
            final inicioDia = DateTime(agora.year, agora.month, agora.day);
            final fimDia = inicioDia.add(const Duration(days: 1));

            // Calcular estatísticas usando o período filtrado
            final statsPeriodo = _calcularEstatisticasMes(dataService, inicioPeriodo, fimPeriodo);
            final statsDia = _calcularEstatisticasDia(dataService, inicioDia, fimDia);
            final statsCaixa = _calcularEstatisticasCaixa(dataService);
            final topProdutos = _calcularTopProdutos(dataService, inicioPeriodo, fimPeriodo);
            final topServicos = _calcularTopServicos(dataService, inicioPeriodo, fimPeriodo);
            final pedidosPendentes = _calcularPedidosPendentes(dataService);
            final contasPagar = _calcularContasPagar(dataService);
            final receitasDespesas = _calcularReceitasDespesas(dataService, inicioPeriodo, fimPeriodo);

            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filtro de Data
                  _buildFiltroData(),
                  const SizedBox(height: 16),
                  
                  // Gráfico de Receitas vs Despesas
                  _buildCardGraficoReceitas(receitasDespesas),
                  const SizedBox(height: 16),

                  // Resumo do Dia
                  _buildCardResumo(
                    'Resumo do Dia',
                    statsDia,
                    Colors.blue,
                    Icons.today,
                  ),
                  const SizedBox(height: 16),

                  // Resumo do Período Selecionado
                  _buildCardResumo(
                    _periodoSelecionado == 'hoje' ? 'Resumo do Dia' : 
                    _periodoSelecionado == 'semana' ? 'Resumo da Semana' :
                    _periodoSelecionado == 'mês' ? 'Resumo do Mês' : 'Resumo do Período',
                    statsPeriodo,
                    Colors.purple,
                    Icons.calendar_month,
                  ),
                  const SizedBox(height: 16),

                  // Status do Caixa
                  _buildCardCaixa(statsCaixa),
                  const SizedBox(height: 16),

                  // Grid de Métricas
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Pedidos Pendentes',
                          pedidosPendentes['quantidade'].toString(),
                          Colors.orange,
                          Icons.pending_actions,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          'Contas a Pagar',
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(contasPagar['total']),
                          Colors.red,
                          Icons.account_balance_wallet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Top Produtos
                  _buildCardTopProdutos(topProdutos, _periodoSelecionado),
                  const SizedBox(height: 16),

                  // Top Serviços
                  _buildCardTopServicos(topServicos, _periodoSelecionado),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        );

    if (widget.showAppBar) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Dashboard'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.filter_alt),
                tooltip: 'Filtro de Data',
                onPressed: () => _mostrarDialogFiltroData(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar',
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          body: body,
        ),
      );
    } else {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: body,
        ),
      );
    }
  }

  Map<String, dynamic> _calcularEstatisticasDia(
    DataService dataService,
    DateTime inicio,
    DateTime fim,
  ) {
    // IMPORTANTE: Excluir vendas e pedidos cancelados
    final vendasDia = dataService.vendasBalcao.where((v) {
      if (v.isCancelada) return false; // Não incluir vendas canceladas
      return v.dataVenda.isAfter(inicio) &&
          v.dataVenda.isBefore(fim);
    }).toList();

    final pedidosDia = dataService.pedidos.where((p) {
      if (p.status.toLowerCase() == 'cancelado') return false; // Não incluir pedidos cancelados
      return p.dataPedido.isAfter(inicio) &&
          p.dataPedido.isBefore(fim);
    }).toList();

    double totalVendas = vendasDia.fold(0.0, (sum, v) => sum + v.valorTotal);
    double totalPedidos = pedidosDia.fold(0.0, (sum, p) => sum + p.totalRecebido);
    int quantidadeVendas = vendasDia.length;
    int quantidadePedidos = pedidosDia.length;

    return {
      'total': totalVendas + totalPedidos,
      'vendas': totalVendas,
      'pedidos': totalPedidos,
      'quantidadeVendas': quantidadeVendas,
      'quantidadePedidos': quantidadePedidos,
    };
  }

  Map<String, dynamic> _calcularEstatisticasMes(
    DataService dataService,
    DateTime inicio,
    DateTime fim,
  ) {
    // IMPORTANTE: Excluir vendas e pedidos cancelados
    final vendasMes = dataService.vendasBalcao.where((v) {
      if (v.isCancelada) return false; // Não incluir vendas canceladas
      return v.dataVenda.isAfter(inicio) &&
          v.dataVenda.isBefore(fim);
    }).toList();

    final pedidosMes = dataService.pedidos.where((p) {
      if (p.status.toLowerCase() == 'cancelado') return false; // Não incluir pedidos cancelados
      return p.dataPedido.isAfter(inicio) &&
          p.dataPedido.isBefore(fim);
    }).toList();

    double totalVendas = vendasMes.fold(0.0, (sum, v) => sum + v.valorTotal);
    double totalPedidos = pedidosMes.fold(0.0, (sum, p) => sum + p.totalRecebido);
    int quantidadeVendas = vendasMes.length;
    int quantidadePedidos = pedidosMes.length;

    return {
      'total': totalVendas + totalPedidos,
      'vendas': totalVendas,
      'pedidos': totalPedidos,
      'quantidadeVendas': quantidadeVendas,
      'quantidadePedidos': quantidadePedidos,
    };
  }

  Map<String, dynamic> _calcularEstatisticasCaixa(DataService dataService) {
    final abertura = dataService.aberturaCaixaAtual;
    if (abertura == null) {
      return {
        'aberto': false,
        'saldo': 0.0,
        'sangrias': 0.0,
        'suprimentos': 0.0,
      };
    }

    final agora = DateTime.now();
    final inicioDia = DateTime(agora.year, agora.month, agora.day);
    final fimDia = inicioDia.add(const Duration(days: 1));

    // Vendas do dia (EXCLUIR canceladas)
    final vendasDia = dataService.vendasBalcao.where((v) {
      if (v.isCancelada) return false; // Não incluir vendas canceladas
      return v.dataVenda.isAfter(inicioDia) &&
          v.dataVenda.isBefore(fimDia);
    }).toList();

    double totalVendas = vendasDia.fold(0.0, (sum, v) => sum + v.valorTotal);

    // Sangrias e suprimentos do caixa atual
    final sangrias = dataService.getSangriasCaixaAtual();
    final suprimentos = dataService.getSuprimentosCaixaAtual();
    double totalSangrias = sangrias.fold(0.0, (sum, s) => sum + s.valor);
    double totalSuprimentos = suprimentos.fold(0.0, (sum, s) => sum + s.valor);

    // Saldo = valor inicial + vendas + suprimentos - sangrias
    double saldo = abertura.valorInicial + totalVendas + totalSuprimentos - totalSangrias;

    return {
      'aberto': true,
      'saldo': saldo,
      'valorInicial': abertura.valorInicial,
      'vendas': totalVendas,
      'sangrias': totalSangrias,
      'suprimentos': totalSuprimentos,
      'numero': abertura.numero,
    };
  }

  List<Map<String, dynamic>> _calcularTopProdutos(
    DataService dataService,
    DateTime inicio,
    DateTime fim,
  ) {
    // IMPORTANTE: Excluir vendas canceladas
    final vendas = dataService.vendasBalcao.where((v) {
      if (v.isCancelada) return false; // Não incluir vendas canceladas
      return v.dataVenda.isAfter(inicio) &&
          v.dataVenda.isBefore(fim);
    }).toList();

    final produtosVendidos = <String, Map<String, dynamic>>{};

    for (final venda in vendas) {
      for (final item in venda.itens) {
        if (!item.isServico) {
          final nome = item.nome;
          if (!produtosVendidos.containsKey(nome)) {
            produtosVendidos[nome] = {
              'nome': nome,
              'quantidade': 0,
              'total': 0.0,
            };
          }
          produtosVendidos[nome]!['quantidade'] =
              (produtosVendidos[nome]!['quantidade'] as int) + item.quantidade;
          produtosVendidos[nome]!['total'] =
              (produtosVendidos[nome]!['total'] as double) +
                  (item.precoUnitario * item.quantidade);
        }
      }
    }

    final lista = produtosVendidos.values.toList();
    lista.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

    return lista.take(5).toList();
  }

  List<Map<String, dynamic>> _calcularTopServicos(
    DataService dataService,
    DateTime inicio,
    DateTime fim,
  ) {
    // IMPORTANTE: Excluir pedidos cancelados
    final pedidos = dataService.pedidos.where((p) {
      if (p.status.toLowerCase() == 'cancelado') return false; // Não incluir pedidos cancelados
      return p.dataPedido.isAfter(inicio) &&
          p.dataPedido.isBefore(fim);
    }).toList();

    final servicosVendidos = <String, Map<String, dynamic>>{};

    for (final pedido in pedidos) {
      for (final servico in pedido.servicos) {
        final nome = servico.descricao;
        if (!servicosVendidos.containsKey(nome)) {
          servicosVendidos[nome] = {
            'nome': nome,
            'quantidade': 0,
            'total': 0.0,
          };
        }
        servicosVendidos[nome]!['quantidade'] =
            (servicosVendidos[nome]!['quantidade'] as int) + 1;
        servicosVendidos[nome]!['total'] =
            (servicosVendidos[nome]!['total'] as double) +
                (servico.valor + servico.valorAdicional);
      }
    }

    final lista = servicosVendidos.values.toList();
    lista.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

    return lista.take(5).toList();
  }

  Map<String, dynamic> _calcularPedidosPendentes(DataService dataService) {
    final pedidosPendentes = dataService.pedidos.where((p) {
      return p.status.toLowerCase() != 'cancelado' && !p.totalmenteRecebido;
    }).toList();

    double totalPendente = pedidosPendentes.fold(
      0.0,
      (sum, p) => sum + p.valorPendente,
    );

    return {
      'quantidade': pedidosPendentes.length,
      'total': totalPendente,
    };
  }

  Map<String, dynamic> _calcularContasPagar(DataService dataService) {
    final agora = DateTime.now();
    final contasPendentes = dataService.contasPagar.where((c) {
      return c.status != StatusContaPagar.pago && 
          c.status != StatusContaPagar.cancelado &&
          c.dataVencimento.isBefore(agora.add(const Duration(days: 30)));
    }).toList();

    double total = contasPendentes.fold(0.0, (sum, c) => sum + c.valor);

    return {
      'quantidade': contasPendentes.length,
      'total': total,
    };
  }

  Map<String, dynamic> _calcularReceitasDespesas(
    DataService dataService,
    DateTime inicioMes,
    DateTime fimMes,
  ) {
    // Receitas: Vendas do balcão + Pedidos recebidos do mês
    // IMPORTANTE: Excluir vendas e pedidos cancelados
    final vendasMes = dataService.vendasBalcao.where((v) {
      if (v.isCancelada) return false; // Não incluir vendas canceladas
      return v.dataVenda.isAfter(inicioMes) &&
          v.dataVenda.isBefore(fimMes);
    }).toList();

    final pedidosMes = dataService.pedidos.where((p) {
      if (p.status.toLowerCase() == 'cancelado') return false; // Não incluir pedidos cancelados
      return p.dataPedido.isAfter(inicioMes) &&
          p.dataPedido.isBefore(fimMes);
    }).toList();

    // Total de receitas = vendas + pedidos recebidos
    double totalVendas = vendasMes.fold(0.0, (sum, v) => sum + v.valorTotal);
    double totalPedidosRecebidos = pedidosMes.fold(
      0.0,
      (sum, p) => sum + p.totalRecebido,
    );
    double totalReceitas = totalVendas + totalPedidosRecebidos;

    // Despesas: Contas a pagar que foram pagas no mês
    final contasPagas = dataService.contasPagar.where((c) {
      if (c.status != StatusContaPagar.pago) return false;
      if (c.dataPagamento == null) return false;
      return c.dataPagamento!.isAfter(inicioMes) &&
          c.dataPagamento!.isBefore(fimMes);
    }).toList();

    double totalDespesas = contasPagas.fold(0.0, (sum, c) => sum + (c.valorPago ?? c.valor));

    // Lucro líquido = Receitas - Despesas
    double lucroLiquido = totalReceitas - totalDespesas;

    return {
      'receitas': totalReceitas,
      'despesas': totalDespesas,
      'lucroLiquido': lucroLiquido,
      'vendas': totalVendas,
      'pedidosRecebidos': totalPedidosRecebidos,
    };
  }

  Widget _buildCardResumo(
    String titulo,
    Map<String, dynamic> stats,
    Color color,
    IconData icon,
  ) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total',
                    formato.format(stats['total']),
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Vendas',
                    formato.format(stats['vendas']),
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Pedidos',
                    formato.format(stats['pedidos']),
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Qtd. Vendas',
                    stats['quantidadeVendas'].toString(),
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardCaixa(Map<String, dynamic> stats) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final estaAberto = stats['aberto'] as bool;

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (estaAberto ? Colors.green : Colors.red).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    estaAberto ? Icons.lock_open : Icons.lock,
                    color: estaAberto ? Colors.green : Colors.red,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        estaAberto ? 'Caixa Aberto' : 'Caixa Fechado',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (estaAberto && stats['numero'] != null)
                        Text(
                          stats['numero'],
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (estaAberto) ...[
              const SizedBox(height: 20),
              _buildStatItem(
                'Saldo Atual',
                formato.format(stats['saldo']),
                Colors.green,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      'Valor Inicial',
                      formato.format(stats['valorInicial']),
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      'Vendas Hoje',
                      formato.format(stats['vendas']),
                      Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroData() {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.date_range, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTituloPeriodo(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Período selecionado',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              tooltip: 'Alterar período',
              onPressed: () => _mostrarDialogFiltroData(),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogFiltroData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Filtro de Data',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Opções rápidas
            _buildOpcaoPeriodo('hoje', 'Hoje', Icons.today),
            const SizedBox(height: 8),
            _buildOpcaoPeriodo('semana', 'Esta Semana', Icons.calendar_view_week),
            const SizedBox(height: 8),
            _buildOpcaoPeriodo('mês', 'Este Mês', Icons.calendar_month),
            const SizedBox(height: 8),
            _buildOpcaoPeriodo('personalizado', 'Período Personalizado', Icons.date_range),
            
            // Seletores de data personalizada
            if (_periodoSelecionado == 'personalizado') ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Data Início',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final data = await showDatePicker(
                              context: context,
                              initialDate: _dataInicioCustomizada ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.blue,
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E1E2E),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (data != null) {
                              setState(() {
                                _dataInicioCustomizada = DateTime(data.year, data.month, data.day);
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  _dataInicioCustomizada != null
                                      ? DateFormat('dd/MM/yyyy').format(_dataInicioCustomizada!)
                                      : 'Selecionar',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Data Fim',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final data = await showDatePicker(
                              context: context,
                              initialDate: _dataFimCustomizada ?? DateTime.now(),
                              firstDate: _dataInicioCustomizada ?? DateTime(2020),
                              lastDate: DateTime.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Colors.blue,
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E1E2E),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (data != null) {
                              setState(() {
                                _dataFimCustomizada = DateTime(data.year, data.month, data.day).add(const Duration(days: 1));
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  _dataFimCustomizada != null
                                      ? DateFormat('dd/MM/yyyy').format(_dataFimCustomizada!.subtract(const Duration(days: 1)))
                                      : 'Selecionar',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_periodoSelecionado == 'personalizado' && 
                  (_dataInicioCustomizada == null || _dataFimCustomizada == null)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione as datas de início e fim'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpcaoPeriodo(String periodo, String label, IconData icon) {
    final isSelected = _periodoSelecionado == periodo;
    return InkWell(
      onTap: () {
        setState(() {
          _periodoSelecionado = periodo;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.blue : Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Colors.blue, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTopProdutos(List<Map<String, dynamic>> topProdutos, String periodo) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.trending_up, color: Colors.green, size: 28),
                ),
                const SizedBox(width: 16),
                Text(
                  'Top 5 Produtos ${_getLabelPeriodo(periodo)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topProdutos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Nenhum produto vendido este mês',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              ...topProdutos.asMap().entries.map((entry) {
                final index = entry.key;
                final produto = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              produto['nome'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${produto['quantidade']} unidades',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formato.format(produto['total']),
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  String _getLabelPeriodo(String periodo) {
    switch (periodo) {
      case 'hoje':
        return 'do Dia';
      case 'semana':
        return 'da Semana';
      case 'mês':
        return 'do Mês';
      case 'personalizado':
        return 'do Período';
      default:
        return 'do Mês';
    }
  }

  Widget _buildCardTopServicos(List<Map<String, dynamic>> topServicos, String periodo) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.star, color: Colors.orange, size: 28),
                ),
                const SizedBox(width: 16),
                Text(
                  'Top 5 Serviços ${_getLabelPeriodo(periodo)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topServicos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Nenhum serviço realizado este mês',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              ...topServicos.asMap().entries.map((entry) {
                final index = entry.key;
                final servico = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              servico['nome'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${servico['quantidade']} realizados',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formato.format(servico['total']),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCardGraficoReceitas(Map<String, dynamic> dados) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final receitas = dados['receitas'] as double;
    final despesas = dados['despesas'] as double;
    final lucroLiquido = dados['lucroLiquido'] as double;
    
    final maxValor = [receitas, despesas, lucroLiquido.abs()].reduce((a, b) => a > b ? a : b);
    final alturaGrafico = 200.0;

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.trending_up, color: Colors.green, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Receitas vs Despesas ${_getLabelPeriodo(_periodoSelecionado)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Gráfico de barras
            if (maxValor > 0) ...[
              SizedBox(
                height: alturaGrafico,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Barra de Receitas
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: double.infinity,
                            height: (receitas / maxValor) * alturaGrafico,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.green.shade600,
                                  Colors.green.shade400,
                                ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                formato.format(receitas),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Receitas',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Barra de Despesas
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: double.infinity,
                            height: (despesas / maxValor) * alturaGrafico,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.red.shade600,
                                  Colors.red.shade400,
                                ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                formato.format(despesas),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Despesas',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Barra de Lucro Líquido
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: double.infinity,
                            height: (lucroLiquido.abs() / maxValor) * alturaGrafico,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: lucroLiquido >= 0
                                    ? [
                                        Colors.blue.shade600,
                                        Colors.blue.shade400,
                                      ]
                                    : [
                                        Colors.red.shade800,
                                        Colors.red.shade600,
                                      ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                formato.format(lucroLiquido),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Lucro Líquido',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    'Nenhum dado financeiro este mês',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Resumo em números
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: lucroLiquido >= 0
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: lucroLiquido >= 0
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    lucroLiquido >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: lucroLiquido >= 0 ? Colors.green : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lucro Líquido',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          formato.format(lucroLiquido),
                          style: TextStyle(
                            color: lucroLiquido >= 0 ? Colors.green : Colors.red,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Receitas',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        formato.format(receitas),
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Despesas',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        formato.format(despesas),
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


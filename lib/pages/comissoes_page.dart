import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/funcionario.dart';
import '../models/motorista.dart';
import '../models/pedido.dart';
import '../models/entrega.dart';
import '../models/comissao_vendedor.dart';
import '../theme.dart';
import '../widgets/sync_status_widget.dart';

class ComissoesPage extends StatefulWidget {
  const ComissoesPage({super.key});

  @override
  State<ComissoesPage> createState() => _ComissoesPageState();
}

class _ComissoesPageState extends State<ComissoesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _dataInicio;
  DateTime? _dataFim;
  
  // Filtros específicos
  Funcionario? _funcionarioFiltro;
  Motorista? _motoristaFiltro;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _dataInicio = DateTime.now().subtract(const Duration(days: 30));
    _dataFim = DateTime.now();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final theme = Theme.of(context);
    final formatoData = DateFormat('dd/MM/yyyy');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Relatórios de Comissões'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            const SyncStatusWidget(),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Vendedores', icon: Icon(Icons.people)),
              Tab(text: 'Motoboy/Motorista', icon: Icon(Icons.motorcycle)),
            ],
          ),
        ),
        body: Column(
          children: [
            // Filtros de Data (Comum)
            _buildFiltroDatas(formatoData),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabVendedores(dataService, theme, formatoData, formatoMoeda),
                  _buildTabMotoboys(dataService, theme, formatoData, formatoMoeda),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroDatas(DateFormat format) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          _buildDateTile('Início', _dataInicio, (d) => setState(() => _dataInicio = d), format),
          const SizedBox(width: 8),
          _buildDateTile('Fim', _dataFim, (d) => setState(() => _dataFim = d), format),
        ],
      ),
    );
  }

  Widget _buildTabVendedores(DataService dataService, ThemeData theme, DateFormat df, NumberFormat mf) {
    final comissoes = _filtrarComissoesVenda(dataService.comissoesVendedores);
    final pedidos = _filtrarPedidos(dataService.pedidos);

    final Map<String, Map<String, dynamic>> metricas = {};

    // Processar serviços
    for (final pedido in pedidos) {
      for (final servico in pedido.servicos) {
        if (servico.funcionarioId != null && servico.valorComissao > 0) {
          final fId = servico.funcionarioId!;
          metricas.putIfAbsent(fId, () => {'total': 0.0, 'itens': []});
          metricas[fId]!['total'] += servico.valorComissao;
          metricas[fId]!['itens'].add({
            'desc': 'Serviço: ${servico.descricao}',
            'data': pedido.dataPedido,
            'valor': servico.valorComissao,
            'detalhe': pedido.numero.isNotEmpty ? 'Pedido #${pedido.numero}' : null,

          });
        }
      }
    }

    // Processar vendas diretas/links
    for (final com in comissoes) {
      final fId = com.funcionarioId;
      metricas.putIfAbsent(fId, () => {'total': 0.0, 'itens': []});
      metricas[fId]!['total'] += com.valorComissao;
      metricas[fId]!['itens'].add({
        'desc': 'Venda #${com.pedidoNumero}',
        'data': com.createdAt,
        'valor': com.valorComissao,
        'detalhe': '${com.percentualComissao.toStringAsFixed(1)}%',
      });
    }

    final totalGeral = metricas.values.fold(0.0, (sum, item) => sum + item['total']);

    return Column(
      children: [
        _buildResumoTotal('Total Vendedores', totalGeral, mf),
        Expanded(
          child: metricas.isEmpty
              ? _buildEmptyState('Nenhuma comissão de vendedor encontrada')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: metricas.length,
                  itemBuilder: (context, index) {
                    final fId = metricas.keys.elementAt(index);
                    final dados = metricas[fId]!;
                    final fNome = dataService.funcionarios.any((f) => f.id == fId)
                        ? dataService.funcionarios.firstWhere((f) => f.id == fId).nome
                        : 'Vendedor Desconhecido';

                    return _buildCardColaborador(fNome, dados['total'], dados['itens'], df, mf, Icons.person);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabMotoboys(DataService dataService, ThemeData theme, DateFormat df, NumberFormat mf) {
    final entregas = dataService.entregas.where((e) {
      if (e.motoristaId == null || e.status != StatusEntrega.entregue) return false;
      if (_dataInicio != null && e.dataCriacao.isBefore(_dataInicio!)) return false;
      if (_dataFim != null && e.dataCriacao.isAfter(_dataFim!.add(const Duration(days: 1)))) return false;
      return true;
    }).toList();

    final Map<String, Map<String, dynamic>> metricas = {};

    for (final entrega in entregas) {
      final mId = entrega.motoristaId!;
      final motorista = dataService.motoristas.any((m) => m.id == mId) 
          ? dataService.motoristas.firstWhere((m) => m.id == mId) : null;
      
      double valorComissao = 0.0;
      if (motorista != null) {
        if (motorista.tipoComissao == 'Fixo por Entrega') {
          valorComissao = motorista.valorComissao;
        } else if (motorista.tipoComissao == 'Porcentagem') {
          valorComissao = (entrega.taxaEntrega ?? 0.0) * (motorista.valorComissao / 100);
        } else {
          // Diária costuma ser pago fora do cálculo por entrega, mas podemos somar aqui se for o caso
          valorComissao = motorista.valorComissao; // Simplificado
        }
      } else {
        valorComissao = entrega.taxaEntrega ?? 0.0; // Fallback: ganha a taxa integral
      }

      metricas.putIfAbsent(mId, () => {'total': 0.0, 'itens': []});
      metricas[mId]!['total'] += valorComissao;
      metricas[mId]!['itens'].add({
        'desc': 'Entrega: ${entrega.clienteNome}',
        'data': entrega.dataCriacao,
        'valor': valorComissao,
        'detalhe': entrega.bairro != null ? 'Bairro: ${entrega.bairro}' : null,
      });
    }

    final totalGeral = metricas.values.fold(0.0, (sum, item) => sum + item['total']);

    return Column(
      children: [
        _buildResumoTotal('Total Motoboys', totalGeral, mf),
        Expanded(
          child: metricas.isEmpty
              ? _buildEmptyState('Nenhuma comissão de motoboy encontrada')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: metricas.length,
                  itemBuilder: (context, index) {
                    final mId = metricas.keys.elementAt(index);
                    final dados = metricas[mId]!;
                    final mNome = dataService.motoristas.any((m) => m.id == mId)
                        ? dataService.motoristas.firstWhere((m) => m.id == mId).nome
                        : 'Motoboy Desconhecido';

                    return _buildCardColaborador(mNome, dados['total'], dados['itens'], df, mf, Icons.motorcycle);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildResumoTotal(String label, double total, NumberFormat mf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: Colors.orange.withOpacity(0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(mf.format(total), style: const TextStyle(color: Colors.orange, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCardColaborador(String nome, double total, List<dynamic> itens, DateFormat df, NumberFormat mf, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.2),
          child: Icon(icon, color: Colors.orange, size: 20),
        ),
        title: Text(nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        trailing: Text(mf.format(total), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        children: itens.map((item) => ListTile(
          dense: true,
          title: Text(item['desc'], style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text('${df.format(item['data'])}${item['detalhe'] != null ? " • ${item['detalhe']}" : ""}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: Text(mf.format(item['valor']), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
        )).toList(),
      ),
    );
  }

  Widget _buildDateTile(String label, DateTime? value, Function(DateTime) onSelected, DateFormat format) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final data = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (data != null) onSelected(data);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF181A1B), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.white54),
              const SizedBox(width: 8),
              Text(value == null ? label : format.format(value), style: TextStyle(color: value == null ? Colors.white54 : Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  List<Pedido> _filtrarPedidos(List<Pedido> pedidos) {
    return pedidos.where((p) => p.status == 'Concluído').toList();
  }

  List<ComissaoVendedor> _filtrarComissoesVenda(List<ComissaoVendedor> comissoes) {
    var resultado = comissoes;
    if (_dataInicio != null) resultado = resultado.where((c) => c.createdAt.isAfter(_dataInicio!.subtract(const Duration(days: 1)))).toList();
    if (_dataFim != null) resultado = resultado.where((c) => c.createdAt.isBefore(_dataFim!.add(const Duration(days: 1)))).toList();
    return resultado;
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.money_off, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/funcionario.dart';
import '../models/pedido.dart';
import '../models/comissao_vendedor.dart';
import '../theme.dart';
import '../widgets/sync_status_widget.dart';

class ComissoesPage extends StatefulWidget {
  const ComissoesPage({super.key});

  @override
  State<ComissoesPage> createState() => _ComissoesPageState();
}

class _ComissoesPageState extends State<ComissoesPage> {
  DateTime? _dataInicio;
  DateTime? _dataFim;
  Funcionario? _funcionarioFiltro;

  @override
  void dispose() {
    super.dispose();
  }

  List<Pedido> _filtrarPedidos(List<Pedido> pedidos) {
    var resultado = pedidos.where((p) => p.servicos.isNotEmpty && p.status == 'Concluído').toList();
    
    // Filtro por funcionário
    if (_funcionarioFiltro != null) {
      resultado = resultado.where((p) {
        return p.servicos.any((s) => s.funcionarioId == _funcionarioFiltro!.id);
      }).toList();
    }
    
    // Filtro por data
    if (_dataInicio != null) {
      resultado = resultado.where((p) => p.dataPedido.isAfter(_dataInicio!.subtract(const Duration(days: 1)))).toList();
    }
    if (_dataFim != null) {
      resultado = resultado.where((p) => p.dataPedido.isBefore(_dataFim!.add(const Duration(days: 1)))).toList();
    }
    
    return resultado;
  }

  List<ComissaoVendedor> _filtrarComissoesVenda(List<ComissaoVendedor> comissoes) {
    var resultado = comissoes;
    
    // Filtro por funcionário
    if (_funcionarioFiltro != null) {
      resultado = resultado.where((c) => c.funcionarioId == _funcionarioFiltro!.id).toList();
    }
    
    // Filtro por data
    if (_dataInicio != null) {
      resultado = resultado.where((c) => c.createdAt.isAfter(_dataInicio!.subtract(const Duration(days: 1)))).toList();
    }
    if (_dataFim != null) {
      resultado = resultado.where((c) => c.createdAt.isBefore(_dataFim!.add(const Duration(days: 1)))).toList();
    }
    
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formatoData = DateFormat('dd/MM/yyyy');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // 1. Filtrar dados
    final pedidos = _filtrarPedidos(dataService.pedidos);
    final comissoesVenda = _filtrarComissoesVenda(dataService.comissoesVendedores);

    // 2. Agrupar por funcionário
    final Map<String, Map<String, dynamic>> metricasPorFuncionario = {};

    // Processar serviços
    for (final pedido in pedidos) {
      for (final servico in pedido.servicos) {
        if (servico.funcionarioId != null && servico.valorComissao > 0) {
          final fId = servico.funcionarioId!;
          if (!metricasPorFuncionario.containsKey(fId)) {
            metricasPorFuncionario[fId] = {
              'total': 0.0,
              'servicos': <Map<String, dynamic>>[],
              'vendas': <ComissaoVendedor>[],
            };
          }
          metricasPorFuncionario[fId]!['total'] += servico.valorComissao;
          metricasPorFuncionario[fId]!['servicos'].add({
            'descricao': servico.descricao,
            'data': pedido.dataPedido,
            'valor': servico.valorComissao,
            'tipo': servico.tipoComissao,
            'porc': servico.porcentagemComissao,
          });
        }
      }
    }

    // Processar vendas (links)
    for (final com in comissoesVenda) {
      final fId = com.funcionarioId;
      if (!metricasPorFuncionario.containsKey(fId)) {
        metricasPorFuncionario[fId] = {
          'total': 0.0,
          'servicos': <Map<String, dynamic>>[],
          'vendas': <ComissaoVendedor>[],
        };
      }
      metricasPorFuncionario[fId]!['total'] += com.valorComissao;
      metricasPorFuncionario[fId]!['vendas'].add(com);
    }

    final totalGeral = metricasPorFuncionario.values.fold(0.0, (sum, item) => sum + item['total']);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Consulta de Comissões'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            const SyncStatusWidget(),
          ],
        ),
        body: Column(
          children: [
            // Filtros
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E).withOpacity(0.8),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Column(
                children: [
                  // Filtro por funcionário
                  DropdownButtonFormField<Funcionario?>(
                    value: _funcionarioFiltro,
                    decoration: InputDecoration(
                      labelText: 'Filtrar por Funcionário',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    dropdownColor: const Color(0xFF23272A),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem<Funcionario?>(
                        value: null,
                        child: Text('Todos os funcionários', style: TextStyle(color: Colors.white70)),
                      ),
                      ...dataService.funcionarios.where((f) => f.ativo).map((funcionario) {
                        return DropdownMenuItem(
                          value: funcionario,
                          child: Text(funcionario.nome),
                        );
                      }),
                    ],
                    onChanged: (funcionario) => setState(() => _funcionarioFiltro = funcionario),
                  ),
                  const SizedBox(height: 12),
                  // Filtro por data
                  Row(
                    children: [
                      _buildDateTile('Início', _dataInicio, (d) => setState(() => _dataInicio = d), formatoData),
                      const SizedBox(width: 8),
                      _buildDateTile('Fim', _dataFim, (d) => setState(() => _dataFim = d), formatoData),
                    ],
                  ),
                ],
              ),
            ),
            // Resumo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                border: Border(bottom: BorderSide(color: Colors.orange.withOpacity(0.3))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total de Comissões:', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(formatoMoeda.format(totalGeral), style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // Lista
            Expanded(
              child: metricasPorFuncionario.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: metricasPorFuncionario.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final fId = metricasPorFuncionario.keys.elementAt(index);
                        final dados = metricasPorFuncionario[fId]!;
                        final total = dados['total'] as double;
                        final servicos = dados['servicos'] as List<Map<String, dynamic>>;
                        final vendas = dados['vendas'] as List<ComissaoVendedor>;
                        
                        final fNome = dataService.funcionarios.any((f) => f.id == fId) 
                            ? dataService.funcionarios.firstWhere((f) => f.id == fId).nome
                            : (vendas.isNotEmpty ? vendas.first.funcionarioNome : 'Desconhecido');

                        return Card(
                          color: theme.cardTheme.color,
                          shape: theme.cardTheme.shape,
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withOpacity(0.2),
                              child: const Icon(Icons.person, color: Colors.orange),
                            ),
                            title: Text(fNome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('${servicos.length} servs, ${vendas.length} vendas', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            trailing: Text(formatoMoeda.format(total), style: const TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
                            children: [
                              if (servicos.isNotEmpty) _buildSectionHeader('Comissões de Serviços'),
                              ...servicos.map((s) => _buildItemTile(s['descricao'], s['data'], s['valor'], formatoData, formatoMoeda, sub: s['tipo'] == 'Porcentagem' ? '${s['porc'].toStringAsFixed(1).replaceAll('.', ',')}%' : null)),
                              if (vendas.isNotEmpty) _buildSectionHeader('Comissões de Vendas (Links)'),
                              ...vendas.map((v) => _buildItemTile('Venda ${v.pedidoNumero}', v.createdAt, v.valorComissao, formatoData, formatoMoeda, sub: '${v.percentualComissao.toStringAsFixed(1).replaceAll('.', ',')}%')),
                              const SizedBox(height: 16),
                            ],
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

  Widget _buildDateTile(String label, DateTime? value, Function(DateTime) onSelected, DateFormat format) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final data = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
          if (data != null) onSelected(data);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF181A1B), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Text(value == null ? label : format.format(value), style: TextStyle(color: value == null ? Colors.white54 : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildItemTile(String desc, DateTime date, double val, DateFormat df, NumberFormat mf, {String? sub}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(df.format(date), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(mf.format(val), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              if (sub != null) Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.money_off, size: 64, color: Colors.white.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('Nenhuma comissão encontrada', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../services/data_service.dart';
import '../models/cliente.dart';
import '../models/agendamento_servico.dart';
import '../models/pedido.dart';
import '../models/venda_balcao.dart';
import '../theme.dart';

class ClienteServicoDetalhesPage extends StatefulWidget {
  final Cliente cliente;

  const ClienteServicoDetalhesPage({super.key, required this.cliente});

  @override
  State<ClienteServicoDetalhesPage> createState() => _ClienteServicoDetalhesPageState();
}

class _ClienteServicoDetalhesPageState extends State<ClienteServicoDetalhesPage> {
  String _filtroPeriodo = 'Todos'; // 'Todos', '30 dias', '90 dias', '1 ano'
  String _filtroTipo = 'Todos'; // 'Todos', 'Serviços', 'Agendamentos', 'Vacinas'
  String _filtroStatus = 'Todos'; // 'Todos', 'Concluído', 'Pendente', etc.

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    final pedidosCliente = dataService.pedidos
        .where((p) => p.clienteId == widget.cliente.id && p.servicos.isNotEmpty)
        .toList();
    final agendamentosCliente = dataService.agendamentosServico
        .where((a) => a.clienteId == widget.cliente.id)
        .toList();
    final vendasBalcaoCliente = dataService.vendasBalcao
        .where((v) => v.clienteId == widget.cliente.id)
        .toList();

    // Aplicar filtros
    final agora = DateTime.now();
    DateTime? dataInicio;
    switch (_filtroPeriodo) {
      case '30 dias':
        dataInicio = agora.subtract(const Duration(days: 30));
        break;
      case '90 dias':
        dataInicio = agora.subtract(const Duration(days: 90));
        break;
      case '1 ano':
        dataInicio = agora.subtract(const Duration(days: 365));
        break;
    }

    var pedidosFiltrados = pedidosCliente;
    var agendamentosFiltrados = agendamentosCliente;
    var vendasBalcaoFiltradas = vendasBalcaoCliente;

    if (dataInicio != null) {
      pedidosFiltrados = pedidosFiltrados.where((p) => p.dataPedido.isAfter(dataInicio!)).toList();
      agendamentosFiltrados = agendamentosFiltrados.where((a) => a.dataAgendamento.isAfter(dataInicio!)).toList();
      vendasBalcaoFiltradas = vendasBalcaoFiltradas.where((v) => v.dataVenda.isAfter(dataInicio!)).toList();
    }

    if (_filtroStatus != 'Todos') {
      pedidosFiltrados = pedidosFiltrados.where((p) => p.status == _filtroStatus).toList();
      agendamentosFiltrados = agendamentosFiltrados.where((a) => a.status == _filtroStatus).toList();
      // Vendas balcão só têm "cancelado" como status negativo
      if (_filtroStatus == 'Cancelado') {
        vendasBalcaoFiltradas = vendasBalcaoFiltradas.where((v) => v.cancelado).toList();
      } else if (_filtroStatus == 'Concluído') {
        vendasBalcaoFiltradas = vendasBalcaoFiltradas.where((v) => !v.cancelado).toList();
      } else {
        vendasBalcaoFiltradas = [];
      }
    }

    // Separar vacinas
    final agendamentosVacinas = agendamentosFiltrados.where((a) {
      return (a.servicoId?.startsWith('vacina_') ?? false) ||
             (a.observacoes != null && a.observacoes!.toLowerCase().contains('aplicar')) ||
             a.materiais.any((m) => m.isVacina) ||
             (a.servico != null && a.servico!.materiais.any((m) => m.isVacina));
    }).toList();

    final agendamentosNormais = agendamentosFiltrados.where((a) => !agendamentosVacinas.contains(a)).toList();

    if (_filtroTipo == 'Vacinas') {
      agendamentosNormais.clear();
      pedidosFiltrados = pedidosFiltrados.where((p) => 
        p.materiaisConsumidos.any((m) => m.isVacina) ||
        p.servicos.any((s) => s.materiais.any((m) => m.isVacina))
      ).toList();
      vendasBalcaoFiltradas = []; // Geralmente vendas balcão não são vacinas
    } else if (_filtroTipo == 'Serviços') {
      vendasBalcaoFiltradas = [];
      agendamentosFiltrados.clear();
      agendamentosVacinas.clear();
    } else if (_filtroTipo == 'Vendas') {
      pedidosFiltrados = [];
      agendamentosFiltrados.clear();
      agendamentosVacinas.clear();
      agendamentosNormais.clear();
    } else if (_filtroTipo == 'Agendamentos') {
      pedidosFiltrados.clear();
      vendasBalcaoFiltradas = [];
    }

    // Ordenar por data (mais recentes primeiro)
    pedidosFiltrados.sort((a, b) => b.dataPedido.compareTo(a.dataPedido));
    agendamentosNormais.sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));
    agendamentosVacinas.sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));
    vendasBalcaoFiltradas.sort((a, b) => b.dataVenda.compareTo(a.dataVenda));

    // Calcular estatísticas
    final totalGasto = pedidosFiltrados.fold<double>(0.0, (sum, p) {
      return sum + p.servicos.fold(0.0, (s, item) => s + item.valor + item.valorAdicional);
    }) + agendamentosFiltrados.fold<double>(0.0, (sum, a) {
      return sum + (a.servico?.precoTotal ?? 0.0) + (a.valorTaxiDog ?? 0.0);
    }) + vendasBalcaoFiltradas.fold<double>(0.0, (sum, v) {
      return sum + (v.cancelado ? 0.0 : v.valorTotal);
    });

    final totalItens = pedidosFiltrados.length + agendamentosFiltrados.length + vendasBalcaoFiltradas.length;
    final mediaGasto = totalItens > 0 ? totalGasto / totalItens : 0.0;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formatoData = DateFormat('dd/MM/yyyy');
    final formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.cliente.nome),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _mostrarDialogoFiltros(context),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card com foto e informações principais
              _buildCardCliente(widget.cliente, colorScheme, formatoData),
              const SizedBox(height: 24),
              
              // Estatísticas
              _buildEstatisticas(totalGasto, totalItens, mediaGasto, formatoMoeda, colorScheme),
              const SizedBox(height: 24),

              // Filtros ativos
              if (_filtroPeriodo != 'Todos' || _filtroTipo != 'Todos' || _filtroStatus != 'Todos')
                _buildFiltrosAtivos(),
              const SizedBox(height: 24),

              // Seção de Vacinas (se houver)
              if (isModuloPet && agendamentosVacinas.isNotEmpty) ...[
                _buildSecaoVacinas(agendamentosVacinas, formatoData, formatoDataHora, formatoMoeda, colorScheme),
              ],

              // Histórico de Serviços
              _buildHistoricoCompleto(
                pedidosFiltrados,
                vendasBalcaoFiltradas,
                agendamentosNormais,
                formatoData,
                formatoDataHora,
                formatoMoeda,
                colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardCliente(Cliente cliente, ColorScheme colorScheme, DateFormat formatoData) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: colorScheme.primary.withOpacity(0.2),
              backgroundImage: cliente.fotoPath != null && File(cliente.fotoPath!).existsSync()
                  ? FileImage(File(cliente.fotoPath!))
                  : null,
              child: cliente.fotoPath == null || !File(cliente.fotoPath!).existsSync()
                  ? Icon(Icons.person, size: 50, color: colorScheme.primary)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              cliente.nome,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (cliente.telefone.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    cliente.telefone,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                  ),
                ],
              ),
            if (cliente.email != null && cliente.email!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.email, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    cliente.email!,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    'Cadastrado em ${formatoData.format(cliente.createdAt)}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstatisticas(double totalGasto, int totalItens, double mediaGasto, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Estatísticas',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildEstatisticaItem(
                    'Total Gasto',
                    formatoMoeda.format(totalGasto),
                    Icons.attach_money,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEstatisticaItem(
                    'Total Itens',
                    totalItens.toString(),
                    Icons.work,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildEstatisticaItem(
                    'Média por Item',
                    formatoMoeda.format(mediaGasto),
                    Icons.trending_up,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEstatisticaItem(
                    'Frequência',
                    totalItens > 0 ? '${(totalItens / 30).toStringAsFixed(1)}/mês' : '0/mês',
                    Icons.calendar_today,
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

  Widget _buildEstatisticaItem(String label, String valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosAtivos() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_filtroPeriodo != 'Todos')
          Chip(
            label: Text('Período: $_filtroPeriodo'),
            onDeleted: () => setState(() => _filtroPeriodo = 'Todos'),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        if (_filtroTipo != 'Todos')
          Chip(
            label: Text('Tipo: $_filtroTipo'),
            onDeleted: () => setState(() => _filtroTipo = 'Todos'),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        if (_filtroStatus != 'Todos')
          Chip(
            label: Text('Status: $_filtroStatus'),
            onDeleted: () => setState(() => _filtroStatus = 'Todos'),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
      ],
    );
  }

  Widget _buildSecaoVacinas(List<AgendamentoServico> vacinas, DateFormat formatoData, DateFormat formatoDataHora, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vaccines, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Histórico de Vacinas',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${vacinas.length} vacina${vacinas.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...vacinas.map((agendamento) => _buildCardVacina(agendamento, formatoData, formatoDataHora, colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVacina(AgendamentoServico agendamento, DateFormat formatoData, DateFormat formatoDataHora, ColorScheme colorScheme) {
    final todosMateriais = [
      ...agendamento.materiais,
      if (agendamento.servico != null) ...agendamento.servico!.materiais,
    ];
    final vacinas = todosMateriais.where((m) => m.isVacina).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vaccines, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatoDataHora.format(agendamento.dataAgendamento),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCorStatusAgendamento(agendamento.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  agendamento.status,
                  style: TextStyle(
                    color: _getCorStatusAgendamento(agendamento.status),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...vacinas.map((vacina) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.medical_services, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            vacina.produtoNome,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${vacina.quantidade.toStringAsFixed(vacina.quantidade % 1 == 0 ? 0 : 2)}${vacina.unidade != null ? ' ${vacina.unidade}' : ''}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                    if (vacina.dataProximaAplicacao != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Próxima aplicação: ${formatoData.format(vacina.dataProximaAplicacao!)}',
                            style: TextStyle(
                              color: Colors.green.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (vacina.intervaloDias != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Intervalo: ${vacina.intervaloDias} dias',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              )),
          if (agendamento.pet != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.pets, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  'Pet: ${agendamento.pet!.nome}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoricoCompleto(List<Pedido> pedidos, List<VendaBalcao> vendas, List<AgendamentoServico> agendamentos, DateFormat formatoData, DateFormat formatoDataHora, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    // Combinar e ordenar por data
    final todosItens = <Map<String, dynamic>>[];
    
    for (final pedido in pedidos) {
      todosItens.add({
        'tipo': 'pedido',
        'data': pedido.dataPedido,
        'item': pedido,
      });
    }

    for (final venda in vendas) {
      todosItens.add({
        'tipo': 'venda',
        'data': venda.dataVenda,
        'item': venda,
      });
    }
    
    for (final agendamento in agendamentos) {
      todosItens.add({
        'tipo': 'agendamento',
        'data': agendamento.dataAgendamento,
        'item': agendamento,
      });
    }
    
    todosItens.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));

    // Agrupar por data
    final itensPorData = <String, List<Map<String, dynamic>>>{};
    for (final item in todosItens) {
      final dataKey = formatoData.format(item['data'] as DateTime);
      itensPorData.putIfAbsent(dataKey, () => []).add(item);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Histórico Completo',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${todosItens.length} item${todosItens.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (todosItens.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Nenhum serviço encontrado',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                ),
              )
            else
              ...itensPorData.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...entry.value.map((item) {
                      if (item['tipo'] == 'pedido') {
                        return _buildCardPedido(item['item'] as Pedido, formatoDataHora, formatoMoeda, colorScheme);
                      } else if (item['tipo'] == 'venda') {
                        return _buildCardVendaBalcao(item['item'] as VendaBalcao, formatoDataHora, formatoMoeda, colorScheme);
                      } else {
                        return _buildCardAgendamento(item['item'] as AgendamentoServico, formatoDataHora, formatoMoeda, colorScheme);
                      }
                    }),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPedido(Pedido pedido, DateFormat formatoDataHora, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    final totalServicos = pedido.servicos.fold(0.0, (sum, item) => sum + item.valor + item.valorAdicional);
    final totalTaxiDog = pedido.servicos.fold(0.0, (sum, s) => sum + (s.valorTaxiDog ?? 0.0));
    final totalGeral = totalServicos + totalTaxiDog;

    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatoDataHora.format(pedido.dataPedido),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                formatoMoeda.format(totalGeral),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (pedido.numero.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Nº ${pedido.numero}',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          ...pedido.servicos.map((servico) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            servico.descricao,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          formatoMoeda.format(servico.valor + servico.valorAdicional),
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                    if (servico.descricaoAdicional != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          servico.descricaoAdicional!,
                          style: TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ),
                    ],
                    if (servico.tipoEntrega != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Row(
                          children: [
                            Icon(
                              servico.tipoEntrega == 'Taxi Dog' ? Icons.local_taxi : Icons.directions_walk,
                              size: 12,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${servico.tipoEntrega}${servico.valorTaxiDog != null && servico.valorTaxiDog! > 0 ? ' - ${formatoMoeda.format(servico.valorTaxiDog!)}' : ''}',
                              style: TextStyle(color: Colors.orange, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (servico.duracaoMinutos != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Row(
                          children: [
                            const Icon(Icons.timer, size: 12, color: Colors.white60),
                            const SizedBox(width: 4),
                            Text(
                              'Duração: ${servico.duracaoMinutos} min',
                              style: TextStyle(color: Colors.white60, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              )),
          if (pedido.materiaisConsumidos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.inventory, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Materiais:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...pedido.materiaisConsumidos.map((material) => Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        material.isVacina ? Icons.vaccines : Icons.inventory_2,
                        size: 14,
                        color: material.isVacina ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${material.produtoNome} - ${material.quantidade.toStringAsFixed(material.quantidade % 1 == 0 ? 0 : 2)}${material.unidade != null ? ' ${material.unidade}' : ''}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ),
                      if (material.precoCusto != null && material.precoCusto! > 0)
                        Text(
                          'Custo: ${formatoMoeda.format(material.precoCusto! * material.quantidade)}',
                          style: TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                    ],
                  ),
                )),
          ],
          if (pedido.pagamentos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.payment, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Pagamentos:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...pedido.pagamentos.map((pagamento) => Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        pagamento.recebido ? Icons.check_circle : Icons.pending,
                        size: 14,
                        color: pagamento.recebido ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${pagamento.tipo.toString().split('.').last} - ${formatoMoeda.format(pagamento.valor)}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (pagamento.recebido && pagamento.dataRecebimento != null)
                        Text(
                          formatoDataHora.format(pagamento.dataRecebimento!),
                          style: TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                    ],
                  ),
                )),
          ],
          if (pedido.status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getCorStatus(pedido.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pedido.status,
                style: TextStyle(
                  color: _getCorStatus(pedido.status),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardVendaBalcao(VendaBalcao venda, DateFormat formatoDataHora, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatoDataHora.format(venda.dataVenda),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                formatoMoeda.format(venda.valorTotal),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nº ${venda.numero}',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (venda.cancelado)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CANCELADO',
                    style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...venda.itens.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart, size: 14, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.quantidade}x ${item.nome}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(item.precoUnitario * item.quantidade),
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.payment, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'Pagamento: ${venda.tipoPagamento.toString().split('.').last}',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardAgendamento(AgendamentoServico agendamento, DateFormat formatoDataHora, NumberFormat formatoMoeda, ColorScheme colorScheme) {
    final servicoNome = agendamento.servico?.nome ?? (agendamento.observacoes ?? 'Agendamento');
    final todosMateriais = [
      ...agendamento.materiais,
      if (agendamento.servico != null) ...agendamento.servico!.materiais,
    ];
    final valorTotal = (agendamento.servico?.precoTotal ?? 0.0) + (agendamento.valorTaxiDog ?? 0.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatoDataHora.format(agendamento.dataAgendamento),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (valorTotal > 0)
                Text(
                  formatoMoeda.format(valorTotal),
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          if (agendamento.numero.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Nº ${agendamento.numero}',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.build, size: 14, color: Colors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  servicoNome,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCorStatusAgendamento(agendamento.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  agendamento.status,
                  style: TextStyle(
                    color: _getCorStatusAgendamento(agendamento.status),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (agendamento.pet != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.pets, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  agendamento.pet!.nome,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ],
          if (agendamento.tipoEntrega != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  agendamento.tipoEntrega == 'Taxi Dog' ? Icons.local_taxi : Icons.directions_walk,
                  size: 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  '${agendamento.tipoEntrega}${agendamento.valorTaxiDog != null && agendamento.valorTaxiDog! > 0 ? ' - ${formatoMoeda.format(agendamento.valorTaxiDog!)}' : ''}',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ],
            ),
          ],
          if (agendamento.duracaoMinutos > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.timer, size: 14, color: Colors.white60),
                const SizedBox(width: 6),
                Text(
                  'Duração: ${agendamento.duracaoMinutos} min',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ],
          if (todosMateriais.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.inventory, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Materiais:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...todosMateriais.map((material) => Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        material.isVacina ? Icons.vaccines : Icons.inventory_2,
                        size: 14,
                        color: material.isVacina ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${material.produtoNome} - ${material.quantidade.toStringAsFixed(material.quantidade % 1 == 0 ? 0 : 2)}${material.unidade != null ? ' ${material.unidade}' : ''}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ),
                      if (material.precoCusto != null && material.precoCusto! > 0)
                        Text(
                          'Custo: ${formatoMoeda.format(material.precoCusto! * material.quantidade)}',
                          style: TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                    ],
                  ),
                )),
          ],
          if (agendamento.observacoes != null && agendamento.observacoes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note, size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      agendamento.observacoes!,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _mostrarDialogoFiltros(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Filtros', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Período:', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ...['Todos', '30 dias', '90 dias', '1 ano'].map((periodo) => RadioListTile<String>(
                    title: Text(periodo, style: const TextStyle(color: Colors.white)),
                    value: periodo,
                    groupValue: _filtroPeriodo,
                    onChanged: (value) => setState(() => _filtroPeriodo = value!),
                  )),
              const SizedBox(height: 16),
              const Text('Tipo:', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ...['Todos', 'Vendas', 'Serviços', 'Agendamentos', if (isModuloPet) 'Vacinas'].map((tipo) => RadioListTile<String>(
                    title: Text(tipo, style: const TextStyle(color: Colors.white)),
                    value: tipo,
                    groupValue: _filtroTipo,
                    onChanged: (value) => setState(() => _filtroTipo = value!),
                  )),
              const SizedBox(height: 16),
              const Text('Status:', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              ...['Todos', 'Concluído', 'Pendente', 'Em Andamento', 'Cancelado'].map((status) => RadioListTile<String>(
                    title: Text(status, style: const TextStyle(color: Colors.white)),
                    value: status,
                    groupValue: _filtroStatus,
                    onChanged: (value) => setState(() => _filtroStatus = value!),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Color _getCorStatusAgendamento(String status) {
    switch (status) {
      case 'Agendado':
        return Colors.blue;
      case 'Em Andamento':
        return Colors.orange;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Em Andamento':
        return Colors.blue;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

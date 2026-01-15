import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import '../models/entrega.dart';
import '../services/data_service.dart';
import '../theme.dart';
import 'entrega_detalhes_page.dart';
import 'taxas_entrega_page.dart';

class EntregasPage extends StatefulWidget {
  const EntregasPage({super.key});

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  String? _motoristaFiltro;
  DateTime? _dataFiltro;

  final List<StatusEntrega> _statusTabs = [
    StatusEntrega.aguardando,
    StatusEntrega.entregue,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length + 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final entregas = _filtrarEntregas(dataService.entregas);
    final estatisticas = _calcularEstatisticas(dataService.entregas);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Controle de Entregas'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: [
            // Gerenciar taxas de entrega
            IconButton(
              icon: const Icon(Icons.local_shipping),
              tooltip: 'Gerenciar Taxas de Entrega',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TaxasEntregaPage(),
                  ),
                );
              },
            ),
            // Filtro por data
            IconButton(
              icon: Icon(
                Icons.calendar_today,
                color: _dataFiltro != null
                    ? Colors.greenAccent
                    : Theme.of(context).colorScheme.onPrimary,
              ),
              tooltip: 'Filtrar por data',
              onPressed: () => _selecionarData(context),
            ),
            // Busca
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar entregas',
              onPressed: () => _mostrarBusca(context),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.greenAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                const Tab(text: 'TODAS'),
                ..._statusTabs.map(
                  (status) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(status.nome.toUpperCase()),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getCorStatus(status),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_contarPorStatus(dataService.entregas, status)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // Dashboard de estatísticas
            _buildDashboard(estatisticas),

            // Indicador de filtros ativos
            if (_termoBusca.isNotEmpty ||
                _dataFiltro != null ||
                _motoristaFiltro != null)
              _buildFiltrosAtivos(),

            // Lista de entregas
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab "TODAS"
                  _buildListaEntregas(entregas, dataService),
                  // Tabs por status
                  ..._statusTabs.map((status) {
                    final entregasFiltradas = entregas
                        .where((e) => e.status == status)
                        .toList();
                    return _buildListaEntregas(entregasFiltradas, dataService);
                  }),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _criarNovaEntrega(context, dataService),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Nova Entrega'),
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> stats) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: _buildStatCard(
                  'Aguardando',
                  stats['aguardando'].toString(),
                  Colors.orange,
                  Icons.hourglass_empty,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Em Rota',
                  stats['emTransito'].toString(),
                  Colors.blue.shade800,
                  Icons.local_shipping,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Entregues Hoje',
                  stats['entreguesHoje'].toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Atrasadas',
                  stats['atrasadas'].toString(),
                  Colors.red,
                  Icons.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Taxa Sucesso',
                  '${stats['taxaSucesso']}%',
                  Colors.teal,
                  Icons.trending_up,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Total Mês',
                  stats['totalMes'].toString(),
                  Colors.purple,
                  Icons.calendar_month,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosAtivos() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.filter_alt, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                if (_termoBusca.isNotEmpty)
                  Chip(
                    label: Text('Busca: "$_termoBusca"'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() {
                      _termoBusca = '';
                      _buscaController.clear();
                    }),
                    backgroundColor: Colors.blue.withOpacity(0.3),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                if (_dataFiltro != null)
                  Chip(
                    label: Text(
                      'Data: ${_dataFiltro!.day}/${_dataFiltro!.month}/${_dataFiltro!.year}',
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _dataFiltro = null),
                    backgroundColor: Colors.green.withOpacity(0.3),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                if (_motoristaFiltro != null)
                  Chip(
                    label: Text('Motorista: $_motoristaFiltro'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _motoristaFiltro = null),
                    backgroundColor: Colors.purple.withOpacity(0.3),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _termoBusca = '';
              _buscaController.clear();
              _dataFiltro = null;
              _motoristaFiltro = null;
            }),
            child: const Text(
              'Limpar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaEntregas(List<Entrega> entregas, DataService dataService) {
    if (entregas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 88,
              color: Colors.blue.shade900,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma entrega encontrada',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: entregas.length,
      itemBuilder: (context, index) {
        final entrega = entregas[index];
        return _buildCardEntrega(context, entrega, dataService);
      },
    );
  }

  Widget _buildCardEntrega(
    BuildContext context,
    Entrega entrega,
    DataService dataService,
  ) {
    final corStatus = _getCorStatus(entrega.status);
    final isAtrasada = entrega.estaAtrasada;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAtrasada
              ? [Colors.red.shade900, Colors.red.shade800]
              : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: isAtrasada ? Border.all(color: Colors.red, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _abrirDetalhes(context, entrega),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  // Ícone do status
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: corStatus.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIconeStatus(entrega.status),
                      color: corStatus,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Pedido e Cliente
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entrega.pedidoNumero ??
                                  'Entrega #${entrega.id.substring(0, 6)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (isAtrasada) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ATRASADA',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.yellowAccent.shade200,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.yellowAccent.shade100.withOpacity(
                                  0.6,
                                ),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            entrega.clienteNome,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Telefone do cliente e observações da entrega
                        Row(
                          children: [
                            if (entrega.clienteTelefone != null) ...[
                              Icon(
                                Icons.phone,
                                color: Colors.greenAccent,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                entrega.clienteTelefone!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],

                            if (entrega.observacoes != null &&
                                entrega.observacoes!.isNotEmpty)
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.notes,
                                      color: Colors.white70,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        entrega.observacoes!,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Badge de status com popup para alterar
                  _buildStatusBadge(entrega, dataService),
                ],
              ),

              const SizedBox(height: 12),

              // Endereço
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.white.withOpacity(0.6),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entrega.enderecoCompleto,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Informações adicionais
              Row(
                children: [
                  // Motorista
                  if (entrega.motoristaNome != null)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            color: Colors.blue.withOpacity(0.8),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entrega.motoristaNome!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Ordem na rota
                  if (entrega.ordemRota != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Rota: ${entrega.ordemRota}º',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(width: 8),

                  // Tipo de entrega
                  if (entrega.tipoEntrega != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getCorTipoEntrega(entrega.tipoEntrega!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entrega.tipoEntrega!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const Spacer(),

                  // Data previsão
                  if (entrega.dataPrevisao != null)
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          color: isAtrasada ? Colors.red : Colors.white54,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatarData(entrega.dataPrevisao!),
                          style: TextStyle(
                            color: isAtrasada ? Colors.red : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              // Ações rápidas
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Ligar para cliente
                  if (entrega.clienteTelefone != null)
                    IconButton(
                      icon: const Icon(Icons.phone, size: 20),
                      color: Colors.greenAccent,
                      tooltip: 'Ligar para cliente',
                      onPressed: () => _ligarCliente(entrega.clienteTelefone!),
                    ),

                  // Abrir no Maps
                  IconButton(
                    icon: const Icon(Icons.map, size: 20),
                    color: Colors.blue,
                    tooltip: 'Abrir no mapa',
                    onPressed: () => _abrirMapa(entrega),
                  ),

                  // Ver detalhes
                  TextButton.icon(
                    onPressed: () => _abrirDetalhes(context, entrega),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Detalhes'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Entrega entrega, DataService dataService) {
    final proximos = _getProximosStatus(entrega);

    return PopupMenuButton<StatusEntrega>(
      onSelected: (novoStatus) {
        _alterarStatus(entrega, novoStatus, dataService);
      },
      enabled: proximos.isNotEmpty,
      itemBuilder: (context) => proximos
          .map(
            (status) => PopupMenuItem(
              value: status,
              child: Row(
                children: [
                  Icon(
                    _getIconeStatus(status),
                    color: _getCorStatus(status),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(status.nome),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getCorStatus(entrega.status),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entrega.status.nome,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (proximos.isNotEmpty) ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  List<StatusEntrega> _getProximosStatus(Entrega entrega) {
    return StatusEntrega.values
        .where((s) => entrega.podeAlterarPara(s))
        .toList();
  }

  void _alterarStatus(
    Entrega entrega,
    StatusEntrega novoStatus,
    DataService dataService,
  ) {
    // Criar evento no histórico
    final evento = EventoEntrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dataHora: DateTime.now(),
      status: novoStatus,
      descricao: 'Status alterado para ${novoStatus.nome}',
    );

    // Atualizar entrega
    final entregaAtualizada = entrega
        .adicionarEvento(evento)
        .copyWith(
          dataEntrega: novoStatus == StatusEntrega.entregue
              ? DateTime.now()
              : null,
        );

    dataService.updateEntrega(entregaAtualizada);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_getIconeStatus(novoStatus), color: Colors.white),
            const SizedBox(width: 10),
            Text('Status alterado para "${novoStatus.nome}"'),
          ],
        ),
        backgroundColor: _getCorStatus(novoStatus),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Entrega> _filtrarEntregas(List<Entrega> entregas) {
    var resultado = entregas.toList();

    // Filtro por busca
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.toLowerCase();
      resultado = resultado.where((e) {
        return e.clienteNome.toLowerCase().contains(termo) ||
            e.pedidoNumero?.toLowerCase().contains(termo) == true ||
            e.enderecoEntrega.toLowerCase().contains(termo) ||
            e.motoristaNome?.toLowerCase().contains(termo) == true ||
            e.bairro?.toLowerCase().contains(termo) == true;
      }).toList();
    }

    // Filtro por data
    if (_dataFiltro != null) {
      resultado = resultado.where((e) {
        final dataEntrega = e.dataPrevisao ?? e.dataCriacao;
        return dataEntrega.year == _dataFiltro!.year &&
            dataEntrega.month == _dataFiltro!.month &&
            dataEntrega.day == _dataFiltro!.day;
      }).toList();
    }

    // Filtro por motorista
    if (_motoristaFiltro != null) {
      resultado = resultado
          .where((e) => e.motoristaNome == _motoristaFiltro)
          .toList();
    }

    // Ordenar por prioridade: atrasadas primeiro, depois por data
    resultado.sort((a, b) {
      if (a.estaAtrasada && !b.estaAtrasada) return -1;
      if (!a.estaAtrasada && b.estaAtrasada) return 1;
      return (a.dataPrevisao ?? a.dataCriacao).compareTo(
        b.dataPrevisao ?? b.dataCriacao,
      );
    });

    return resultado;
  }

  Map<String, dynamic> _calcularEstatisticas(List<Entrega> entregas) {
    final hoje = DateTime.now();
    final inicioMes = DateTime(hoje.year, hoje.month, 1);

    final entreguesHoje = entregas.where((e) {
      return e.status == StatusEntrega.entregue &&
          e.dataEntrega != null &&
          e.dataEntrega!.year == hoje.year &&
          e.dataEntrega!.month == hoje.month &&
          e.dataEntrega!.day == hoje.day;
    }).length;

    final entreguesMes = entregas.where((e) {
      return e.status == StatusEntrega.entregue &&
          e.dataEntrega != null &&
          e.dataEntrega!.isAfter(inicioMes);
    }).length;

    final totalMes = entregas.where((e) {
      return e.dataCriacao.isAfter(inicioMes);
    }).length;

    final taxaSucesso = totalMes > 0
        ? (entreguesMes / totalMes * 100).round()
        : 0;

    return {
      'aguardando': entregas
          .where((e) => e.status == StatusEntrega.aguardando)
          .length,
      'entregue': entregas
          .where((e) => e.status == StatusEntrega.entregue)
          .length,
      'entreguesHoje': entreguesHoje,
      'atrasadas': entregas.where((e) => e.estaAtrasada).length,
      'taxaSucesso': taxaSucesso,
      'totalMes': totalMes,
    };
  }

  int _contarPorStatus(List<Entrega> entregas, StatusEntrega status) {
    return entregas.where((e) => e.status == status).length;
  }

  void _selecionarData(BuildContext context) async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataFiltro ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.greenAccent,
              surface: Color(0xFF1E1E2E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (data != null) {
      setState(() {
        _dataFiltro = data;
      });
    }
  }

  void _mostrarBusca(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Buscar Entregas',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _buscaController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Cliente, pedido, endereço, bairro...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _buscaController.clear();
              setState(() => _termoBusca = '');
              Navigator.pop(context);
            },
            child: const Text(
              'Limpar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _termoBusca = _buscaController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  void _criarNovaEntrega(BuildContext context, DataService dataService) {
    // Mostrar diálogo para selecionar pedido ou criar entrega avulsa
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Criar Nova Entrega',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long, color: Colors.blue),
              ),
              title: const Text(
                'A partir de um Pedido',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Vincular entrega a um pedido existente',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.pop(context);
                _selecionarPedidoParaEntrega(context, dataService);
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_location, color: Colors.green),
              ),
              title: const Text(
                'Entrega Avulsa',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Criar entrega sem pedido vinculado',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                Navigator.pop(context);
                _criarEntregaAvulsa(context, dataService);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selecionarPedidoParaEntrega(
    BuildContext context,
    DataService dataService,
  ) {
    final pedidosSemEntrega = dataService.pedidos.where((p) {
      return !dataService.entregas.any((e) => e.pedidoId == p.id);
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Selecionar Pedido',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: pedidosSemEntrega.isEmpty
                  ? Center(
                      child: Text(
                        'Todos os pedidos já possuem entrega',
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: pedidosSemEntrega.length,
                      itemBuilder: (context, index) {
                        final pedido = pedidosSemEntrega[index];
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.blue,
                            ),
                          ),
                          title: Text(
                            pedido.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            pedido.clienteNome ?? 'Cliente não informado',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                          trailing: Text(
                            'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _criarEntregaDePedido(context, pedido, dataService);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _criarEntregaDePedido(
    BuildContext context,
    dynamic pedido,
    DataService dataService,
  ) {
    // Buscar cliente do pedido — usar somente se houver correspondência
    Cliente? cliente;
    if (pedido.clienteId != null) {
      final encontrados = dataService.clientes
          .where((c) => c.id == pedido.clienteId)
          .toList();
      if (encontrados.isNotEmpty) cliente = encontrados.first;
    }

    // Montar endereço completo do cliente (endereço + número)
    String? enderecoCompleto;
    if (cliente?.endereco != null) {
      enderecoCompleto = cliente!.endereco!;
      if (cliente.numero != null && cliente.numero!.isNotEmpty) {
        enderecoCompleto += ', ${cliente.numero}';
      }
    }

    final novaEntrega = Entrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: pedido.id,
      pedidoNumero: pedido.numero,
      clienteNome: cliente?.nome ?? pedido.clienteNome ?? 'Cliente',
      clienteTelefone: cliente?.telefone ?? pedido.clienteTelefone,
      enderecoEntrega:
          enderecoCompleto ??
          pedido.clienteEndereco ??
          'Endereço não informado',
      complemento: cliente?.complemento,
      bairro: cliente?.bairro,
      cidade: cliente?.cidade,
      cep: cliente?.cep,
      pontoReferencia: cliente?.pontoReferencia,
      dataCriacao: DateTime.now(),
      dataPrevisao: DateTime.now().add(const Duration(days: 1)),
      quantidadeVolumes: pedido.quantidadeItens,
      historico: [
        EventoEntrega(
          id: '1',
          dataHora: DateTime.now(),
          status: StatusEntrega.aguardando,
          descricao: 'Entrega criada a partir do pedido ${pedido.numero}',
        ),
      ],
    );

    dataService.addEntrega(novaEntrega);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text('Entrega criada para ${pedido.numero}'),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _criarEntregaAvulsa(BuildContext context, DataService dataService) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EntregaDetalhesPage(entrega: null),
      ),
    );
  }

  void _abrirDetalhes(BuildContext context, Entrega entrega) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntregaDetalhesPage(entrega: entrega),
      ),
    );
  }

  void _ligarCliente(String telefone) {
    // Implementar chamada
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ligar para: $telefone'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _abrirMapa(Entrega entrega) {
    // Implementar abertura no mapa
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Abrir mapa: ${entrega.enderecoEntrega}'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
  }

  Color _getCorStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Colors.orange;
      case StatusEntrega.entregue:
        return Colors.green;
    }
  }

  IconData _getIconeStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Icons.hourglass_empty;
      case StatusEntrega.entregue:
        return Icons.done_all;
    }
  }

  Color _getCorTipoEntrega(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'expressa':
        return Colors.red;
      case 'agendada':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

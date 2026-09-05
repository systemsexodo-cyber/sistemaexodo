import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import '../models/entrega.dart';
import '../services/data_service.dart';
import '../theme.dart';
import 'entrega_detalhes_page.dart';
import 'taxas_entrega_page.dart';
import '../widgets/sync_status_widget.dart';
import 'romaneios_page.dart';
import '../models/romaneio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';


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
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  bool _apenasAtrasadas = false;

  final List<StatusEntrega> _statusTabs = [
    StatusEntrega.aguardando,
    StatusEntrega.romaneioCriado,
    StatusEntrega.emEntrega,
    StatusEntrega.entregue,
    StatusEntrega.cancelado,
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
            // Atalho para Romaneios
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const RomaneiosPage()),
                  );
                },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Ir para Romaneios'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
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

            // Busca
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar entregas',
              onPressed: () => _mostrarBusca(context),
            ),
            const SyncStatusWidget(),

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

            // Filtro de Data
            _buildFiltroData(),

            // Indicador de filtros ativos
            if (_termoBusca.isNotEmpty ||
                _dataInicioFiltro != null ||
                _dataFimFiltro != null ||
                _motoristaFiltro != null ||
                _apenasAtrasadas)
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
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildStatChip(
            'Aguardando', 
            stats['aguardando'].toString(), 
            Colors.orange, 
            Icons.hourglass_empty,
            onTap: () => _tabController.animateTo(1),
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            'Em Rota', 
            stats['emEntrega'].toString(), 
            Colors.deepPurple, 
            Icons.local_shipping,
            onTap: () => _tabController.animateTo(3), // Em Entrega é o index 3 (Todas=0, Aguardando=1, Romaneio=2, Em Entrega=3)
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            'Entregues Hoje', 
            stats['entreguesHoje'].toString(), 
            Colors.green, 
            Icons.check_circle,
            onTap: () => _tabController.animateTo(4), // Entregue é o index 4
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            'Atrasadas', 
            stats['atrasadas'].toString(), 
            Colors.red, 
            Icons.warning_amber_rounded,
            onTap: () {
              setState(() {
                _apenasAtrasadas = true;
                _tabController.animateTo(0); // Volta para "TODAS" para ver todas as atrasadas
              });
            },
          ),
          const SizedBox(width: 8),
          _buildStatChip('Taxa Sucesso', '${stats['taxaSucesso']}%', Colors.teal, Icons.trending_up),
          const SizedBox(width: 8),
          _buildStatChip('Total Mês', stats['totalMes'].toString(), Colors.purple, Icons.calendar_month),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String valor, Color cor, IconData icone, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withOpacity(0.35), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 18),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: TextStyle(
                    color: cor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
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
                if (_dataInicioFiltro != null || _dataFimFiltro != null)
                  Chip(
                    label: Text(
                      'Período: ${_dataInicioFiltro != null ? DateFormat('dd/MM').format(_dataInicioFiltro!) : "?"} - ${_dataFimFiltro != null ? DateFormat('dd/MM').format(_dataFimFiltro!) : "?"}',
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() {
                      _dataInicioFiltro = null;
                      _dataFimFiltro = null;
                    }),
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
                if (_apenasAtrasadas)
                  Chip(
                    label: const Text('Atrasadas'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _apenasAtrasadas = false),
                    backgroundColor: Colors.red.withOpacity(0.3),
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
              _dataInicioFiltro = null;
              _dataFimFiltro = null;
              _motoristaFiltro = null;
              _apenasAtrasadas = false;
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
    final accentColor = isAtrasada ? Colors.red : corStatus;

    // Romaneios que incluem este pedido
    final romaneiosVinculados = dataService.romaneios
        .where((r) => r.entregaIds.contains(entrega.pedidoId))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2535),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _abrirDetalhes(context, entrega),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Linha 1: Número + badge status + badge atrasada ──
              Row(
                children: [
                  // Ícone status
                  Icon(_getIconeStatus(entrega.status), color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  // Número do pedido
                  Text(
                    entrega.pedidoNumero ?? 'Entrega #${entrega.id.substring(0, 6)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (isAtrasada) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('ATRASADA',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const Spacer(),
                  // Data de criação
                  Text(
                    _formatarDataHora(entrega.dataCriacao),
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── Linha 2: Nome do cliente + badge status ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      entrega.clienteNome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildStatusBadge(entrega, dataService),
                ],
              ),

              // ── Linha 3: Telefone ──
              if (entrega.clienteTelefone != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: Colors.greenAccent, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        entrega.clienteTelefone!,
                        style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // ── Linha 4: Endereço ──
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.white.withOpacity(0.4), size: 15),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      entrega.enderecoCompleto,
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // ── Linha 5: Motorista / Tipo / Rota / Romaneios ──
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (entrega.motoristaNome != null)
                      _buildTag(Icons.person, entrega.motoristaNome!, Colors.blue),
                    if (entrega.tipoEntrega != null)
                      _buildTag(Icons.local_shipping, entrega.tipoEntrega!, _getCorTipoEntrega(entrega.tipoEntrega!)),
                    if (entrega.ordemRota != null)
                      _buildTag(Icons.route, 'Rota ${entrega.ordemRota}º', Colors.purple),
                    if (entrega.dataPrevisao != null)
                      _buildTag(
                        Icons.schedule,
                        _formatarDataHora(entrega.dataPrevisao!),
                        isAtrasada ? Colors.red : Colors.white38,
                      ),
                    ...romaneiosVinculados.map((r) {
                      final isEntregueNoRomaneio = r.pedidosEntregues.contains(entrega.pedidoId);
                      final corRomaneio = isEntregueNoRomaneio ? Colors.green : Colors.teal;
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RomaneiosPage(romaneioIdToOpen: r.id),
                            ),
                          );
                        },
                        child: _buildTag(
                          isEntregueNoRomaneio ? Icons.check_circle : Icons.assignment,
                          r.numero,
                          corRomaneio,
                        ),
                      );
                    }),
                    
                    // ── Informação de Pagamento ──
                    Builder(
                      builder: (context) {
                        final pedido = dataService.pedidos.where((p) => p.id == entrega.pedidoId || p.numero == entrega.pedidoNumero).firstOrNull;
                        if (pedido == null) return const SizedBox.shrink();
                        
                        final saldoDevedor = pedido.totalGeral - pedido.totalRecebido;
                        final isPago = saldoDevedor <= 0.01;
                        final corPagamento = isPago ? Colors.greenAccent : (pedido.totalRecebido > 0 ? Colors.orangeAccent : Colors.redAccent);
                        final labelPagamento = isPago ? 'PAGO' : (pedido.totalRecebido > 0 ? 'PARCIAL: R\$ ${saldoDevedor.toStringAsFixed(2)}' : 'PENDENTE: R\$ ${saldoDevedor.toStringAsFixed(2)}');
                        
                        return _buildTag(
                          isPago ? Icons.payments : Icons.money_off,
                          labelPagamento,
                          corPagamento,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Linha 6: Ações ──
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (entrega.clienteTelefone != null)
                    _buildActionBtn(Icons.phone, Colors.greenAccent, () => _ligarCliente(entrega.clienteTelefone!)),
                  if (entrega.clienteTelefone != null)
                    _buildActionBtn(Icons.chat, Colors.green, () => _abrirWhatsApp(entrega)),
                  _buildActionBtn(Icons.map, Colors.blueAccent, () => _abrirMapa(entrega)),
                  TextButton.icon(
                    onPressed: () => _abrirDetalhes(context, entrega),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Detalhes', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white60,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  Widget _buildTag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color,
      onPressed: onTap,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }

  String _formatarDataHora(DateTime data) {
    final h = data.hour.toString().padLeft(2, '0');
    final m = data.minute.toString().padLeft(2, '0');
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} $h:$m';
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual;

    // Criar evento no histórico
    final evento = EventoEntrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dataHora: DateTime.now(),
      status: novoStatus,
      descricao: 'Status alterado para ${novoStatus.nome} por ${usuario?.nome ?? "Sistema"}',
      responsavel: usuario?.nome,
    );

    // Atualizar entrega
    final entregaAtualizada = entrega
        .adicionarEvento(evento)
        .copyWith(
          status: novoStatus,
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
    if (_dataInicioFiltro != null) {
      resultado = resultado.where((e) {
        final dataEntrega = e.dataPrevisao ?? e.dataCriacao;
        return !dataEntrega.isBefore(_dataInicioFiltro!);
      }).toList();
    }
    if (_dataFimFiltro != null) {
      resultado = resultado.where((e) {
        final dataEntrega = e.dataPrevisao ?? e.dataCriacao;
        final dataFim = _dataFimFiltro!.add(const Duration(days: 1));
        return !dataEntrega.isAfter(dataFim);
      }).toList();
    }

    // Filtro por motorista
    if (_motoristaFiltro != null) {
      resultado = resultado
          .where((e) => e.motoristaNome == _motoristaFiltro)
          .toList();
    }

    // Filtro apenas atrasadas
    if (_apenasAtrasadas) {
      resultado = resultado.where((e) => e.estaAtrasada).toList();
    }

    // Ordenar: atrasadas primeiro, depois mais recentes (por previsão ou criação) no topo
    resultado.sort((a, b) {
      // 1. Prioridade para atrasadas
      if (a.estaAtrasada && !b.estaAtrasada) return -1;
      if (!a.estaAtrasada && b.estaAtrasada) return 1;
      
      // 2. Dentro do grupo (atrasadas ou normais), mostrar as mais recentes no topo
      // Priorizar dataPrevisao se disponível, senão dataCriacao
      final dataA = a.dataPrevisao ?? a.dataCriacao;
      final dataB = b.dataPrevisao ?? b.dataCriacao;
      
      return dataB.compareTo(dataA);
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
      'romaneioCriado': entregas
          .where((e) => e.status == StatusEntrega.romaneioCriado)
          .length,
      'emEntrega': entregas
          .where((e) => e.status == StatusEntrega.emEntrega)
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

  Widget _buildFiltroData() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 16, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _buildBotaoData(
                  label: _dataInicioFiltro != null
                      ? DateFormat('dd/MM/yyyy').format(_dataInicioFiltro!)
                      : 'Início',
                  onTap: () => _selecionarData(true),
                  isSet: _dataInicioFiltro != null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('até', style: TextStyle(color: Colors.white24, fontSize: 12)),
                ),
                _buildBotaoData(
                  label: _dataFimFiltro != null
                      ? DateFormat('dd/MM/yyyy').format(_dataFimFiltro!)
                      : 'Fim',
                  onTap: () => _selecionarData(false),
                  isSet: _dataFimFiltro != null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoData({required String label, required VoidCallback onTap, bool isSet = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isSet ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSet ? Colors.green.withOpacity(0.3) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSet ? Colors.greenAccent : Colors.white54,
              fontSize: 12,
              fontWeight: isSet ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _selecionarData(bool isInicio) async {
    final data = await showDatePicker(
      context: context,
      initialDate: (isInicio ? _dataInicioFiltro : _dataFimFiltro) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.green,
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
        if (isInicio) {
          _dataInicioFiltro = DateTime(data.year, data.month, data.day);
        } else {
          _dataFimFiltro = DateTime(data.year, data.month, data.day, 23, 59, 59);
        }
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

  void _ligarCliente(String telefone) async {
    final cleanTel = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('tel:$cleanTel');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a chamada.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _abrirWhatsApp(Entrega entrega) async {
    if (entrega.clienteTelefone == null) return;
    
    final cleanTel = entrega.clienteTelefone!.replaceAll(RegExp(r'[^0-9]'), '');
    String telFmt = cleanTel;
    if (!telFmt.startsWith('55') && telFmt.length <= 11) {
      telFmt = '55$telFmt';
    }
    
    final msg = 'Olá ${entrega.clienteNome}, sua entrega (${entrega.pedidoNumero ?? "Pedido"}) está sendo processada!';
    final url = 'https://wa.me/$telFmt?text=${Uri.encodeComponent(msg)}';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _abrirMapa(Entrega entrega) async {
    final query = Uri.encodeComponent(entrega.enderecoCompleto);
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
  }

  Color _getCorStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Colors.orange;
      case StatusEntrega.romaneioCriado:
        return Colors.blue;
      case StatusEntrega.emEntrega:
        return Colors.deepPurple;
      case StatusEntrega.entregue:
        return Colors.green;
      case StatusEntrega.cancelado:
        return Colors.red;
    }
  }

  IconData _getIconeStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Icons.hourglass_empty;
      case StatusEntrega.romaneioCriado:
        return Icons.assignment;
      case StatusEntrega.emEntrega:
        return Icons.local_shipping;
      case StatusEntrega.entregue:
        return Icons.done_all;
      case StatusEntrega.cancelado:
        return Icons.cancel;
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

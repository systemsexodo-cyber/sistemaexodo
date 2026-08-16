import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sync_monitor_service.dart';
import '../theme.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';

/// Pagina de monitoramento de sincronizacao para administradores
/// Mostra o status de sync de todas as empresas e seus logs
class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  List<Map<String, dynamic>> _statusEmpresas = [];
  List<Map<String, dynamic>> _logsEmpresa = [];
  String? _empresaSelecionada;
  bool _carregando = true;
  String _filtroStatus = 'todos';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _carregarDados();

    // Auto-refresh a cada 10 segundos
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _carregarDados();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final status = await SyncMonitorService.buscarStatusTodasEmpresas();
    if (mounted) {
      setState(() {
        _statusEmpresas = status;
        _carregando = false;
      });
    }

    if (_empresaSelecionada != null) {
      final logs = await SyncMonitorService.buscarLogsEmpresa(
        _empresaSelecionada!,
        limite: 100,
      );
      if (mounted) {
        setState(() {
          _logsEmpresa = logs;
        });
      }
    }
  }

  Color _corStatus(Map<String, dynamic> empresa) {
    final online = empresa['online'] == true;
    final ultimaSync = empresa['ultima_sincronizacao'] as String?;
    final temErro = (empresa['ultimo_erro'] as String?)?.isNotEmpty == true;

    if (!online) return Colors.grey;
    if (temErro) return Colors.redAccent;

    if (ultimaSync != null) {
      final data = DateTime.tryParse(ultimaSync);
      if (data != null) {
        final diff = DateTime.now().difference(data);
        if (diff.inMinutes < 5) return Colors.greenAccent;
        if (diff.inHours < 1) return Colors.orangeAccent;
        return Colors.redAccent;
      }
    }

    return Colors.grey;
  }

  String _textoStatus(Map<String, dynamic> empresa) {
    final online = empresa['online'] == true;
    final ultimaSync = empresa['ultima_sincronizacao'] as String?;
    final temErro = (empresa['ultimo_erro'] as String?)?.isNotEmpty == true;

    if (!online) return 'Offline';
    if (temErro) return 'Com Erros';

    if (ultimaSync != null) {
      final data = DateTime.tryParse(ultimaSync);
      if (data != null) {
        final diff = DateTime.now().difference(data);
        if (diff.inMinutes < 5) return 'Online';
        if (diff.inHours < 1) return 'Atencao (${diff.inMinutes}min)';
        return 'Offline (${diff.inHours}h)';
      }
    }

    return 'Desconhecido';
  }

  List<Map<String, dynamic>> get _empresasFiltradas {
    if (_filtroStatus == 'todos') return _statusEmpresas;
    return _statusEmpresas.where((e) {
      final cor = _corStatus(e);
      switch (_filtroStatus) {
        case 'online':
          return cor == Colors.greenAccent;
        case 'erro':
          return cor == Colors.redAccent;
        case 'offline':
          return cor == Colors.grey || cor == Colors.redAccent;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExodoLogoCompact(fontSize: 24),
              SizedBox(width: 8),
              Text('Monitor de Sincronizacao',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blueAccent),
              tooltip: 'Atualizar',
              onPressed: _carregarDados,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildFiltros(),
                  Expanded(
                    child: _empresaSelecionada == null
                        ? _buildListaEmpresas()
                        : _buildDetalheEmpresa(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFiltroChip('Todos', 'todos', Colors.blueAccent),
          const SizedBox(width: 8),
          _buildFiltroChip('Online', 'online', Colors.greenAccent),
          const SizedBox(width: 8),
          _buildFiltroChip('Com Erro', 'erro', Colors.redAccent),
          const SizedBox(width: 8),
          _buildFiltroChip('Offline', 'offline', Colors.grey),
          const Spacer(),
          Text(
            '${_empresasFiltradas.length} empresas',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label, String valor, Color cor) {
    final selecionado = _filtroStatus == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroStatus = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado ? cor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? cor : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selecionado ? cor : Colors.white54,
            fontSize: 12,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildListaEmpresas() {
    if (_empresasFiltradas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text('Nenhuma empresa com sync ativo',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            Text('Aguardando clientes enviarem heartbeat...',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _empresasFiltradas.length,
      itemBuilder: (context, index) {
        final empresa = _empresasFiltradas[index];
        final cor = _corStatus(empresa);
    final status = _textoStatus(empresa);
    final ultimaSync = empresa['ultima_sincronizacao'] as String?;
    final fila = empresa['fila_pendente'] as int? ?? 0;
        final empresaId = empresa['empresa_id'] as String? ?? '';

        return Card(
          color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cor.withOpacity(0.3), width: 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _empresaSelecionada = empresaId;
              });
              _carregarDados();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Indicador de status
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: cor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cor.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          empresaId.length > 12
                              ? '${empresaId.substring(0, 12)}...'
                              : empresaId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PC: ${empresa['pc_name'] ?? '-'}',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          color: cor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (ultimaSync != null)
                        Text(
                          _formatarData(ultimaSync),
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      if (fila > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Fila: $fila',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.white24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetalheEmpresa() {
    return Column(
      children: [
        // Cabecalho da empresa selecionada
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                onPressed: () => setState(() => _empresaSelecionada = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Empresa: $_empresaSelecionada',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_logsEmpresa.length} eventos registrados',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Lista de logs
        Expanded(
          child: _logsEmpresa.isEmpty
              ? Center(
                  child: Text('Nenhum log encontrado',
                      style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _logsEmpresa.length,
                  itemBuilder: (context, index) {
                    final log = _logsEmpresa[index];
                    return _buildLogItem(log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final evento = log['evento'] as String? ?? '';
    final detalhes = log['detalhes'] as String? ?? '';
    final erro = log['erro'] as String? ?? '';
    final data = log['created_at'] as String? ?? '';

    IconData icon;
    Color cor;
    switch (evento) {
      case 'sync_ok':
      case 'sync_item_ok':
        icon = Icons.check_circle;
        cor = Colors.greenAccent;
        break;
      case 'erro_sync':
        icon = Icons.error;
        cor = Colors.redAccent;
        break;
      case 'inicio_sync':
        icon = Icons.sync;
        cor = Colors.blueAccent;
        break;
      default:
        icon = Icons.info;
        cor = Colors.grey;
    }

    return Card(
      color: Colors.white.withOpacity(0.03),
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: cor, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        evento,
                        style: TextStyle(
                          color: cor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatarData(data),
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  if (detalhes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detalhes,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (erro.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        erro.length > 200
                            ? '${erro.substring(0, 200)}...'
                            : erro,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatarData(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final agora = DateTime.now().toUtc();
    final diff = agora.difference(dt);

    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return 'ha ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'ha ${diff.inHours}h';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

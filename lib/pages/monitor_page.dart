import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/empresa.dart';
import '../models/status_sync.dart';
import '../services/auth_service.dart';
import '../services/sync_monitor_service.dart';
import '../theme.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';

/// Pagina de monitoramento de sincronizacao para administradores.
///
/// Mostra, para cada computador cliente: quando deu o ultimo sinal de vida,
/// ha quantos dias/dias esta sem sincronizar e qual erro esta pendente. Os
/// erros recentes de todas as empresas aparecem tambem num painel no topo,
/// porque e o que o suporte precisa ver primeiro.
class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  List<StatusSync> _empresas = [];
  List<Map<String, dynamic>> _errosRecentes = [];
  List<Map<String, dynamic>> _logsEmpresa = [];
  String? _empresaSelecionada;
  bool _carregando = true;
  bool _atualizando = false;
  String _filtroStatus = 'todos';
  bool _ordemCritica = true;
  bool _mostrarTodosErros = false;
  bool _logsSomenteErros = false;
  DateTime _ultimaAtualizacao = DateTime.now();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _carregarDados();

    // Auto-refresh a cada 15 segundos
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _carregarDados();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    if (_atualizando) return;
    _atualizando = true;
    try {
      // As tres consultas sao independentes: uma falhar (nuvem fora do ar) nao
      // pode apagar o que a outra ja trouxe.
      final status = await SyncMonitorService.buscarStatusInterpretado();
      final erros = await SyncMonitorService.buscarErrosRecentes();
      List<Map<String, dynamic>> logs = _logsEmpresa;
      if (_empresaSelecionada != null) {
        logs = await SyncMonitorService.buscarLogsEmpresa(
          _empresaSelecionada!,
          limite: 100,
        );
      }

      if (!mounted) return;
      setState(() {
        _empresas = _comEmpresasNuncaSincronizadas(status);
        _errosRecentes = erros;
        _logsEmpresa = logs;
        _carregando = false;
        _ultimaAtualizacao = DateTime.now();
      });
    } finally {
      _atualizando = false;
    }
  }

  /// Acrescenta as empresas cadastradas que nunca apareceram no `sync_status`.
  ///
  /// Sem isso, "o cliente nunca sincronizou" seria invisivel: o monitor so
  /// mostraria quem ja deu sinal alguma vez.
  List<StatusSync> _comEmpresasNuncaSincronizadas(List<StatusSync> status) {
    final conhecidas = status.map((s) => s.empresaId).toSet();
    final resultado = List<StatusSync>.from(status);
    for (final empresa in _empresasCadastradas) {
      if (conhecidas.contains(empresa.id)) continue;
      resultado.add(StatusSync(empresaId: empresa.id));
    }
    return resultado;
  }

  List<Empresa> get _empresasCadastradas {
    try {
      return Provider.of<AuthService>(context, listen: false).empresas;
    } catch (_) {
      // Tela aberta sem o provider (testes/uso isolado): segue sem nomes.
      return const [];
    }
  }

  String _nomeEmpresa(String empresaId) {
    for (final empresa in _empresasCadastradas) {
      if (empresa.id == empresaId) {
        final nome = empresa.nomeExibicao.isNotEmpty
            ? empresa.nomeExibicao
            : empresa.razaoSocial;
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Empresa ${_idCurto(empresaId)}';
  }

  String _idCurto(String id) =>
      id.length > 12 ? '${id.substring(0, 12)}...' : id;

  // ── Estados derivados ────────────────────────────────────────────────────

  List<StatusSync> get _empresasFiltradas {
    final lista = _empresas.where((e) {
      switch (_filtroStatus) {
        case 'online':
          return e.criticidade(DateTime.now()) == 0;
        case 'erro':
          return e.temErroNaoResolvido;
        case 'offline':
          return e.semContatoHaDias(DateTime.now());
        case 'nunca':
          return e.ultimoContato == null;
        default:
          return true;
      }
    }).toList();

    if (_ordemCritica) {
      final agora = DateTime.now();
      lista.sort((a, b) => a.compararCom(b, agora));
    } else {
      lista.sort((a, b) => _nomeEmpresa(a.empresaId)
          .toLowerCase()
          .compareTo(_nomeEmpresa(b.empresaId).toLowerCase()));
    }
    return lista;
  }

  List<Map<String, dynamic>> get _logsExibidos {
    if (!_logsSomenteErros) return _logsEmpresa;
    return _logsEmpresa
        .where((l) => (l['erro']?.toString() ?? '').trim().isNotEmpty)
        .toList();
  }

  int _contar(bool Function(StatusSync) teste) =>
      _empresas.where((e) => teste(e)).length;

  // ── Cores por gravidade ──────────────────────────────────────────────────

  Color _corDoNivel(StatusSync e, DateTime agora) {
    if (e.temErroNaoResolvido) return Colors.redAccent;
    final tempo = e.tempoSemContato(agora);
    if (tempo == null) return Colors.deepPurpleAccent;
    if (tempo.inHours >= 24) return Colors.redAccent;
    if (tempo.inHours >= 2) return Colors.orangeAccent;
    if (tempo.inMinutes >= 30) return Colors.amberAccent;
    return Colors.greenAccent;
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
              tooltip: 'Atualizar agora',
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
                  if (_empresaSelecionada == null) ...[
                    _buildResumo(),
                    _buildPainelErros(),
                    _buildFiltros(),
                  ],
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

  /// Resumo no topo: quantos clientes em cada situacao e ha quanto tempo a tela
  /// foi atualizada (o refresh automatico roda a cada 15s).
  Widget _buildResumo() {
    final agora = DateTime.now();
    final online = _contar((e) => e.criticidade(agora) == 0);
    final comErro = _contar((e) => e.temErroNaoResolvido);
    final offlineDias = _contar((e) => e.semContatoHaDias(agora));
    final nunca = _contar((e) => e.ultimoContato == null);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildContador('Online', online, Colors.greenAccent),
              _buildContador('Com erro', comErro, Colors.redAccent),
              _buildContador('Offline +1 dia', offlineDias, Colors.orangeAccent),
              _buildContador('Nunca sincronizou', nunca,
                  Colors.deepPurpleAccent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_empresas.length} empresa(s) monitorada(s) • atualizado às '
            '${_horaMinutoSegundo(_ultimaAtualizacao)} (recarrega sozinho a cada 15s)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildContador(String label, int valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$valor',
            style: TextStyle(
              color: cor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: cor, fontSize: 11)),
        ],
      ),
    );
  }

  /// Erros recentes de TODAS as empresas (tabela `sync_logs`).
  ///
  /// O monitor antigo exigia clicar em cada empresa para descobrir o erro — e o
  /// erro so aparecia porque o cliente o registrava. Aqui o erro fica na cara,
  /// com a mensagem completa, a empresa, o PC e quando aconteceu.
  Widget _buildPainelErros() {
    if (_errosRecentes.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.25)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhum erro de sincronização registrado pelos clientes.',
                style: TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final visiveis =
        _mostrarTodosErros ? _errosRecentes : _errosRecentes.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Erros recentes (${_errosRecentes.length})',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_errosRecentes.length > 3)
                  TextButton(
                    onPressed: () => setState(
                        () => _mostrarTodosErros = !_mostrarTodosErros),
                    child: Text(
                      _mostrarTodosErros ? 'Mostrar menos' : 'Ver todos',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          ...visiveis.map(_buildItemErroRecente),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildItemErroRecente(Map<String, dynamic> erro) {
    final empresaId = erro['empresa_id']?.toString() ?? '';
    final pc = erro['pc_name']?.toString() ?? '';
    final mensagem = (erro['erro']?.toString() ?? '').trim();
    final detalhes = (erro['detalhes']?.toString() ?? '').trim();
    final quando = _parseData(erro['created_at']);

    return InkWell(
      onTap: empresaId.isEmpty
          ? null
          : () => _abrirDetalheEmpresa(empresaId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _nomeEmpresa(empresaId),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  quando == null ? '' : _tempoRelativo(quando),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'PC: ${pc.isEmpty ? '-' : pc}'
              '${detalhes.isEmpty ? '' : ' • $detalhes'}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                mensagem,
                maxLines: 4,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
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
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFiltroChip('Todos', 'todos', Colors.blueAccent),
                  const SizedBox(width: 8),
                  _buildFiltroChip('Online', 'online', Colors.greenAccent),
                  const SizedBox(width: 8),
                  _buildFiltroChip('Com Erro', 'erro', Colors.redAccent),
                  const SizedBox(width: 8),
                  _buildFiltroChip('Offline +1 dia', 'offline',
                      Colors.orangeAccent),
                  const SizedBox(width: 8),
                  _buildFiltroChip(
                      'Nunca sync', 'nunca', Colors.deepPurpleAccent),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _ordemCritica ? Icons.priority_high : Icons.sort_by_alpha,
              color: Colors.white54,
              size: 20,
            ),
            tooltip: _ordemCritica
                ? 'Mostrando os mais críticos primeiro'
                : 'Ordenado por nome',
            onPressed: () => setState(() => _ordemCritica = !_ordemCritica),
          ),
          Text(
            '${_empresasFiltradas.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
          color: selecionado
              ? cor.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
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
            const Icon(Icons.cloud_off, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('Nenhuma empresa neste filtro',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            Text(
              _empresas.isEmpty
                  ? 'Aguardando clientes enviarem heartbeat...'
                  : 'Troque o filtro para ver as outras ${_empresas.length}.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _empresasFiltradas.length,
      itemBuilder: (context, index) =>
          _buildCardEmpresa(_empresasFiltradas[index]),
    );
  }

  Widget _buildCardEmpresa(StatusSync empresa) {
    final agora = DateTime.now();
    final cor = _corDoNivel(empresa, agora);
    final status = empresa.textoStatus(agora);
    final selo = empresa.seloOffline(agora);
    final contato = empresa.ultimoContato;
    final tempo = empresa.tempoLegivel(agora);

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirDetalheEmpresa(empresa.empresaId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nomeEmpresa(empresa.empresaId),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID ${_idCurto(empresa.empresaId)}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PC: ${empresa.pcName.isEmpty ? '-' : empresa.pcName}'
                          '${empresa.versaoApp.isEmpty ? '' : ' • versão ${empresa.versaoApp}'}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white24),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      color: cor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (empresa.filaPendente > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Fila: ${empresa.filaPendente}',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 12, color: Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      contato == null
                          ? 'Nunca deu sinal de sincronização'
                          : 'Último contato: ${_dataAbsoluta(contato)}'
                              '${tempo == null ? '' : ' ($tempo)'}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
              if (selo != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.redAccent.withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          color: Colors.redAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        selo,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (empresa.temErroNaoResolvido) ...[
                const SizedBox(height: 8),
                _buildBlocoErro(empresa, agora),
              ] else if (empresa.erroJaResolvido) ...[
                const SizedBox(height: 6),
                Text(
                  'Último erro já superado por uma sincronização posterior '
                  '(${empresa.erroHaQuantoTempo(agora) ?? 'sem data'}).',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlocoErro(StatusSync empresa, DateTime agora) {
    final quando = empresa.erroHaQuantoTempo(agora);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error, color: Colors.redAccent, size: 14),
              const SizedBox(width: 6),
              const Text(
                'ERRO PENDENTE',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (quando != null)
                Text(
                  quando,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            empresa.ultimoErro.trim(),
            maxLines: 3,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDetalheEmpresa(String empresaId) {
    setState(() {
      _empresaSelecionada = empresaId;
      _logsSomenteErros = false;
    });
    _carregarDados();
  }

  Widget _buildDetalheEmpresa() {
    final agora = DateTime.now();
    final status = _empresas.firstWhere(
      (e) => e.empresaId == _empresaSelecionada,
      orElse: () => StatusSync(empresaId: _empresaSelecionada ?? ''),
    );
    final cor = _corDoNivel(status, agora);
    final logs = _logsExibidos;
    final totalErros = _logsEmpresa
        .where((l) => (l['erro']?.toString() ?? '').trim().isNotEmpty)
        .length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.arrow_back, color: Colors.white54),
                    onPressed: () =>
                        setState(() => _empresaSelecionada = null),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nomeEmpresa(status.empresaId),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SelectableText(
                          status.empresaId,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildPilula(status.textoStatus(agora), cor),
                  if (status.seloOffline(agora) != null)
                    _buildPilula(status.seloOffline(agora)!, Colors.redAccent),
                  if (status.pcName.isNotEmpty)
                    _buildPilula('PC: ${status.pcName}', Colors.white54),
                  if (status.versaoApp.isNotEmpty)
                    _buildPilula('Versão ${status.versaoApp}', Colors.white54),
                  if (status.filaPendente > 0)
                    _buildPilula('Fila: ${status.filaPendente}',
                        Colors.orangeAccent),
                  _buildPilula('$totalErros erro(s) registrado(s)',
                      Colors.redAccent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                status.ultimoContato == null
                    ? 'Este computador nunca registrou sincronização na nuvem.'
                    : 'Último contato com a nuvem: '
                        '${_dataAbsoluta(status.ultimoContato!)}'
                        ' • ${status.tempoLegivel(agora) ?? ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (status.ultimaSincronizacao != null)
                Text(
                  'Última sincronização: '
                  '${_dataAbsoluta(status.ultimaSincronizacao!)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFiltroLogsChip('Todos os eventos', false),
              const SizedBox(width: 8),
              _buildFiltroLogsChip('Somente erros', true),
              const Spacer(),
              Text('${logs.length} evento(s)',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Text(
                    _logsSomenteErros
                        ? 'Nenhum erro registrado para esta empresa.'
                        : 'Nenhum log encontrado',
                    style: const TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) =>
                      _buildLogItem(logs[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildPilula(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 11),
      ),
    );
  }

  Widget _buildFiltroLogsChip(String label, bool somenteErros) {
    final selecionado = _logsSomenteErros == somenteErros;
    final cor = somenteErros ? Colors.redAccent : Colors.blueAccent;
    return GestureDetector(
      onTap: () => setState(() => _logsSomenteErros = somenteErros),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado
              ? cor.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selecionado ? cor : Colors.white12, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selecionado ? cor : Colors.white54,
            fontSize: 12,
            fontWeight:
                selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final evento = log['evento'] as String? ?? '';
    final detalhes = log['detalhes'] as String? ?? '';
    final erro = (log['erro'] as String? ?? '').trim();
    final data = _parseData(log['created_at']);

    IconData icon;
    Color cor;
    String titulo;
    switch (evento) {
      case 'sync_ok':
        icon = Icons.check_circle;
        cor = Colors.greenAccent;
        titulo = 'Sincronização concluída';
        break;
      case 'sync_item_ok':
        icon = Icons.check_circle_outline;
        cor = Colors.tealAccent;
        titulo = 'Registro enviado';
        break;
      case 'erro_sync':
        icon = Icons.error;
        cor = Colors.redAccent;
        titulo = 'FALHA NA SINCRONIZAÇÃO';
        break;
      case 'inicio_sync':
        icon = Icons.sync;
        cor = Colors.blueAccent;
        titulo = 'Sessão iniciada';
        break;
      default:
        icon = Icons.info;
        cor = Colors.grey;
        titulo = evento.isEmpty ? 'Evento' : evento;
    }

    return Card(
      color: Colors.white.withOpacity(0.03),
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: erro.isNotEmpty
            ? BorderSide(color: Colors.redAccent.withOpacity(0.4))
            : BorderSide.none,
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
                      Expanded(
                        child: Text(
                          titulo,
                          style: TextStyle(
                            color: cor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        data == null
                            ? '-'
                            : '${_dataAbsoluta(data)} • ${_tempoRelativo(data)}',
                        style: const TextStyle(
                          color: Colors.white38,
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
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        erro,
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

  // ── Datas ────────────────────────────────────────────────────────────────

  static DateTime? _parseData(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor.toLocal();
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  /// Data absoluta: sem o ano quando é do ano corrente (o caso comum),
  /// porque o que importa é "quando, no dia a dia".
  static String _dataAbsoluta(DateTime data) {
    final local = data.toLocal();
    final agora = DateTime.now();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');
    final ano = local.year == agora.year ? '' : '/${local.year}';
    return '$dia/$mes$ano $hora:$minuto';
  }

  static String _horaMinutoSegundo(DateTime data) {
    final local = data.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  static String _tempoRelativo(DateTime data) {
    final diff = DateTime.now().difference(data.toLocal());
    if (diff.isNegative) return 'agora';
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    final dias = diff.inDays;
    return dias == 1 ? 'há 1 dia' : 'há $dias dias';
  }
}

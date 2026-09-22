import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../services/pedido_impressao_service.dart';
import '../models/servico_realizado.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'lancar_servico_page.dart';
import 'agenda_servicos_page.dart';
import 'pdv_page.dart';
import 'clientes_servicos_page.dart';
import 'comissoes_page.dart';
import 'historico_vendas_page.dart';
import 'tipos_servico_page.dart';
import '../widgets/sync_status_widget.dart';
import '../widgets/pedido_detalhes_dialog.dart';

/// Tela de Serviços realizados.
///
/// Lista os serviços lançados na entidade PRÓPRIA de serviço (tabela
/// `servicos_realizados`, série SRV), separados em abas: "Orçamentos"
/// (propostas), "Em Aberto" (ainda não recebidos) e "Recebidos" (quitados).
/// O cadastro dos tipos de serviço fica em [TiposServicoPage].
class ServicosPage extends StatefulWidget {
  const ServicosPage({super.key});

  @override
  State<ServicosPage> createState() => _ServicosPageState();
}

class _ServicosPageState extends State<ServicosPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _buscaController = TextEditingController();
  String _termoBusca = '';
  int _abaAtual = 0;
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  String? _periodoRapido; // 'Hoje', '7 dias', '30 dias', 'Este mês' ou null (personalizado)

  static const _coresAba = [
    Colors.purpleAccent,
    Colors.orangeAccent,
    Colors.greenAccent,
    Colors.blueAccent,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_aoTrocarAba);
  }

  @override
  void dispose() {
    _tabController.removeListener(_aoTrocarAba);
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  void _aoTrocarAba() {
    if (_tabController.index != _abaAtual) {
      setState(() => _abaAtual = _tabController.index);
    }
  }

  bool _cancelado(ServicoRealizado s) => s.cancelado;

  bool _orcamento(ServicoRealizado s) => s.ehOrcamento;

  bool _recebido(ServicoRealizado s) => s.totalmenteRecebido;

  bool _emAberto(ServicoRealizado s) => s.emAberto;

  /// Serviços lançados que batem com o termo de busca e com o período escolhido.
  List<ServicoRealizado> _filtrar(List<ServicoRealizado> servicos) {
    var lista = servicos;

    // Filtro de período (pela data do serviço)
    if (_dataInicioFiltro != null || _dataFimFiltro != null) {
      final inicio = _dataInicioFiltro != null
          ? DateTime(_dataInicioFiltro!.year, _dataInicioFiltro!.month,
              _dataInicioFiltro!.day)
          : null;
      final fim = _dataFimFiltro != null
          ? DateTime(_dataFimFiltro!.year, _dataFimFiltro!.month,
              _dataFimFiltro!.day, 23, 59, 59)
          : null;
      lista = lista.where((s) {
        if (inicio != null && s.dataServico.isBefore(inicio)) return false;
        if (fim != null && s.dataServico.isAfter(fim)) return false;
        return true;
      }).toList();
    }

    final busca = _termoBusca.trim().toLowerCase();
    if (busca.isEmpty) return lista;
    return lista.where((s) {
      if ((s.clienteNome ?? '').toLowerCase().contains(busca)) return true;
      if (s.numero.toLowerCase().contains(busca)) return true;
      if ((s.observacoes ?? '').toLowerCase().contains(busca)) return true;
      return s.servicos.any(
        (item) =>
            item.descricao.toLowerCase().contains(busca) ||
            (item.descricaoAdicional ?? '').toLowerCase().contains(busca),
      );
    }).toList();
  }

  /// Atalhos rápidos de período: Hoje, 7 dias, 30 dias e mês atual.
  void _aplicarPeriodoRapido(String periodo) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final DateTime inicio;
    switch (periodo) {
      case 'Hoje':
        inicio = hoje;
        break;
      case '7 dias':
        inicio = hoje.subtract(const Duration(days: 6));
        break;
      case '30 dias':
        inicio = hoje.subtract(const Duration(days: 29));
        break;
      default: // Este mês
        inicio = DateTime(agora.year, agora.month, 1);
    }

    setState(() {
      _periodoRapido = periodo;
      _dataInicioFiltro = inicio;
      _dataFimFiltro = hoje;
    });
  }

  void _limparPeriodo() {
    setState(() {
      _periodoRapido = null;
      _dataInicioFiltro = null;
      _dataFimFiltro = null;
    });
  }

  /// Escolhe a data inicial ou final do período personalizado.
  Future<void> _selecionarDataFiltro(bool isInicio) async {
    final dataAtual = isInicio ? _dataInicioFiltro : _dataFimFiltro;
    final data = await showDatePicker(
      context: context,
      initialDate: dataAtual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.orange,
            surface: Color(0xFF1E1E2E),
          ),
        ),
        child: child!,
      ),
    );

    if (data == null) return;

    setState(() {
      _periodoRapido = null;
      if (isInicio) {
        _dataInicioFiltro = data;
        if (_dataFimFiltro != null && _dataInicioFiltro!.isAfter(_dataFimFiltro!)) {
          _dataFimFiltro = _dataInicioFiltro;
        }
      } else {
        _dataFimFiltro = data;
        if (_dataInicioFiltro != null && _dataFimFiltro!.isBefore(_dataInicioFiltro!)) {
          _dataInicioFiltro = _dataFimFiltro;
        }
      }
    });
  }

  void _abrirLancamento({ServicoRealizado? servico}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LancarServicoPage(servicoExistente: servico),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Recebe o serviço: quita as parcelas pendentes ou o valor total.
  Future<void> _abrirRecebimento(ServicoRealizado servico) async {
    final dataService = Provider.of<DataService>(context, listen: false);

    if (servico.pagamentos.isEmpty) {
      final tipo = await _escolherFormaPagamento();
      if (tipo == null) return;
      await dataService.receberServicoTotal(servico.id, tipo: tipo);
    } else {
      final opcao = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text('Receber ${servico.numero}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Falta receber: ${_moeda.format(servico.valorPendente)}',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
              const SizedBox(height: 12),
              for (final pag in servico.pagamentos.where((p) => !p.recebido))
                ListTile(
                  leading: Icon(pag.tipo.icone, color: pag.tipo.cor),
                  title: Text(
                    '${pag.tipo.nome}${pag.isParcela ? ' (${pag.descricaoParcela})' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: pag.dataVencimento != null
                      ? Text(
                          'Vence ${DateFormat('dd/MM/yyyy').format(pag.dataVencimento!)}',
                          style: TextStyle(
                            color: pag.isVencida
                                ? Colors.redAccent
                                : Colors.white54,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  trailing: Text(
                    _moeda.format(pag.valor),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => Navigator.pop(dialogContext, 'parcela:${pag.id}'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'tudo'),
              icon: const Icon(Icons.payments),
              label: const Text('Receber tudo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (opcao == null) return;
      if (opcao == 'tudo') {
        await dataService.receberServicoTotal(servico.id);
      } else {
        await dataService.receberPagamentoServico(
          servico.id,
          opcao.replaceFirst('parcela:', ''),
        );
      }
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recebimento registrado em ${servico.numero}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Forma de pagamento para serviços lançados sem pagamento (recebimento avulso).
  Future<TipoPagamento?> _escolherFormaPagamento() async {
    TipoPagamento selecionada = TipoPagamento.dinheiro;
    return showDialog<TipoPagamento>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Forma de pagamento'),
          content: DropdownButtonFormField<TipoPagamento>(
            initialValue: selecionada,
            dropdownColor: const Color(0xFF1E1E2E),
            style: const TextStyle(color: Colors.white),
            items: TipoPagamento.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Icon(t.icone, color: t.cor, size: 18),
                        const SizedBox(width: 8),
                        Text(t.nome),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (valor) {
              if (valor != null) setDialogState(() => selecionada = valor);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, selecionada),
              child: const Text('Receber'),
            ),
          ],
        ),
      ),
    );
  }

  /// Aprova o orçamento: vira serviço em aberto (passa a ser recebível de serviço).
  Future<void> _aprovarOrcamento(ServicoRealizado servico) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    await dataService.aprovarOrcamentoServico(servico.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orçamento ${servico.numero} aprovado — agora está em aberto'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Visualização completa do serviço (cliente, itens, pagamentos...).
  void _mostrarDetalhes(ServicoRealizado servico) {
    mostrarDetalhesPedido(
      context,
      servico.toPedido(),
      rotuloStatusOverride: servico.ehOrcamento
          ? (servico.orcamentoVencido ? 'ORÇAMENTO VENCIDO' : 'ORÇAMENTO')
          : null,
      corStatusOverride: servico.ehOrcamento ? Colors.purpleAccent : null,
      onImprimir: () => _mostrarMenuImpressao(servico),
      onEditar: () => _abrirLancamento(servico: servico),
      onReceber:
          servico.ehOrcamento ? null : () => _abrirRecebimento(servico),
      onAprovar: servico.ehOrcamento ? () => _aprovarOrcamento(servico) : null,
    );
  }

  /// Mesmo menu de impressão disponível na tela de Pedidos.
  void _mostrarMenuImpressao(ServicoRealizado servico) {
    PedidoImpressaoService.mostrarMenuImpressao(
      context,
      servico.toPedido(),
      incluirRomaneio: _temEntrega(servico),
    );
  }

  /// Serviços com Taxi Dog / entrega podem imprimir o romaneio de separação.
  bool _temEntrega(ServicoRealizado servico) =>
      servico.servicos.any((s) => (s.tipoEntrega ?? '').isNotEmpty);

  final _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);

    // Fonte: entidade PRÓPRIA de serviço realizado (série SRV, tabela
    // `servicos_realizados`) — não são pedidos.
    final todos = List<ServicoRealizado>.from(dataService.servicosRealizados)
      ..sort((a, b) => b.dataServico.compareTo(a.dataServico));

    final filtrados = _filtrar(todos);
    final orcamentos = filtrados.where(_orcamento).toList();
    final emAberto = filtrados.where(_emAberto).toList();
    final recebidos = filtrados.where(_recebido).toList();

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Serviços'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ClientesServicosPage(),
                  ),
                );
              },
              tooltip: 'Clientes de Serviços',
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ComissoesPage(),
                  ),
                );
              },
              tooltip: 'Consulta de Comissões',
            ),
            IconButton(
              icon: const Icon(Icons.payment),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PdvPage(
                      abaInicial: 0, // Aba de Receber
                    ),
                  ),
                );
              },
              tooltip: 'Receber Pagamentos',
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AgendaServicosPage(),
                  ),
                );
              },
              tooltip: 'Agenda de Serviços',
            ),
            IconButton(
              icon: const Icon(Icons.history, color: Colors.blue),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoricoVendasPage(),
                  ),
                );
              },
              tooltip: 'Histórico de Vendas',
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add, color: Colors.greenAccent),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TiposServicoPage(),
                  ),
                );
              },
              tooltip: 'Tipos de Serviço (Cadastro)',
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _abrirLancamento(),
              tooltip: 'Lançar Serviço',
            ),
            const SyncStatusWidget(),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _buscaController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente, serviço ou número...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: _termoBusca.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70),
                          onPressed: () {
                            setState(() {
                              _termoBusca = '';
                              _buscaController.clear();
                            });
                          },
                        ),
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _termoBusca = value),
              ),
            ),
            _buildFiltroPeriodo(),
            TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: _coresAba[_abaAtual],
              tabs: [
                Tab(text: 'Orçamentos (${orcamentos.length})'),
                Tab(text: 'Em Aberto (${emAberto.length})'),
                Tab(text: 'Recebidos (${recebidos.length})'),
                Tab(text: 'Todos (${filtrados.length})'),
              ],
            ),
            _buildResumo(orcamentos, emAberto, recebidos, filtrados),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLista(orcamentos, 'Nenhum orçamento'),
                  _buildLista(emAberto, 'Nenhum serviço em aberto'),
                  _buildLista(recebidos, 'Nenhum serviço recebido'),
                  _buildLista(filtrados, 'Nenhum serviço encontrado'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra de filtro por período (atalhos rápidos + datas personalizadas).
  Widget _buildFiltroPeriodo() {
    final formato = DateFormat('dd/MM/yyyy');
    final temFiltro = _dataInicioFiltro != null || _dataFimFiltro != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.orange),
              SizedBox(width: 6),
              Text(
                'Período:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          for (final periodo in const ['Hoje', '7 dias', '30 dias', 'Este mês'])
            _chipPeriodo(
              periodo,
              selecionado: _periodoRapido == periodo,
              onTap: () => _aplicarPeriodoRapido(periodo),
            ),
          _botaoData(
            _dataInicioFiltro != null
                ? formato.format(_dataInicioFiltro!)
                : 'Data inicial',
            temData: _dataInicioFiltro != null,
            onTap: () => _selecionarDataFiltro(true),
          ),
          const Text('até', style: TextStyle(color: Colors.white54, fontSize: 12)),
          _botaoData(
            _dataFimFiltro != null
                ? formato.format(_dataFimFiltro!)
                : 'Data final',
            temData: _dataFimFiltro != null,
            onTap: () => _selecionarDataFiltro(false),
          ),
          if (temFiltro)
            TextButton.icon(
              onPressed: _limparPeriodo,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Limpar'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipPeriodo(
    String label, {
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado
              ? Colors.orange.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? Colors.orange : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selecionado ? Colors.orange : Colors.white70,
            fontSize: 12,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _botaoData(
    String label, {
    required bool temData,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, size: 14, color: Colors.orange),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: temData ? Colors.white : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumo(
    List<ServicoRealizado> orcamentos,
    List<ServicoRealizado> emAberto,
    List<ServicoRealizado> recebidos,
    List<ServicoRealizado> todos,
  ) {
    final moeda = _moeda;
    final faltaReceber = emAberto.fold<double>(
      0.0,
      (s, p) => s + (p.totalGeral - p.totalRecebido),
    );
    final totalRecebido = recebidos.fold<double>(0.0, (s, p) => s + p.totalRecebido);
    final totalGeral = todos.fold<double>(0.0, (s, p) => s + p.totalGeral);
    final totalOrcamentos =
        orcamentos.fold<double>(0.0, (s, p) => s + p.totalGeral);

    late final String texto;
    late final Color cor;
    switch (_abaAtual) {
      case 1:
        texto = '${emAberto.length} em aberto • Falta receber ${moeda.format(faltaReceber)}';
        cor = Colors.orangeAccent;
        break;
      case 2:
        texto = '${recebidos.length} serviço(s) recebido(s) • ${moeda.format(totalRecebido)}';
        cor = Colors.greenAccent;
        break;
      case 3:
        texto = '${todos.length} serviço(s) • ${moeda.format(totalGeral)}';
        cor = Colors.blueAccent;
        break;
      default:
        texto =
            '${orcamentos.length} orçamento(s) • ${moeda.format(totalOrcamentos)} em proposta';
        cor = Colors.purpleAccent;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.summarize, size: 16, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista(List<ServicoRealizado> pedidos, String vazio) {
    if (pedidos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.build_circle_outlined, size: 56, color: Colors.white.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(vazio, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      cacheExtent: 1000,
      itemCount: pedidos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCardServico(pedidos[index]),
    );
  }

  Widget _buildCardServico(ServicoRealizado pedido) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final moeda =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    final isCancelado = _cancelado(pedido);
    final isRecebido = _recebido(pedido);
    final isOrcamento = _orcamento(pedido);
    final falta = pedido.totalGeral - pedido.totalRecebido;

    final corStatus = isCancelado
        ? Colors.redAccent
        : isOrcamento
            ? Colors.purpleAccent
            : isRecebido
                ? Colors.greenAccent
                : Colors.orangeAccent;
    final labelStatus = isCancelado
        ? 'CANCELADO'
        : isOrcamento
            ? (pedido.orcamentoVencido ? 'ORÇAMENTO VENCIDO' : 'ORÇAMENTO')
            : isRecebido
                ? 'RECEBIDO'
                : 'EM ABERTO';

    final servicosVisiveis = pedido.servicos.take(3).toList();
    final restantes = pedido.servicos.length - servicosVisiveis.length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCancelado
              ? [Colors.red.shade900, Colors.red.shade800]
              : isOrcamento
                  ? [const Color(0xFF4A148C), const Color(0xFF311B92)]
                  : isRecebido
                      ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                      : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corStatus.withOpacity(0.6), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _mostrarDetalhes(pedido),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    pedido.numero.isNotEmpty ? pedido.numero : '#${pedido.id}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: corStatus.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: corStatus.withOpacity(0.6)),
                    ),
                    child: Text(
                      labelStatus,
                      style: TextStyle(
                        color: corStatus,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    moeda.format(pedido.totalGeral),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      pedido.clienteNome?.isNotEmpty == true
                          ? pedido.clienteNome!
                          : 'Consumidor final',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.event, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    formatoData.format(pedido.dataServico),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...servicosVisiveis.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.build, size: 12, color: Colors.lightBlueAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.valorAdicional > 0.001
                                    ? '${s.descricao} (+ ${moeda.format(s.valorAdicional)})'
                                    : s.descricao,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              moeda.format(s.valor + s.valorAdicional),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (restantes > 0)
                      Text(
                        '+ $restantes serviço(s)',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (isOrcamento && pedido.validadeOrcamento != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Válido até ${DateFormat('dd/MM/yyyy').format(pedido.validadeOrcamento!)}',
                    style: TextStyle(
                      color: pedido.orcamentoVencido
                          ? Colors.redAccent
                          : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (!isCancelado && !isOrcamento) ...[
                Row(
                  children: [
                    Text(
                      'Recebido: ${moeda.format(pedido.totalRecebido)}',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    if (!isRecebido)
                      Text(
                        'Falta: ${moeda.format(falta)}',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pedido.totalGeral > 0
                        ? (pedido.totalRecebido / pedido.totalGeral).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 5,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isRecebido ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () => _mostrarDetalhes(pedido),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Ver'),
                    style: TextButton.styleFrom(foregroundColor: Colors.lightBlueAccent),
                  ),
                  TextButton.icon(
                    onPressed: () => _mostrarMenuImpressao(pedido),
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Imprimir'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  ),
                  TextButton.icon(
                    onPressed: () => _abrirLancamento(servico: pedido),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                  if (isOrcamento)
                    ElevatedButton.icon(
                      onPressed: () => _aprovarOrcamento(pedido),
                      icon: const Icon(Icons.thumb_up, size: 16),
                      label: const Text('Aprovar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (!isCancelado && !isOrcamento && !isRecebido)
                    ElevatedButton.icon(
                      onPressed: () => _abrirRecebimento(pedido),
                      icon: const Icon(Icons.payments, size: 16),
                      label: const Text('Receber'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
}

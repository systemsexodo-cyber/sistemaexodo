import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/orcamento.dart';
import '../services/data_service.dart';
import '../services/pedido_impressao_service.dart';
import '../theme.dart';
import 'lancar_pedido_page.dart';
import '../widgets/pedido_detalhes_dialog.dart';

/// Tela de Orçamentos de pedido (série ORC-).
///
/// Fica ao lado da tela de Pedidos central: aqui vivem as **propostas** feitas
/// para o cliente, com validade. Um orçamento não é um pedido — não aparece no
/// PDV, nos recebíveis nem nos relatórios de venda. Ao ser aprovado, gera um
/// pedido de verdade (PED-) e guarda o vínculo.
class OrcamentosPage extends StatefulWidget {
  const OrcamentosPage({super.key});

  @override
  State<OrcamentosPage> createState() => _OrcamentosPageState();
}

class _OrcamentosPageState extends State<OrcamentosPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _buscaController = TextEditingController();
  String _termoBusca = '';
  int _abaAtual = 0;
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  String? _periodoRapido;

  static const _coresAba = [
    Colors.purpleAccent,
    Colors.greenAccent,
    Colors.redAccent,
    Colors.blueAccent,
  ];

  final _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');
  final _formatoDia = DateFormat('dd/MM/yyyy');

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

  bool _aberto(Orcamento o) => o.aberto;
  bool _aprovado(Orcamento o) => o.aprovado;
  bool _encerrado(Orcamento o) => o.recusado || o.cancelado;

  /// Orçamentos que batem com a busca e com o período escolhido.
  List<Orcamento> _filtrar(List<Orcamento> orcamentos) {
    var lista = orcamentos;

    if (_dataInicioFiltro != null || _dataFimFiltro != null) {
      final inicio = _dataInicioFiltro != null
          ? DateTime(_dataInicioFiltro!.year, _dataInicioFiltro!.month,
              _dataInicioFiltro!.day)
          : null;
      final fim = _dataFimFiltro != null
          ? DateTime(_dataFimFiltro!.year, _dataFimFiltro!.month,
              _dataFimFiltro!.day, 23, 59, 59)
          : null;
      lista = lista.where((o) {
        if (inicio != null && o.dataOrcamento.isBefore(inicio)) return false;
        if (fim != null && o.dataOrcamento.isAfter(fim)) return false;
        return true;
      }).toList();
    }

    final busca = _termoBusca.trim().toLowerCase();
    if (busca.isEmpty) return lista;
    return lista.where((o) {
      if ((o.clienteNome ?? '').toLowerCase().contains(busca)) return true;
      if (o.numero.toLowerCase().contains(busca)) return true;
      if ((o.pedidoGeradoNumero ?? '').toLowerCase().contains(busca)) {
        return true;
      }
      if ((o.observacoes ?? '').toLowerCase().contains(busca)) return true;
      return o.itens.any((i) => i.nome.toLowerCase().contains(busca)) ||
          o.servicos.any((s) => s.descricao.toLowerCase().contains(busca));
    }).toList();
  }

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
      default:
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
            primary: Colors.purple,
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
        if (_dataFimFiltro != null &&
            _dataInicioFiltro!.isAfter(_dataFimFiltro!)) {
          _dataFimFiltro = _dataInicioFiltro;
        }
      } else {
        _dataFimFiltro = data;
        if (_dataInicioFiltro != null &&
            _dataFimFiltro!.isBefore(_dataInicioFiltro!)) {
          _dataInicioFiltro = _dataFimFiltro;
        }
      }
    });
  }

  Future<void> _abrirLancamento({Orcamento? orcamento}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => orcamento == null
            ? const LancarPedidoPage(modoOrcamento: true)
            : LancarPedidoPage(
                modoOrcamento: true,
                orcamentoExistente: orcamento,
              ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Aprovar = o cliente aceitou a proposta. O orçamento continua sendo
  /// orçamento (com o número ORC-) e NÃO gera pedido — isso vem depois.
  Future<void> _aprovar(Orcamento orcamento) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Aprovar ${orcamento.numero}?'),
        content: Text(
          'O orçamento fica como APROVADO, mantendo o número ${orcamento.numero} '
          'no valor de ${_moeda.format(orcamento.totalGeral)}.\n\n'
          'Nenhum pedido é criado agora: use "Gerar pedido" quando quiser emitir '
          'o pedido deste orçamento.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.thumb_up),
            label: const Text('Aprovar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final aprovado = await dataService.aprovarOrcamento(orcamento.id);
    if (!mounted) return;

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(aprovado == null
            ? 'Não foi possível aprovar este orçamento'
            : 'Orçamento ${aprovado.numero} aprovado — use "Gerar pedido" para emitir o pedido'),
        backgroundColor: aprovado == null ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Gerar pedido = emite o Pedido (PED-) de um orçamento JÁ APROVADO.
  Future<void> _gerarPedido(Orcamento orcamento) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Gerar pedido de ${orcamento.numero}?'),
        content: Text(
          'O pedido recebe um número próprio (PED-) e entra na tela de Pedidos '
          'para ser recebido, com ${orcamento.quantidadeItens.toStringAsFixed(0)} '
          'item(ns) no valor de ${_moeda.format(orcamento.totalGeral)}.\n\n'
          'O orçamento ${orcamento.numero} continua registrado como aprovado, '
          'com o número do pedido gerado.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Gerar pedido'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final pedido = await dataService.gerarPedidoDoOrcamento(orcamento.id);
    if (!mounted) return;

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pedido == null
            ? 'Não foi possível gerar o pedido deste orçamento'
            : 'Orçamento ${orcamento.numero} → pedido ${pedido.numero} gerado'),
        backgroundColor: pedido == null ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Reabre um orçamento recusado/cancelado para proposta em aberto.
  Future<void> _reabrir(Orcamento orcamento) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    await dataService.reabrirOrcamento(orcamento.id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _mudarStatus(Orcamento orcamento, String novoStatus) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    if (novoStatus == Orcamento.statusRecusado) {
      await dataService.recusarOrcamento(orcamento.id);
    } else {
      await dataService.cancelarOrcamento(orcamento.id);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Orçamento ${orcamento.numero} marcado como $novoStatus'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _mostrarDetalhes(Orcamento orcamento) {
    mostrarDetalhesPedido(
      context,
      orcamento.toPedido(),
      rotuloStatusOverride: orcamento.statusExibicao,
      corStatusOverride: _corStatus(orcamento),
      onImprimir: () => _imprimir(orcamento),
      onEditar: () => _abrirLancamento(orcamento: orcamento),
      rotuloAprovar: orcamento.aberto
          ? 'Aprovar'
          : (orcamento.podeGerarPedido ? 'Gerar pedido' : null),
      onAprovar: orcamento.aberto
          ? () => _aprovar(orcamento)
          : (orcamento.podeGerarPedido ? () => _gerarPedido(orcamento) : null),
      onReceber: null,
    );
  }

  void _imprimir(Orcamento orcamento) {
    PedidoImpressaoService.mostrarMenuImpressao(
      context,
      orcamento.toPedido(),
      incluirRomaneio: orcamento.deliveryInfo != null,
    );
  }

  Color _corStatus(Orcamento orcamento) {
    if (orcamento.aprovado) return Colors.greenAccent;
    if (orcamento.recusado) return Colors.redAccent;
    if (orcamento.cancelado) return Colors.white54;
    return orcamento.orcamentoVencido ? Colors.deepOrangeAccent : Colors.purpleAccent;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);

    final todos = List<Orcamento>.from(dataService.orcamentos)
      ..sort((a, b) => b.dataOrcamento.compareTo(a.dataOrcamento));

    final filtrados = _filtrar(todos);
    final abertos = filtrados.where(_aberto).toList();
    final aprovados = filtrados.where(_aprovado).toList();
    final encerrados = filtrados.where(_encerrado).toList();

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Orçamentos'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _abrirLancamento(),
              tooltip: 'Novo Orçamento',
            ),
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
                  hintText: 'Buscar por cliente, número, produto ou pedido...',
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
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: _coresAba[_abaAtual],
              tabs: [
                Tab(text: 'Abertos (${abertos.length})'),
                Tab(text: 'Aprovados (${aprovados.length})'),
                Tab(text: 'Recusados/Cancelados (${encerrados.length})'),
                Tab(text: 'Todos (${filtrados.length})'),
              ],
            ),
            _buildResumo(abertos, aprovados, filtrados),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLista(abertos, 'Nenhum orçamento em aberto'),
                  _buildLista(aprovados, 'Nenhum orçamento aprovado'),
                  _buildLista(encerrados, 'Nenhum orçamento recusado ou cancelado'),
                  _buildLista(filtrados, 'Nenhum orçamento encontrado'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroPeriodo() {
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
              Icon(Icons.calendar_today, size: 16, color: Colors.purple),
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
                ? _formatoDia.format(_dataInicioFiltro!)
                : 'Data inicial',
            temData: _dataInicioFiltro != null,
            onTap: () => _selecionarDataFiltro(true),
          ),
          const Text('até', style: TextStyle(color: Colors.white54, fontSize: 12)),
          _botaoData(
            _dataFimFiltro != null
                ? _formatoDia.format(_dataFimFiltro!)
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
                foregroundColor: Colors.purpleAccent,
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
              ? Colors.purple.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selecionado ? Colors.purpleAccent : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selecionado ? Colors.purpleAccent : Colors.white70,
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
          color: Colors.purple.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, size: 14, color: Colors.purpleAccent),
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
    List<Orcamento> abertos,
    List<Orcamento> aprovados,
    List<Orcamento> todos,
  ) {
    final emProposta = abertos.fold<double>(0.0, (s, o) => s + o.totalGeral);
    final totalAprovado = aprovados.fold<double>(0.0, (s, o) => s + o.totalGeral);
    final totalGeral = todos.fold<double>(0.0, (s, o) => s + o.totalGeral);
    final vencidos = abertos.where((o) => o.orcamentoVencido).length;

    late final String texto;
    late final Color cor;
    switch (_abaAtual) {
      case 1:
        final semPedido = aprovados.where((o) => !o.temPedidoGerado).length;
        texto = '${aprovados.length} aprovado(s) • ${_moeda.format(totalAprovado)}'
            '${semPedido > 0 ? ' • $semPedido aguardando "Gerar pedido"' : ''}';
        cor = Colors.greenAccent;
        break;
      case 2:
      case 3:
        texto = '${todos.length} orçamento(s) • ${_moeda.format(totalGeral)}';
        cor = Colors.blueAccent;
        break;
      default:
        texto = '${abertos.length} em aberto • ${_moeda.format(emProposta)} em proposta'
            '${vencidos > 0 ? ' • $vencidos vencido(s)' : ''}';
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
          Icon(Icons.request_quote, size: 16, color: cor),
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

  Widget _buildLista(List<Orcamento> orcamentos, String vazio) {
    if (orcamentos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.request_quote_outlined,
                size: 56, color: Colors.white.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(vazio,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      cacheExtent: 1000,
      itemCount: orcamentos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCard(orcamentos[index]),
    );
  }

  Widget _buildCard(Orcamento orcamento) {
    final colorScheme = Theme.of(context).colorScheme;
    final corStatus = _corStatus(orcamento);

    final itensVisiveis = orcamento.itens.take(3).toList();
    final restantes = orcamento.itens.length - itensVisiveis.length;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF311B92), Color(0xFF4A148C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corStatus.withOpacity(0.6), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _mostrarDetalhes(orcamento),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    orcamento.numero.isNotEmpty ? orcamento.numero : '#${orcamento.id}',
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
                      orcamento.statusExibicao,
                      style: TextStyle(
                        color: corStatus,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _moeda.format(orcamento.totalGeral),
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
                      (orcamento.clienteNome?.isNotEmpty ?? false)
                          ? orcamento.clienteNome!
                          : 'Consumidor final',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.event, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    _formatoData.format(orcamento.dataOrcamento),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              if (orcamento.validadeOrcamento != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Válido até ${_formatoDia.format(orcamento.validadeOrcamento!)}'
                  '${orcamento.orcamentoVencido ? ' • VENCIDO' : ''}',
                  style: TextStyle(
                    color: orcamento.orcamentoVencido
                        ? Colors.deepOrangeAccent
                        : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
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
                    ...itensVisiveis.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2,
                                size: 12, color: Colors.lightBlueAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${item.quantidade.toStringAsFixed(0)}x ${item.nome}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _moeda.format(item.preco * item.quantidade),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (restantes > 0)
                      Text(
                        '+ $restantes item(ns)',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    if (orcamento.aprovado)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          orcamento.temPedidoGerado
                              ? 'Aprovado • Pedido gerado: ${orcamento.pedidoGeradoNumero}'
                              : 'Aprovado • ainda sem pedido gerado',
                          style: TextStyle(
                            color: orcamento.temPedidoGerado
                                ? Colors.greenAccent
                                : Colors.amberAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () => _mostrarDetalhes(orcamento),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Ver'),
                    style: TextButton.styleFrom(foregroundColor: Colors.lightBlueAccent),
                  ),
                  TextButton.icon(
                    onPressed: () => _imprimir(orcamento),
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Imprimir'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  ),
                  TextButton.icon(
                    onPressed: () => _abrirLancamento(orcamento: orcamento),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                  if (orcamento.aberto) ...[
                    TextButton.icon(
                      onPressed: () => _mudarStatus(orcamento, Orcamento.statusRecusado),
                      icon: const Icon(Icons.thumb_down, size: 16),
                      label: const Text('Recusar'),
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _aprovar(orcamento),
                      icon: const Icon(Icons.thumb_up, size: 16),
                      label: const Text('Aprovar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else if (orcamento.podeGerarPedido)
                    ElevatedButton.icon(
                      onPressed: () => _gerarPedido(orcamento),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('Gerar pedido'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    )
                  else if (orcamento.temPedidoGerado)
                    TextButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: Text('Pedido ${orcamento.pedidoGeradoNumero}'),
                      style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => _reabrir(orcamento),
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Reabrir'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
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

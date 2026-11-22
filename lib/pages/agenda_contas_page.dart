import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'conta_pagar_form_page.dart';

class AgendaContasPage extends StatefulWidget {
  const AgendaContasPage({super.key});

  @override
  State<AgendaContasPage> createState() => _AgendaContasPageState();
}

class _AgendaContasPageState extends State<AgendaContasPage> {
  static const Color _corCard = Color(0xFF1A1F26);
  static const Color _corBorda = Color(0x14FFFFFF);

  DateTime _dataInicioSemana = DateTime.now();
  DateFormat? _formatoData;
  DateFormat? _formatoDiaSemana;
  final NumberFormat _formatoMoeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _localeInicializado = false;

  // Filtros
  bool _modoTodas = false; // false = semana selecionada, true = todas as contas
  bool _somenteVencidas = false;
  bool _incluirPagas = false;
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _ajustarParaInicioSemana();
    _inicializarLocale();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _inicializarLocale() async {
    await initializeDateFormatting('pt_BR', null);
    if (mounted) {
      setState(() {
        _formatoData = DateFormat('dd/MM/yyyy', 'pt_BR');
        _formatoDiaSemana = DateFormat('EEEE', 'pt_BR');
        _localeInicializado = true;
      });
    }
  }

  void _ajustarParaInicioSemana() {
    final hoje = DateTime.now();
    final diasDesdeSegunda = hoje.weekday - 1;
    final inicio = hoje.subtract(Duration(days: diasDesdeSegunda));
    _dataInicioSemana = DateTime(inicio.year, inicio.month, inicio.day);
  }

  DateTime get _fimSemana => _dataInicioSemana.add(const Duration(days: 6));

  void _irParaSemanaAnterior() {
    setState(() {
      _dataInicioSemana = _dataInicioSemana.subtract(const Duration(days: 7));
    });
  }

  void _irParaProximaSemana() {
    setState(() {
      _dataInicioSemana = _dataInicioSemana.add(const Duration(days: 7));
    });
  }

  void _irParaSemanaAtual() {
    setState(() {
      _ajustarParaInicioSemana();
      _modoTodas = false;
    });
  }

  String _getTituloPeriodo() {
    if (_modoTodas) return 'Todas as contas';
    final fim = _fimSemana;
    if (!_localeInicializado || _formatoData == null) {
      return '${_dataInicioSemana.day}/${_dataInicioSemana.month} - ${fim.day}/${fim.month}';
    }
    return '${_formatoData!.format(_dataInicioSemana)} - ${_formatoData!.format(fim)}';
  }

  String _getNomeDia(int weekday) {
    const dias = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo'
    ];
    return dias[weekday - 1];
  }

  bool _isHoje(DateTime dia) {
    final hoje = DateTime.now();
    return dia.year == hoje.year && dia.month == hoje.month && dia.day == hoje.day;
  }

  DateTime _somenteData(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Contas consideradas na agenda: ativas, não canceladas e sem recebíveis.
  bool _contaBase(ContaPagar c) {
    if (!c.ativo) return false;
    if (c.categoria == 'Recebível') return false;
    if (c.status == StatusContaPagar.cancelado) return false;
    if (c.status == StatusContaPagar.pago && !_incluirPagas) return false;
    return true;
  }

  List<ContaPagar> _contasDoPeriodo(List<ContaPagar> todas) {
    final contas = todas.where(_contaBase).where((c) {
      if (_modoTodas) return true;
      final venc = _somenteData(c.dataVencimento);
      return !venc.isBefore(_dataInicioSemana) &&
          !venc.isAfter(_fimSemana);
    }).toList();
    contas.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    return contas;
  }

  List<ContaPagar> _contasExibidas(List<ContaPagar> doPeriodo) {
    final termo = _busca.trim().toLowerCase();
    return doPeriodo.where((c) {
      if (_somenteVencidas && !c.isVencida) return false;
      if (termo.isEmpty) return true;
      final descricao = c.descricao.toLowerCase();
      final fornecedor = (c.fornecedorNome ?? '').toLowerCase();
      return descricao.contains(termo) || fornecedor.contains(termo);
    }).toList();
  }

  String _rotuloVencimento(ContaPagar conta) {
    final hoje = _somenteData(DateTime.now());
    final venc = _somenteData(conta.dataVencimento);
    final diff = venc.difference(hoje).inDays;
    if (conta.status == StatusContaPagar.pago) return 'Conta paga';
    if (diff == 0) return 'Vence hoje';
    if (diff == 1) return 'Vence amanhã';
    if (diff > 1) return 'Vence em $diff dias';
    if (diff == -1) return 'Venceu ontem';
    return 'Venceu há ${-diff} dias';
  }

  IconData _iconeCategoria(String? categoria) {
    final c = (categoria ?? '').toLowerCase();
    if (c.contains('aluguel') || c.contains('imóvel')) return Icons.home_work;
    if (c.contains('energia') || c.contains('luz')) return Icons.bolt;
    if (c.contains('água') || c.contains('agua')) return Icons.water_drop;
    if (c.contains('internet') || c.contains('telefone')) return Icons.wifi;
    if (c.contains('salário') || c.contains('salario')) return Icons.groups;
    if (c.contains('imposto') || c.contains('taxa')) return Icons.account_balance;
    if (c.contains('fornecedor') || c.contains('mercadoria')) {
      return Icons.local_shipping;
    }
    if (c.contains('manutenção') || c.contains('manutencao')) {
      return Icons.build;
    }
    if (c.contains('frete')) return Icons.local_shipping;
    return Icons.receipt_long;
  }

  Color _corStatus(ContaPagar conta) {
    if (conta.status == StatusContaPagar.pago) return Colors.green;
    if (conta.isVencida) return Colors.redAccent;
    if (_isHoje(_somenteData(conta.dataVencimento))) return Colors.orangeAccent;
    return const Color(0xFF64B5F6);
  }

  String _textoStatus(ContaPagar conta) {
    if (conta.status == StatusContaPagar.pago) return 'PAGA';
    if (conta.isVencida) return 'VENCIDA';
    if (_isHoje(_somenteData(conta.dataVencimento))) return 'HOJE';
    return 'PENDENTE';
  }

  @override
  Widget build(BuildContext context) {
    if (!_localeInicializado) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Agenda de Contas'),
            backgroundColor: Colors.transparent,
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final dataService = Provider.of<DataService>(context);
    final periodo = _contasDoPeriodo(dataService.contasPagar);
    final exibidas = _contasExibidas(periodo);

    final pendentes = periodo
        .where((c) => c.status != StatusContaPagar.pago)
        .toList();
    final totalPendente = pendentes.fold<double>(
      0,
      (soma, c) => soma + c.valorPendente,
    );
    final vencidas = pendentes.where((c) => c.isVencida).toList();
    final totalVencido =
        vencidas.fold<double>(0, (soma, c) => soma + c.valorPendente);
    final hoje = pendentes
        .where((c) => _isHoje(_somenteData(c.dataVencimento)))
        .toList();

    // Agrupa as contas exibidas por data de vencimento
    final grupos = <DateTime, List<ContaPagar>>{};
    for (final conta in exibidas) {
      final dia = _somenteData(conta.dataVencimento);
      grupos.putIfAbsent(dia, () => []).add(conta);
    }
    final dias = grupos.keys.toList()..sort();

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Agenda de Contas'),
          backgroundColor: Colors.transparent,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Voltar para hoje',
              onPressed: _irParaSemanaAtual,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ContaPagarFormPage(),
              ),
            ).then((_) => setState(() {}));
          },
          icon: const Icon(Icons.add),
          label: const Text('Nova Conta'),
          backgroundColor: Colors.orange,
        ),
        body: Column(
          children: [
            _buildCabecalho(
              totalPendente: totalPendente,
              totalVencido: totalVencido,
              quantidade: pendentes.length,
              quantidadeHoje: hoje.length,
              quantidadeVencida: vencidas.length,
            ),
            _buildBarraFiltros(exibidas.length, pendentes.length),
            Expanded(
              child: exibidas.isEmpty
                  ? _buildVazio(periodo.isEmpty, pendentes.length)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: dias.length,
                      itemBuilder: (context, index) {
                        final dia = dias[index];
                        return _buildGrupoDia(dia, grupos[dia]!);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCabecalho({
    required double totalPendente,
    required double totalVencido,
    required int quantidade,
    required int quantidadeHoje,
    required int quantidadeVencida,
  }) {
    final primaria = Theme.of(context).colorScheme.primary;
    final secundaria = Theme.of(context).colorScheme.secondary;
    final fim = _fimSemana;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(primaria, Colors.black, 0.15)!,
            Color.lerp(secundaria, Colors.black, 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _modoTodas
                  ? const SizedBox(width: 40)
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_left),
                      color: Colors.white,
                      tooltip: 'Semana anterior',
                      onPressed: _irParaSemanaAnterior,
                    ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _modoTodas
                          ? 'Ordenadas por vencimento'
                          : '${_getNomeDia(_dataInicioSemana.weekday)} a ${_getNomeDia(fim.weekday)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getTituloPeriodo(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _modoTodas
                  ? const SizedBox(width: 40)
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right),
                      color: Colors.white,
                      tooltip: 'Próxima semana',
                      onPressed: _irParaProximaSemana,
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCabecalho(
                  'A pagar',
                  _formatoMoeda.format(totalPendente),
                  Icons.account_balance_wallet,
                  Colors.white,
                ),
              ),
              _divisorVertical(),
              Expanded(
                child: _buildStatCabecalho(
                  'Vencido',
                  _formatoMoeda.format(totalVencido),
                  Icons.warning_amber_rounded,
                  Colors.redAccent.shade100,
                  destaque: quantidadeVencida > 0,
                ),
              ),
              _divisorVertical(),
              Expanded(
                child: _buildStatCabecalho(
                  'Contas',
                  quantidade.toString(),
                  Icons.list_alt,
                  Colors.white,
                  rodape: quantidadeHoje > 0
                      ? '$quantidadeHoje vence hoje'
                      : (quantidadeVencida > 0
                          ? '$quantidadeVencida vencida(s)'
                          : null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divisorVertical() => Container(
        width: 1,
        height: 38,
        color: Colors.white.withOpacity(0.15),
      );

  Widget _buildStatCabecalho(
    String titulo,
    String valor,
    IconData icone,
    Color cor, {
    bool destaque = false,
    String? rodape,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 14, color: cor.withOpacity(0.8)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            valor,
            style: TextStyle(
              color: destaque ? cor : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (rodape != null) ...[
          const SizedBox(height: 2),
          Text(
            rodape,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.orangeAccent.withOpacity(0.9),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBarraFiltros(int exibidas, int totalPeriodo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            onChanged: (valor) => setState(() => _busca = valor),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            cursorColor: Theme.of(context).colorScheme.primary,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar por descrição ou fornecedor',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12.5,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: Colors.white.withOpacity(0.5),
              ),
              suffixIcon: _busca.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _busca = '');
                      },
                    ),
              filled: true,
              fillColor: _corCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _corBorda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _corBorda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _corCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _corBorda),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAba(
                          'Semana',
                          !_modoTodas,
                          () => setState(() => _modoTodas = false),
                        ),
                      ),
                      Expanded(
                        child: _buildAba(
                          'Todas',
                          _modoTodas,
                          () => setState(() => _modoTodas = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildChipFiltro(
                'Vencidas',
                _somenteVencidas,
                Colors.redAccent,
                () => setState(() => _somenteVencidas = !_somenteVencidas),
              ),
              const SizedBox(width: 6),
              _buildChipFiltro(
                'Pagas',
                _incluirPagas,
                Colors.greenAccent,
                () => setState(() => _incluirPagas = !_incluirPagas),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 13,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                '$exibidas de $totalPeriodo conta(s) no período',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                'Toque para pagar',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAba(String texto, bool selecionada, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selecionada
              ? Theme.of(context).colorScheme.primary.withOpacity(0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selecionada ? Colors.white : Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildChipFiltro(
    String texto,
    bool selecionado,
    Color cor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selecionado ? cor.withOpacity(0.2) : _corCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado ? cor.withOpacity(0.8) : _corBorda,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selecionado) ...[
              Icon(Icons.check, size: 12, color: cor),
              const SizedBox(width: 3),
            ],
            Text(
              texto,
              style: TextStyle(
                color: selecionado ? cor : Colors.white.withOpacity(0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrupoDia(DateTime dia, List<ContaPagar> contas) {
    final hoje = _isHoje(dia);
    final passado = dia.isBefore(_somenteData(DateTime.now()));
    final qtdPendentes =
        contas.where((c) => c.status != StatusContaPagar.pago).length;
    final todosPagos = qtdPendentes == 0;
    final totalDia = contas
        .where((c) => c.status != StatusContaPagar.pago)
        .fold<double>(0, (soma, c) => soma + c.valorPendente);

    final corDia = todosPagos
        ? Colors.greenAccent
        : (passado ? Colors.redAccent : (hoje ? Colors.orangeAccent : Colors.white));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _corCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hoje
              ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
              : _corBorda,
          width: hoje ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: Colors.white.withOpacity(hoje ? 0.06 : 0.03),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: corDia.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: corDia.withOpacity(0.4)),
                  ),
                  child: Text(
                    dia.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: corDia,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatoDiaSemana?.format(dia) ??
                                _getNomeDia(dia.weekday),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (hoje) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'HOJE',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _formatoData?.format(dia) ??
                            '${dia.day}/${dia.month}/${dia.year}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
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
                      _formatoMoeda.format(totalDia),
                      style: TextStyle(
                        color: todosPagos ? Colors.greenAccent : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${contas.length} ${contas.length == 1 ? 'conta' : 'contas'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ...contas.asMap().entries.map((entry) {
            final index = entry.key;
            final conta = entry.value;
            return Column(
              children: [
                if (index > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withOpacity(0.06),
                  ),
                _buildContaTile(conta),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContaTile(ContaPagar conta) {
    final cor = _corStatus(conta);
    final pago = conta.status == StatusContaPagar.pago;
    final valor = pago ? conta.valor : conta.valorPendente;
    final parcial =
        !pago && (conta.valorPago ?? 0) > 0 && conta.valorPendente < conta.valor;

    return InkWell(
      onTap: () => _mostrarDialogoPagamento(context, conta),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: cor.withOpacity(0.85), width: 3),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                conta.isVencida ? Icons.warning_amber_rounded : _iconeCategoria(conta.categoria),
                color: cor,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conta.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: pago ? Colors.white.withOpacity(0.65) : Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      decoration: pago ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (conta.categoria != null) ...[
                        Flexible(
                          child: Text(
                            conta.categoria!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        if (conta.fornecedorNome != null)
                          Text(
                            '  •  ',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                      if (conta.fornecedorNome != null)
                        Flexible(
                          child: Text(
                            conta.fornecedorNome!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 11, color: cor.withOpacity(0.8)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          _rotuloVencimento(conta),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cor.withOpacity(0.9),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (conta.notaEntradaNumero != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.receipt,
                          size: 10,
                          color: Colors.orangeAccent.withOpacity(0.8),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          conta.notaEntradaNumero!,
                          style: TextStyle(
                            color: Colors.orangeAccent.withOpacity(0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatoMoeda.format(valor),
                  style: TextStyle(
                    color: pago ? Colors.white.withOpacity(0.6) : cor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (parcial)
                  Text(
                    'de ${_formatoMoeda.format(conta.valor)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 9.5,
                    ),
                  ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _textoStatus(conta),
                    style: TextStyle(
                      color: cor,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white.withOpacity(0.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVazio(bool periodoVazio, int totalPendentes) {
    final mensagem = periodoVazio
        ? (_modoTodas
            ? 'Nenhuma conta em aberto'
            : 'Nenhuma conta para esta semana')
        : 'Nenhuma conta encontrada com os filtros atuais';
    final subtitulo = periodoVazio && !_modoTodas && totalPendentes > 0
        ? 'Você tem $totalPendentes conta(s) em aberto em outras datas.'
        : (_modoTodas
            ? 'Tudo em dia por aqui.'
            : 'Use as setas para navegar entre as semanas.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: _corBorda),
              ),
              child: Icon(
                periodoVazio ? Icons.event_available : Icons.filter_alt_off,
                size: 34,
                color: Colors.white.withOpacity(0.45),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (periodoVazio && !_modoTodas)
                  FilledButton.icon(
                    onPressed: () => setState(() => _modoTodas = true),
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('Ver todas as contas'),
                  ),
                if (!periodoVazio)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _somenteVencidas = false;
                      _incluirPagas = false;
                      _buscaController.clear();
                      _busca = '';
                    }),
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('Limpar filtros'),
                  ),
                if (periodoVazio && !_modoTodas)
                  OutlinedButton.icon(
                    onPressed: _irParaSemanaAtual,
                    icon: const Icon(Icons.today, size: 18),
                    label: const Text('Semana atual'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = _formatoData ?? DateFormat('dd/MM/yyyy');

    final valorPendente = conta.valorPendente;
    final valorController = TextEditingController(
      text: valorPendente.toStringAsFixed(2).replaceAll('.', ','),
    );
    final observacaoController = TextEditingController();
    DateTime dataPagamento = DateTime.now();
    TipoPagamento? formaPagamento;
    final corPrimaria = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payment, color: Colors.greenAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Registrar Pagamento'),
                    Text(
                      conta.descricao,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: corPrimaria.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: corPrimaria.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description, color: corPrimaria, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              conta.descricao,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (conta.categoria != null) ...[
                        Row(
                          children: [
                            Icon(Icons.category,
                                size: 14, color: Colors.white.withOpacity(0.6)),
                            const SizedBox(width: 6),
                            Text(
                              'Categoria: ${conta.categoria}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                      ],
                      if (conta.fornecedorNome != null) ...[
                        Row(
                          children: [
                            Icon(Icons.business,
                                size: 14, color: Colors.white.withOpacity(0.6)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Fornecedor: ${conta.fornecedorNome}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                      ],
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 14, color: Colors.white.withOpacity(0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Vencimento: ${formatoData.format(conta.dataVencimento)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: Colors.white.withOpacity(0.1), height: 1),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Valor Total',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                formatoMoeda.format(conta.valor),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (conta.valorPago != null && conta.valorPago! > 0) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Já Pago',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  formatoMoeda.format(conta.valorPago!),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Valor Pendente:',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              formatoMoeda.format(valorPendente),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: valorController,
                  decoration: InputDecoration(
                    labelText: 'Valor a Pagar (pode ser parcial)',
                    prefixText: 'R\$ ',
                    border: const OutlineInputBorder(),
                    helperText:
                        'Valor pendente: ${formatoMoeda.format(valorPendente)}',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataPagamento,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setState(() {
                        dataPagamento = data;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data de Pagamento',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(formatoData.format(dataPagamento)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<TipoPagamento>(
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pagamento',
                    border: OutlineInputBorder(),
                  ),
                  value: formaPagamento,
                  items: TipoPagamento.values.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(tipo.nome),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      formaPagamento = value;
                    });
                  },
                  hint: const Text('Selecione a forma de pagamento'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: observacaoController,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                String valorTexto = valorController.text.trim();
                valorTexto = valorTexto.replaceAll(RegExp(r'[^\d,.]'), '');

                if (valorTexto.contains(',')) {
                  valorTexto = valorTexto.replaceAll('.', '');
                  valorTexto = valorTexto.replaceAll(',', '.');
                }

                if (!valorTexto.contains('.')) {
                  valorTexto = '$valorTexto.00';
                }

                final valorPago = double.tryParse(valorTexto);

                if (valorPago == null || valorPago <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Por favor, informe um valor válido maior que zero'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (valorPago > valorPendente + 0.01) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'O valor não pode ser maior que o pendente (${formatoMoeda.format(valorPendente)})'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final novoValorPago = (conta.valorPago ?? 0.0) + valorPago;
                final novoStatus = (novoValorPago >= conta.valor - 0.01)
                    ? StatusContaPagar.pago
                    : conta.status;

                final novoRegistro = RegistroPagamento(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  valor: valorPago,
                  dataPagamento: dataPagamento,
                  formaPagamento: formaPagamento?.nome,
                  observacao: observacaoController.text.isEmpty
                      ? null
                      : observacaoController.text,
                );

                final novoHistorico =
                    List<RegistroPagamento>.from(conta.historicoPagamentos)
                      ..add(novoRegistro);

                final contaAtualizada = ContaPagar(
                  id: conta.id,
                  numero: conta.numero,
                  tipo: conta.tipo,
                  categoria: conta.categoria,
                  descricao: conta.descricao,
                  observacoes: observacaoController.text.isEmpty
                      ? conta.observacoes
                      : '${conta.observacoes ?? ''}\n${observacaoController.text}'
                          .trim(),
                  valor: conta.valor,
                  valorPago: novoValorPago,
                  dataVencimento: conta.dataVencimento,
                  dataPagamento: novoStatus == StatusContaPagar.pago
                      ? dataPagamento
                      : conta.dataPagamento,
                  dataCriacao: conta.dataCriacao,
                  updatedAt: DateTime.now(),
                  notaEntradaId: conta.notaEntradaId,
                  notaEntradaNumero: conta.notaEntradaNumero,
                  fornecedorId: conta.fornecedorId,
                  fornecedorNome: conta.fornecedorNome,
                  status: novoStatus,
                  formaPagamento:
                      formaPagamento?.nome ?? conta.formaPagamento,
                  historicoPagamentos: novoHistorico,
                  recorrente: conta.recorrente,
                  intervaloRecorrencia: conta.intervaloRecorrencia,
                  proximaDataRecorrencia: conta.proximaDataRecorrencia,
                  ativo: conta.ativo,
                  usuarioCriacao: conta.usuarioCriacao,
                  usuarioPagamento: conta.usuarioPagamento,
                );

                dataService.updateContaPagar(contaAtualizada);

                Navigator.pop(context);

                if (mounted) {
                  setState(() {});
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          novoStatus == StatusContaPagar.pago
                              ? '✓ Conta paga com sucesso!'
                              : '✓ Pagamento parcial registrado!',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Conta: ${conta.descricao}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        Text(
                          'Valor pago: ${formatoMoeda.format(valorPago)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 4),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar Pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}

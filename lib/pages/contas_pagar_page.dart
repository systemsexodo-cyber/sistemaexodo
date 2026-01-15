import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'conta_pagar_form_page.dart';

class ContasPagarPage extends StatefulWidget {
  const ContasPagarPage({super.key});

  @override
  State<ContasPagarPage> createState() => _ContasPagarPageState();
}

class _ContasPagarPageState extends State<ContasPagarPage> {
  String _filtroStatus = 'Todos';
  String _filtroTipo = 'Todos';
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  bool _mostrarBusca = false;
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  bool _mostrarVencidas = true;
  bool _mostrarPagas = false;

  final List<String> _statusDisponiveis = [
    'Todos',
    'Pendente',
    'Vencido',
    'Pago',
    'Cancelado',
  ];

  final List<String> _tiposDisponiveis = [
    'Todos',
    'Nota de Entrada',
    'Despesa Fixa',
    'Despesa Variável',
  ];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<ContaPagar> _filtrarContas(List<ContaPagar> contas) {
    var resultado = contas.where((c) => c.ativo).toList();

    // Filtro por status
    if (_filtroStatus != 'Todos') {
      resultado = resultado.where((c) {
        final statusAtual = c.statusAtualizado;
        switch (_filtroStatus) {
          case 'Pendente':
            return statusAtual == StatusContaPagar.pendente;
          case 'Vencido':
            return statusAtual == StatusContaPagar.vencido;
          case 'Pago':
            return statusAtual == StatusContaPagar.pago;
          case 'Cancelado':
            return statusAtual == StatusContaPagar.cancelado;
          default:
            return true;
        }
      }).toList();
    } else {
      if (!_mostrarVencidas) {
        resultado = resultado.where((c) => !c.isVencida).toList();
      }
      if (!_mostrarPagas) {
        resultado = resultado.where((c) => c.status != StatusContaPagar.pago).toList();
      }
    }

    // Filtro por tipo
    if (_filtroTipo != 'Todos') {
      resultado = resultado.where((c) {
        switch (_filtroTipo) {
          case 'Nota de Entrada':
            return c.tipo == TipoContaPagar.notaEntrada;
          case 'Despesa Fixa':
            return c.tipo == TipoContaPagar.despesaFixa;
          case 'Despesa Variável':
            return c.tipo == TipoContaPagar.despesaVariavel;
          default:
            return true;
        }
      }).toList();
    }

    // Filtro por data
    if (_dataInicioFiltro != null) {
      resultado = resultado.where((c) {
        final dataVenc = DateTime(
          c.dataVencimento.year,
          c.dataVencimento.month,
          c.dataVencimento.day,
        );
        final dataInicio = DateTime(
          _dataInicioFiltro!.year,
          _dataInicioFiltro!.month,
          _dataInicioFiltro!.day,
        );
        return dataVenc.isAfter(dataInicio) || dataVenc.isAtSameMomentAs(dataInicio);
      }).toList();
    }

    if (_dataFimFiltro != null) {
      resultado = resultado.where((c) {
        final dataVenc = DateTime(
          c.dataVencimento.year,
          c.dataVencimento.month,
          c.dataVencimento.day,
        );
        final dataFim = DateTime(
          _dataFimFiltro!.year,
          _dataFimFiltro!.month,
          _dataFimFiltro!.day,
        ).add(const Duration(days: 1));
        return dataVenc.isBefore(dataFim);
      }).toList();
    }

    // Filtro por busca
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.toLowerCase();
      resultado = resultado.where((c) {
        return c.descricao.toLowerCase().contains(termo) ||
            (c.numero?.toLowerCase().contains(termo) ?? false) ||
            (c.fornecedorNome?.toLowerCase().contains(termo) ?? false) ||
            (c.categoria?.toLowerCase().contains(termo) ?? false) ||
            (c.notaEntradaNumero?.toLowerCase().contains(termo) ?? false);
      }).toList();
    }

    // Ordenar por vencimento (mais próximas primeiro)
    resultado.sort((a, b) {
      if (a.isVencida && !b.isVencida) return -1;
      if (!a.isVencida && b.isVencida) return 1;
      return a.dataVencimento.compareTo(b.dataVencimento);
    });

    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);
    final contas = _filtrarContas(dataService.contasPagar);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Calcular totais
    final totalPendente = contas
        .where((c) => c.statusAtualizado == StatusContaPagar.pendente)
        .fold<double>(0.0, (sum, c) => sum + c.valorPendente);
    
    final totalVencido = contas
        .where((c) => c.statusAtualizado == StatusContaPagar.vencido)
        .fold<double>(0.0, (sum, c) => sum + c.valorPendente);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Contas a Pagar'),
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
            IconButton(
              icon: Icon(
                _mostrarBusca ? Icons.search_off : Icons.search,
                color: _mostrarBusca
                    ? Colors.greenAccent
                    : Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                setState(() {
                  _mostrarBusca = !_mostrarBusca;
                  if (!_mostrarBusca) {
                    _termoBusca = '';
                    _buscaController.clear();
                  }
                });
              },
            ),
            PopupMenuButton<String>(
              icon: Stack(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  if (_filtroStatus != 'Todos' || _filtroTipo != 'Todos')
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onSelected: (value) {
                if (value.startsWith('status:')) {
                  setState(() => _filtroStatus = value.substring(7));
                } else if (value.startsWith('tipo:')) {
                  setState(() => _filtroTipo = value.substring(5));
                } else if (value == 'data') {
                  _selecionarPeriodo();
                } else if (value == 'mostrar_vencidas') {
                  setState(() => _mostrarVencidas = !_mostrarVencidas);
                } else if (value == 'mostrar_pagas') {
                  setState(() => _mostrarPagas = !_mostrarPagas);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'header_status',
                  enabled: false,
                  child: Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ..._statusDisponiveis.map((status) => PopupMenuItem(
                      value: 'status:$status',
                      child: Row(
                        children: [
                          if (_filtroStatus == status)
                            const Icon(Icons.check, size: 20, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(status),
                        ],
                      ),
                    )),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'header_tipo',
                  enabled: false,
                  child: Text('Tipo:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ..._tiposDisponiveis.map((tipo) => PopupMenuItem(
                      value: 'tipo:$tipo',
                      child: Row(
                        children: [
                          if (_filtroTipo == tipo)
                            const Icon(Icons.check, size: 20, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(tipo),
                        ],
                      ),
                    )),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'data',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20),
                      SizedBox(width: 8),
                      Text('Filtrar por Período'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'mostrar_vencidas',
                  child: Row(
                    children: [
                      Icon(
                        _mostrarVencidas ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('Mostrar Vencidas'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'mostrar_pagas',
                  child: Row(
                    children: [
                      Icon(
                        _mostrarPagas ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('Mostrar Pagas'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_mostrarBusca)
              Container(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _buscaController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar por descrição, fornecedor, categoria...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _termoBusca.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              setState(() {
                                _termoBusca = '';
                                _buscaController.clear();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => setState(() => _termoBusca = value),
                ),
              ),

            // Dashboard de resumo
            Container(
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
                        child: _buildCardResumo(
                          'Pendente',
                          formatoMoeda.format(totalPendente),
                          Colors.orange,
                          Icons.pending,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCardResumo(
                          'Vencido',
                          formatoMoeda.format(totalVencido),
                          Colors.red,
                          Icons.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCardResumo(
                          'Total',
                          '${contas.length}',
                          Colors.blue,
                          Icons.list,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCardResumo(
                          'Próximo Venc.',
                          contas.isNotEmpty && contas.first.isProximoVencimento
                              ? formatoData.format(contas.first.dataVencimento)
                              : '-',
                          Colors.cyan,
                          Icons.calendar_today,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Lista de contas
            Expanded(
              child: contas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma conta encontrada',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: contas.length,
                      itemBuilder: (context, index) {
                        return _buildCardConta(contas[index], formatoMoeda, formatoData);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ContaPagarFormPage(),
              ),
            ).then((_) => setState(() {}));
          },
          icon: const Icon(Icons.add),
          label: const Text('Nova Conta'),
          backgroundColor: Colors.orange,
        ),
      ),
    );
  }

  Widget _buildCardResumo(String titulo, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardConta(ContaPagar conta, NumberFormat formatoMoeda, DateFormat formatoData) {
    final statusAtual = conta.statusAtualizado;
    final isVencida = conta.isVencida;
    final isProximoVenc = conta.isProximoVencimento;
    
    Color corCard;
    Color corBorda;
    IconData iconeStatus;
    
    if (statusAtual == StatusContaPagar.pago) {
      corCard = Colors.green.withOpacity(0.2);
      corBorda = Colors.green;
      iconeStatus = Icons.check_circle;
    } else if (isVencida) {
      corCard = Colors.red.withOpacity(0.2);
      corBorda = Colors.red;
      iconeStatus = Icons.error;
    } else if (isProximoVenc) {
      corCard = Colors.orange.withOpacity(0.2);
      corBorda = Colors.orange;
      iconeStatus = Icons.warning;
    } else {
      corCard = Colors.blue.withOpacity(0.2);
      corBorda = Colors.blue;
      iconeStatus = Icons.pending;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContaPagarFormPage(contaPagar: conta),
          ),
        ).then((_) => setState(() {}));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: corCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: corBorda.withOpacity(0.5), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: corBorda.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconeStatus, color: corBorda, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conta.descricao,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (conta.categoria != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          conta.categoria!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatoMoeda.format(conta.valor),
                      style: TextStyle(
                        color: corBorda,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (statusAtual != StatusContaPagar.pago && conta.valorPendente < conta.valor)
                      Text(
                        'Pendente: ${formatoMoeda.format(conta.valorPendente)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  'Vencimento: ${formatoData.format(conta.dataVencimento)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: corBorda.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusAtual.nome,
                    style: TextStyle(
                      color: corBorda,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (conta.fornecedorNome != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.business,
                    size: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    conta.fornecedorNome!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            if (conta.notaEntradaNumero != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.receipt,
                    size: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Nota: ${conta.notaEntradaNumero}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            // Botão de pagar (se pendente ou vencida)
            if (statusAtual != StatusContaPagar.pago && statusAtual != StatusContaPagar.cancelado) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarDialogoPagamento(context, conta),
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text(
                    conta.valorPendente < conta.valor 
                      ? 'Pagar R\$ ${formatoMoeda.format(conta.valorPendente)}'
                      : 'Pagar (pode ser parcial)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
            // Histórico de pagamentos
            if (conta.historicoPagamentos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history, color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Histórico de Pagamentos (${conta.historicoPagamentos.length})',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...conta.historicoPagamentos.reversed.map((pagamento) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.payment,
                              size: 16,
                              color: Colors.white.withOpacity(0.8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatoData.format(pagamento.dataPagamento),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        formatoMoeda.format(pagamento.valor),
                                        style: TextStyle(
                                          color: Colors.green[300],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (pagamento.formaPagamento != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Forma: ${pagamento.formaPagamento}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                  if (pagamento.observacao != null && pagamento.observacao!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      pagamento.observacao!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 9,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.undo,
                                size: 18,
                                color: Colors.orange,
                              ),
                              tooltip: 'Estornar pagamento',
                              onPressed: () => _estornarPagamento(context, conta, pagamento),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
            // Informação de pagamento (se já pago totalmente - para compatibilidade)
            if (statusAtual == StatusContaPagar.pago && 
                conta.dataPagamento != null && 
                conta.historicoPagamentos.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pago em ${formatoData.format(conta.dataPagamento!)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (conta.formaPagamento != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Forma: ${conta.formaPagamento}',
                              style: TextStyle(
                                color: Colors.green.withOpacity(0.8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selecionarPeriodo() async {
    final DateTime? dataInicio = await showDatePicker(
      context: context,
      initialDate: _dataInicioFiltro ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orange,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataInicio != null) {
      final DateTime? dataFim = await showDatePicker(
        context: context,
        initialDate: _dataFimFiltro ?? dataInicio,
        firstDate: dataInicio,
        lastDate: DateTime(2100),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.orange,
                onPrimary: Colors.white,
                surface: Color(0xFF1E1E2E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (dataFim != null) {
        setState(() {
          _dataInicioFiltro = dataInicio;
          _dataFimFiltro = dataFim;
        });
      }
    }
  }

  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');
    
    final valorPendente = conta.valorPendente;
    final valorController = TextEditingController(
      text: valorPendente.toStringAsFixed(2).replaceAll('.', ','),
    );
    final observacaoController = TextEditingController();
    DateTime dataPagamento = DateTime.now();
    TipoPagamento? formaPagamento;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.payment, color: Colors.green),
              SizedBox(width: 8),
              Text('Registrar Pagamento'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conta.descricao,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Valor total: ${formatoMoeda.format(conta.valor)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                if (conta.valorPago != null && conta.valorPago! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Já pago: ${formatoMoeda.format(conta.valorPago!)}',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                
                // Valor a pagar
                TextFormField(
                  controller: valorController,
                  decoration: InputDecoration(
                    labelText: 'Valor a Pagar (pode ser parcial)',
                    prefixText: 'R\$ ',
                    border: const OutlineInputBorder(),
                    helperText: 'Valor pendente: ${formatoMoeda.format(valorPendente)}',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    // Remove formatação para validação
                    String valorLimpo = value.replaceAll(RegExp(r'[^\d,.]'), '');
                    // Garante que há apenas uma vírgula ou ponto
                    if (valorLimpo.contains(',')) {
                      valorLimpo = valorLimpo.replaceAll('.', '');
                      valorLimpo = valorLimpo.replaceAll(',', '.');
                    }
                    final valor = double.tryParse(valorLimpo) ?? 0.0;
                    if (valor > valorPendente) {
                      valorController.text = valorPendente.toStringAsFixed(2).replaceAll('.', ',');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Valor máximo: ${formatoMoeda.format(valorPendente)}'),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                // Data de pagamento
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
                const SizedBox(height: 16),
                
                // Forma de pagamento
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
                const SizedBox(height: 16),
                
                // Observações
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
                // Processar valor - melhor parsing
                String valorTexto = valorController.text.trim();
                // Remove espaços e caracteres especiais, mantendo apenas números, vírgula e ponto
                valorTexto = valorTexto.replaceAll(RegExp(r'[^\d,.]'), '');
                
                // Trata vírgula como separador decimal
                if (valorTexto.contains(',')) {
                  valorTexto = valorTexto.replaceAll('.', ''); // Remove pontos
                  valorTexto = valorTexto.replaceAll(',', '.'); // Converte vírgula para ponto
                }
                
                // Se não tem ponto, adiciona .00
                if (!valorTexto.contains('.')) {
                  valorTexto = '$valorTexto.00';
                }
                
                final valorPago = double.tryParse(valorTexto);
                
                if (valorPago == null || valorPago <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, informe um valor válido maior que zero'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (valorPago > valorPendente + 0.01) { // +0.01 para tolerância de arredondamento
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('O valor não pode ser maior que o pendente (${formatoMoeda.format(valorPendente)})'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Calcular novo valor pago
                final novoValorPago = (conta.valorPago ?? 0.0) + valorPago;
                final novoStatus = (novoValorPago >= conta.valor - 0.01) // Tolerância para arredondamento
                  ? StatusContaPagar.pago 
                  : conta.status;
                
                // Criar registro de pagamento
                final novoRegistro = RegistroPagamento(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  valor: valorPago,
                  dataPagamento: dataPagamento,
                  formaPagamento: formaPagamento?.nome,
                  observacao: observacaoController.text.isEmpty ? null : observacaoController.text,
                );
                
                // Adicionar ao histórico
                final novoHistorico = List<RegistroPagamento>.from(conta.historicoPagamentos)
                  ..add(novoRegistro);
                
                // Criar conta atualizada
                final contaAtualizada = ContaPagar(
                  id: conta.id,
                  numero: conta.numero,
                  tipo: conta.tipo,
                  categoria: conta.categoria,
                  descricao: conta.descricao,
                  observacoes: observacaoController.text.isEmpty 
                    ? conta.observacoes 
                    : '${conta.observacoes ?? ''}\n${observacaoController.text}'.trim(),
                  valor: conta.valor,
                  valorPago: novoValorPago,
                  dataVencimento: conta.dataVencimento,
                  dataPagamento: novoStatus == StatusContaPagar.pago ? dataPagamento : conta.dataPagamento,
                  dataCriacao: conta.dataCriacao,
                  updatedAt: DateTime.now(),
                  notaEntradaId: conta.notaEntradaId,
                  notaEntradaNumero: conta.notaEntradaNumero,
                  fornecedorId: conta.fornecedorId,
                  fornecedorNome: conta.fornecedorNome,
                  status: novoStatus,
                  formaPagamento: formaPagamento?.nome ?? conta.formaPagamento,
                  historicoPagamentos: novoHistorico,
                  recorrente: conta.recorrente,
                  intervaloRecorrencia: conta.intervaloRecorrencia,
                  proximaDataRecorrencia: conta.proximaDataRecorrencia,
                  ativo: conta.ativo,
                  usuarioCriacao: conta.usuarioCriacao,
                  usuarioPagamento: conta.usuarioPagamento,
                );
                
                // Salvar
                dataService.updateContaPagar(contaAtualizada);
                
                Navigator.pop(context);
                setState(() {});
                
                final valorRestante = conta.valor - novoValorPago;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      novoStatus == StatusContaPagar.pago
                        ? 'Conta paga com sucesso!'
                        : 'Pagamento parcial de ${formatoMoeda.format(valorPago)} registrado! Restante: ${formatoMoeda.format(valorRestante)}',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
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

  void _estornarPagamento(BuildContext context, ContaPagar conta, RegistroPagamento pagamento) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.undo, color: Colors.orange),
            SizedBox(width: 8),
            Text('Estornar Pagamento'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deseja estornar este pagamento?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conta: ${conta.descricao}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Data: ${formatoData.format(pagamento.dataPagamento)}'),
                      Text(
                        'Valor: ${formatoMoeda.format(pagamento.valor)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  if (pagamento.formaPagamento != null) ...[
                    const SizedBox(height: 4),
                    Text('Forma: ${pagamento.formaPagamento}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ao estornar, o pagamento será removido do histórico e o valor será adicionado novamente ao pendente da conta.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Remover o pagamento do histórico
              final novoHistorico = conta.historicoPagamentos
                  .where((p) => p.id != pagamento.id)
                  .toList();
              
              // Recalcular valor pago
              final novoValorPago = novoHistorico.fold<double>(
                0.0,
                (sum, p) => sum + p.valor,
              );
              
              // Atualizar status
              final novoStatus = novoValorPago >= conta.valor - 0.01
                  ? StatusContaPagar.pago
                  : (conta.isVencida ? StatusContaPagar.vencido : StatusContaPagar.pendente);
              
              // Atualizar data de pagamento (se não houver mais pagamentos, remove)
              final dataPagamentoAtualizada = novoHistorico.isNotEmpty
                  ? novoHistorico.map((p) => p.dataPagamento).reduce((a, b) => a.isAfter(b) ? a : b)
                  : null;
              
              // Criar conta atualizada
              final contaAtualizada = ContaPagar(
                id: conta.id,
                numero: conta.numero,
                tipo: conta.tipo,
                categoria: conta.categoria,
                descricao: conta.descricao,
                observacoes: conta.observacoes,
                valor: conta.valor,
                valorPago: novoValorPago > 0 ? novoValorPago : null,
                dataVencimento: conta.dataVencimento,
                dataPagamento: dataPagamentoAtualizada,
                dataCriacao: conta.dataCriacao,
                updatedAt: DateTime.now(),
                notaEntradaId: conta.notaEntradaId,
                notaEntradaNumero: conta.notaEntradaNumero,
                fornecedorId: conta.fornecedorId,
                fornecedorNome: conta.fornecedorNome,
                status: novoStatus,
                formaPagamento: conta.formaPagamento,
                historicoPagamentos: novoHistorico,
                recorrente: conta.recorrente,
                intervaloRecorrencia: conta.intervaloRecorrencia,
                proximaDataRecorrencia: conta.proximaDataRecorrencia,
                ativo: conta.ativo,
                usuarioCriacao: conta.usuarioCriacao,
                usuarioPagamento: conta.usuarioPagamento,
              );
              
              // Salvar
              dataService.updateContaPagar(contaAtualizada);
              
              Navigator.pop(context);
              setState(() {});
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✓ Pagamento estornado com sucesso!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Valor estornado: ${formatoMoeda.format(pagamento.valor)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      Text(
                        'Novo valor pendente: ${formatoMoeda.format(conta.valor - novoValorPago)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar Estorno'),
          ),
        ],
      ),
    );
  }
}

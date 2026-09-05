import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/cliente.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import 'dart:typed_data';
import 'package:printing/printing.dart';

import '../services/whatsapp_service.dart';
import '../services/pedido_pdf_service.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'conta_receber_form_page.dart';
import 'conta_receber_extrato_page.dart';
import '../widgets/sync_status_widget.dart';
import '../models/empresa.dart';

class ContasReceberPage extends StatefulWidget {
  const ContasReceberPage({super.key});

  @override
  State<ContasReceberPage> createState() => _ContasReceberPageState();
}

class _ContasReceberPageState extends State<ContasReceberPage> with SingleTickerProviderStateMixin {
  String _filtroStatus = 'Todos';
  String _filtroTipo = 'Todos';
  String? _clienteFiltro;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  bool _mostrarBusca = false;
  Set<String> _selecionadas = {};
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  bool _gerarRecebivelAuto = true;
  late TabController _abaController;
  Set<String> _itensExpandidos = {}; // IDs das contas com itens expandidos

  final List<String> _statusDisponiveis = [
    'Todos',
    'Pendente',
    'Vencido',
    'Pago',
    'Cancelado',
  ];

  final List<String> _tiposDisponiveis = [
    'Todos',
    'Fiado',
    'Crediário',
    'Avulsas',
  ];


  @override
  void initState() {
    super.initState();
    _abaController = TabController(length: 3, vsync: this);
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _gerarRecebivelAuto = prefs.getBool('gerar_recebivel_nfe') ?? true;
      });
    }
  }

  Future<void> _toggleConfig(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gerar_recebivel_nfe', value);
    setState(() {
      _gerarRecebivelAuto = value;
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _abaController.dispose();
    super.dispose();
  }


  DateTime? _extractDueDate(String? obs) {
    if (obs == null) return null;
    final match = RegExp(r'\[VENC:\s*(\d{4}-\d{2}-\d{2})\]').firstMatch(obs);
    if (match != null) {
      return DateTime.tryParse(match.group(1)!);
    }
    return null;
  }

  List<ContaPagar> _filtrarContas(List<ContaPagar> contas, DataService dataService) {
    var resultado = contas.where((c) => c.ativo && c.categoria == 'Recebível').toList();

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
    }

    // Filtro por tipo
    if (_filtroTipo != 'Todos') {
      resultado = resultado.where((c) {
        switch (_filtroTipo) {
          case 'Fiado':
            // Vendas fiado ou pedidos com pagamento fiado
            if (c.id.startsWith('venda_')) {
              final idReal = c.id.replaceFirst('venda_', '');
              try {
                final venda = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
                return venda.tipoPagamento == TipoPagamento.fiado;
              } catch (_) {}
            } else if (c.id.startsWith('pedido_')) {
              final idReal = c.id.replaceFirst('pedido_', '');
              try {
                final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
                return pedido.pagamentos.any((pag) => pag.tipo == TipoPagamento.fiado);
              } catch (_) {}
            }
            return false;
          case 'Crediário':
            // Vendas crediário ou pedidos com pagamento crediário
            if (c.id.startsWith('venda_')) {
              final idReal = c.id.replaceFirst('venda_', '');
              try {
                final venda = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
                return venda.tipoPagamento == TipoPagamento.crediario;
              } catch (_) {}
            } else if (c.id.startsWith('pedido_')) {
              final idReal = c.id.replaceFirst('pedido_', '');
              try {
                final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
                return pedido.pagamentos.any((pag) => pag.tipo == TipoPagamento.crediario);
              } catch (_) {}
            }
            return false;
          case 'Avulsas':
            return !c.id.startsWith('venda_') && !c.id.startsWith('pedido_');
          default:
            return true;
        }
      }).toList();
    }


    // Filtro por cliente
    if (_clienteFiltro != null && _clienteFiltro!.isNotEmpty) {
      resultado = resultado.where((c) {
        final nome = c.fornecedorNome ?? 'Cliente não informado';
        return nome.toLowerCase().contains(_clienteFiltro!.toLowerCase());
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
    
    // Obter contas a receber do banco
    final contasBase = dataService.contasPagar.where((c) => c.categoria == 'Recebível').toList();
    
    // Obter vendas (fiado/crediário — inclui pagas para manter histórico)
    final vendasPrazo = dataService.vendasBalcao.where((v) {
      if (v.cancelado) return false;
      return v.tipoPagamento == TipoPagamento.fiado || v.tipoPagamento == TipoPagamento.crediario;
    }).map((v) {
      final valPago = v.valorRecebido ?? 0.0;
      final status = valPago >= v.valorTotal - 0.01 ? StatusContaPagar.pago : StatusContaPagar.pendente;
      return ContaPagar(
        id: 'venda_${v.id}',
        numero: v.numero,
        tipo: TipoContaPagar.despesaVariavel,
        categoria: 'Recebível',
        descricao: 'Venda PDV - ${v.numero}',
        observacoes: v.observacoes,
        valor: v.valorTotal,
        valorPago: valPago,
        dataVencimento: _extractDueDate(v.observacoes) ?? v.dataVenda.add(const Duration(days: 30)),
        dataPagamento: valPago >= v.valorTotal - 0.01 ? v.updatedAt : null,
        dataCriacao: v.createdAt,
        updatedAt: v.updatedAt,
        createdAt: v.createdAt,
        status: status,
        fornecedorNome: v.clienteNome?.isNotEmpty == true ? v.clienteNome : 'Cliente não informado',
        ativo: true,
      );
    }).toList();
    
    // Obter pedidos (fiado/crediário — inclui pagos para manter histórico)
    final pedidosPrazo = dataService.pedidos.where((p) {
      if (p.status == 'Cancelado') return false;
      final temFiadoOuCrediario = p.pagamentos.any(
        (pag) => pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario
      );
      return temFiadoOuCrediario;
    }).map((p) {
      final valPago = p.totalRecebido;
      final status = p.totalmenteRecebido ? StatusContaPagar.pago : StatusContaPagar.pendente;
      return ContaPagar(
        id: 'pedido_${p.id}',
        numero: p.numero,
        tipo: TipoContaPagar.despesaVariavel,
        categoria: 'Recebível',
        descricao: 'Pedido - ${p.numero}',
        observacoes: p.observacoes,
        valor: p.totalGeral,
        valorPago: valPago,
        dataVencimento: p.proximaParcela?.dataVencimento ?? p.dataPedido.add(const Duration(days: 30)),
        dataPagamento: p.totalmenteRecebido ? p.updatedAt : null,
        dataCriacao: p.dataPedido,
        updatedAt: p.updatedAt,
        createdAt: p.createdAt,
        status: status,
        fornecedorNome: p.clienteNome?.isNotEmpty == true ? p.clienteNome : 'Cliente não informado',
        ativo: true,
      );
    }).toList();
    
    // Combina as tres listas
    // DEDUPLICAÇÃO: venda fiado/crediário cria VendaBalcao E Pedido com o MESMO
    // id. Sem deduplicar, a mesma venda aparecia 2x na tela (uma como "Venda",
    // outra como "Pedido") e com status diferentes (bug do pagamentoCompleto).
    final idsVendas = vendasPrazo.map((v) => v.id.replaceFirst('venda_', '')).toSet();
    final pedidosSemDuplicar = pedidosPrazo
        .where((p) => !idsVendas.contains(p.id.replaceFirst('pedido_', '')))
        .toList();
    final todasContas = [...contasBase, ...vendasPrazo, ...pedidosSemDuplicar];

    final contas = _filtrarContas(todasContas, dataService);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Calcular totais
    final totalPendente = contas
        .where((c) => c.statusAtualizado == StatusContaPagar.pendente)
        .fold<double>(0.0, (sum, c) => sum + c.valorPendente);
    
    final totalVencido = contas
        .where((c) => c.statusAtualizado == StatusContaPagar.vencido)
        .fold<double>(0.0, (sum, c) => sum + c.valorPendente);

    final totalRecebido = contas
        .where((c) => c.statusAtualizado == StatusContaPagar.pago)
        .fold<double>(0.0, (sum, c) => sum + (c.valorPago ?? 0.0));

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Contas a Receber'),
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
            const SyncStatusWidget(),
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
              icon: const Icon(Icons.settings),
              tooltip: 'Configurações',
              onSelected: (val) {
                if (val == 'toggle_auto') {
                  _toggleConfig(!_gerarRecebivelAuto);
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 'toggle_auto',
                  checked: _gerarRecebivelAuto,
                  child: const Text('Gerar Conta a Receber ao emitir NF-e'),
                ),
              ],
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
              ],
            ),
          ],
          bottom: TabBar(
            controller: _abaController,
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.list, size: 18), text: 'Geral'),
              Tab(icon: Icon(Icons.warning_amber, size: 18), text: 'Atrasados'),
              Tab(icon: Icon(Icons.assessment, size: 18), text: 'Relatório'),
            ],
          ),
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

            
            if (_dataInicioFiltro != null && _dataFimFiltro != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Chip(
                      backgroundColor: Colors.orange.withOpacity(0.2),
                      side: const BorderSide(color: Colors.orange),
                      label: Text(
                        'Período: ${DateFormat('dd/MM/yy').format(_dataInicioFiltro!)} a ${DateFormat('dd/MM/yy').format(_dataFimFiltro!)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
                      onDeleted: () {
                        setState(() {
                          _dataInicioFiltro = null;
                          _dataFimFiltro = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _abaController,
                children: [
                  // === ABA GERAL ===
                  Column(
                    children: [
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
                          'Recebido',
                          formatoMoeda.format(totalRecebido),
                          Colors.green,
                          Icons.check_circle,
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
                  // === ABA ATRASADOS ===
                  _buildAbaAtrasados(contas, formatoMoeda, formatoData),
                  // === ABA RELATORIO ===
                  _buildAbaRelatorio(contas, formatoMoeda, formatoData, totalPendente, totalVencido, totalRecebido),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _selecionadas.isNotEmpty
            ? Container(
                color: const Color(0xFF2C2C3E),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _selecionadas.length == contas.where((c) => c.statusAtualizado != StatusContaPagar.pago && c.statusAtualizado != StatusContaPagar.cancelado).length,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selecionadas = contas
                                    .where((c) => c.statusAtualizado != StatusContaPagar.pago && c.statusAtualizado != StatusContaPagar.cancelado)
                                    .map((c) => c.id)
                                    .toSet();
                              } else {
                                _selecionadas.clear();
                              }
                            });
                          },
                        ),
                        Text(
                          '${_selecionadas.length} selecionadas',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            onPressed: () => _mostrarOpcoesExtrato(contas),
                            icon: const Icon(Icons.send, color: Colors.green), // using whatshot if whatsapp icon not available in standard icons
                            tooltip: 'Enviar Extrato via WhatsApp',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (contas.where((c) => _selecionadas.contains(c.id)).any((c) => c.statusAtualizado != StatusContaPagar.pago && c.statusAtualizado != StatusContaPagar.cancelado))
                        ElevatedButton.icon(
                          onPressed: () => _confirmarBaixaLote(contas),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Receber'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : null,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ContaReceberFormPage(categoriaPredefinida: 'Recebível'),
              ),
            ).then((_) => setState(() {}));
          },
          icon: const Icon(Icons.add),
          label: const Text('Novo Recebimento'),
          backgroundColor: Colors.orange,
        ),
      ),
    );
  }


    void _mostrarOpcoesExtrato(List<ContaPagar> contasNaTela) {
    final contasLote = contasNaTela.where((c) => _selecionadas.contains(c.id)).toList();
    if (contasLote.isEmpty) return;

    // Coletar pedidos/vendas originais para usar o PedidoPDFService
    final dataService = Provider.of<DataService>(context, listen: false);
    final pedidosOriginais = <Pedido>[];
    for (final c in contasLote) {
      if (c.id.startsWith('pedido_')) {
        final idReal = c.id.replaceFirst('pedido_', '');
        try {
          final p = dataService.pedidos.firstWhere((p) => p.id == idReal);
          if (!pedidosOriginais.any((x) => x.id == p.id)) pedidosOriginais.add(p);
        } catch (_) {}
      }
    }

    final temPedidos = pedidosOriginais.isNotEmpty;
    final empresa = dataService.empresaAtual;

    // Nome do cliente
    String clienteNome = '';
    for (final c in contasLote) {
      if (c.fornecedorNome != null && c.fornecedorNome!.isNotEmpty && c.fornecedorNome != 'Cliente não informado') {
        clienteNome = c.fornecedorNome!;
        break;
      }
    }

    // Código do cliente
    String? clienteCodigo;
    if (contasLote.isNotEmpty) {
      for (final c in contasLote) {
        if (c.id.startsWith('venda_')) {
          final idReal = c.id.replaceFirst('venda_', '');
          try {
            final v = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
            if (v.clienteId != null) {
              final cli = dataService.clientes.firstWhere(
                (c) => c.id == v.clienteId,
                orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
              );
              if (cli.id.isNotEmpty) { clienteCodigo = cli.dadosExtras?['codigo']?.toString(); break; }
            }
          } catch (_) {}
        } else if (c.id.startsWith('pedido_')) {
          final idReal = c.id.replaceFirst('pedido_', '');
          try {
            final p = dataService.pedidos.firstWhere((p) => p.id == idReal);
            if (p.clienteId != null) {
              final cli = dataService.clientes.firstWhere(
                (c) => c.id == p.clienteId,
                orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
              );
              if (cli.id.isNotEmpty) { clienteCodigo = cli.dadosExtras?['codigo']?.toString(); break; }
            }
          } catch (_) {}
        }
      }
    }

    bool incluirItens = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Opções de Extrato'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (temPedidos && empresa != null) ...[
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                    title: const Text('Extrato A4 (PedidoPDF)', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('PDF profissional formato A4', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await PedidoPDFService.imprimirExtratoFiado(
                        context: context,
                        pedidos: pedidosOriginais,
                        clienteNome: clienteNome,
                        clienteCodigo: clienteCodigo,
                        empresa: empresa,
                        mostrarItens: incluirItens,
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long, color: Colors.blueAccent),
                    title: const Text('Extrato Térmica (80mm)', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Impressora térmica', style: TextStyle(fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await PedidoPDFService.imprimirExtratoFiadoTermico(
                        context: context,
                        pedidos: pedidosOriginais,
                        clienteNome: clienteNome,
                        clienteCodigo: clienteCodigo,
                        empresa: empresa,
                        mostrarItens: incluirItens,
                      );
                    },
                  ),
                  const Divider(color: Colors.white12),
                ],
                CheckboxListTile(
                  title: const Text('Incluir itens das vendas'),
                  value: incluirItens,
                  onChanged: (val) {
                    setStateDialog(() => incluirItens = val ?? false);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Enviar PDF'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _compartilharPDF(contasLote, incluirItens);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('WhatsApp (PDF)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _enviarWhatsAppExtratoPDF(contasLote, incluirItens);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.send, size: 18),
                label: const Text('WhatsApp (Texto)'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final texto = await _gerarTextoExtrato(contasLote, incluirItens);
                  _abrirWhatsApp(texto);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String> _gerarTextoExtrato(List<ContaPagar> contasLote, bool incluirItens) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    contasLote.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    
    final nomesClientes = contasLote.map((c) => c.fornecedorNome ?? 'Não informado').where((n) => n != 'Não informado').toList();
    String nomeCliente = nomesClientes.isEmpty ? 'Cliente não informado' : nomesClientes.first;
    
    double totalPendente = contasLote.fold(0.0, (sum, c) => sum + c.valorPendente);
    double totalPago = contasLote.fold(0.0, (sum, c) {
      if (c.statusAtualizado == StatusContaPagar.pago) {
        return sum + (c.valorPago ?? c.valor);
      }
      return sum + (c.valorPago ?? 0.0);
    });
    
    final DateFormat formatoData = DateFormat('dd/MM/yyyy');
    final NumberFormat formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    StringBuffer texto = StringBuffer();
    texto.writeln('*EXTRATO DE CONTAS*');
    texto.writeln('Cliente: $nomeCliente');
    texto.writeln('--------------------');
    
    for (final c in contasLote) {
      DateTime dataCompra = c.dataCriacao;
      VendaBalcao? vendaOriginal;
      Pedido? pedidoOriginal;
      if (c.id.startsWith('venda_')) {
        final idReal = c.id.replaceFirst('venda_', '');
        try {
          vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
          dataCompra = vendaOriginal.dataVenda;
        } catch(e) {}
      } else if (c.id.startsWith('pedido_')) {
        final idReal = c.id.replaceFirst('pedido_', '');
        try {
          pedidoOriginal = dataService.pedidos.firstWhere((p) => p.id == idReal);
          dataCompra = pedidoOriginal.dataPedido;
        } catch(e) {}
      }

      String valorTexto = c.statusAtualizado == StatusContaPagar.pago 
          ? 'Valor Pago: ${formatoMoeda.format(c.valorPago ?? c.valor)}' 
          : 'Valor Pendente: ${formatoMoeda.format(c.valorPendente)}';
          
      String statusStr = c.statusAtualizado == StatusContaPagar.pago ? 'PAGO' : (c.isVencida ? 'VENCIDO' : 'PENDENTE');

      texto.writeln('Compra: ${formatoData.format(dataCompra)}');
      texto.writeln('Venc: ${formatoData.format(c.dataVencimento)}');
      texto.writeln('Desc: ${c.descricao} [$statusStr]');
      texto.writeln(valorTexto);
      
      if (incluirItens) {
        if (vendaOriginal != null && vendaOriginal.itens.isNotEmpty) {
          texto.writeln('Itens:');
          for (var item in vendaOriginal.itens) {
            texto.writeln('- ${item.quantidade}x ${item.nome} (${formatoMoeda.format(item.quantidade * item.precoUnitario)})');
          }
        } else if (pedidoOriginal != null && (pedidoOriginal.produtos.isNotEmpty || pedidoOriginal.servicos.isNotEmpty)) {
          texto.writeln('Itens:');
          for (var item in pedidoOriginal.produtos) {
            texto.writeln('- ${item.quantidade}x ${item.nome} (${formatoMoeda.format(item.quantidade * item.preco)})');
          }
          for (var serv in pedidoOriginal.servicos) {
            texto.writeln('- 1x ${serv.descricao} (${formatoMoeda.format(serv.valor + serv.valorAdicional)})');
          }
        }
      }
      texto.writeln('--------------------');
    }
    
    if (totalPendente > 0) texto.writeln('*TOTAL PENDENTE:* ${formatoMoeda.format(totalPendente)}');
    if (totalPago > 0) texto.writeln('*TOTAL PAGO:* ${formatoMoeda.format(totalPago)}');
    if (totalPendente == 0 && totalPago == 0) texto.writeln('*TOTAL:* ${formatoMoeda.format(0)}');
    
    return texto.toString();
  }

  void _abrirWhatsApp(String texto) async {
    final String msgCodificada = Uri.encodeComponent(texto);
    final Uri url = Uri.parse('https://wa.me/?text=$msgCodificada');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o WhatsApp.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<pw.Document> _criarDocumentoPDF(List<ContaPagar> contasLote, bool incluirItens, String nomeCliente) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    
    double totalPendente = contasLote.fold(0.0, (sum, c) => sum + c.valorPendente);
    double totalPago = contasLote.fold(0.0, (sum, c) {
      if (c.statusAtualizado == StatusContaPagar.pago) {
        return sum + (c.valorPago ?? c.valor);
      }
      return sum + (c.valorPago ?? 0.0);
    });
    
    final DateFormat formatoData = DateFormat('dd/MM/yyyy');
    final NumberFormat formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('EXTRATO DE CONTAS', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Data: ${formatoData.format(DateTime.now())}'),
                ]
              )
            ),
            pw.SizedBox(height: 10),
            pw.Text('Cliente: $nomeCliente', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            ...contasLote.map((c) {
              DateTime dataCompra = c.dataCriacao;
              VendaBalcao? vendaOriginal;
              Pedido? pedidoOriginal;
              if (c.id.startsWith('venda_')) {
                final idReal = c.id.replaceFirst('venda_', '');
                try {
                  vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
                  dataCompra = vendaOriginal.dataVenda;
                } catch(e) {}
              } else if (c.id.startsWith('pedido_')) {
                final idReal = c.id.replaceFirst('pedido_', '');
                try {
                  pedidoOriginal = dataService.pedidos.firstWhere((p) => p.id == idReal);
                  dataCompra = pedidoOriginal.dataPedido;
                } catch(e) {}
              }

              String valorTexto = c.statusAtualizado == StatusContaPagar.pago 
                  ? 'Valor Pago: ${formatoMoeda.format(c.valorPago ?? c.valor)}' 
                  : 'Valor Pendente: ${formatoMoeda.format(c.valorPendente)}';
                  
              String statusStr = c.statusAtualizado == StatusContaPagar.pago ? 'PAGO' : (c.isVencida ? 'VENCIDO' : 'PENDENTE');
              PdfColor statusColor = c.statusAtualizado == StatusContaPagar.pago ? PdfColors.green700 : (c.isVencida ? PdfColors.red700 : PdfColors.orange700);

              List<pw.Widget> itemWidgets = [];
              if (incluirItens) {
                if (vendaOriginal != null && vendaOriginal.itens.isNotEmpty) {
                  itemWidgets.add(pw.SizedBox(height: 4));
                  itemWidgets.add(pw.Text('Itens da Venda:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)));
                  for (var item in vendaOriginal.itens) {
                    itemWidgets.add(pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8, top: 2),
                      child: pw.Text('- ${item.quantidade}x ${item.nome} (${formatoMoeda.format(item.quantidade * item.precoUnitario)})', style: const pw.TextStyle(fontSize: 10)),
                    ));
                  }
                } else if (pedidoOriginal != null && (pedidoOriginal.produtos.isNotEmpty || pedidoOriginal.servicos.isNotEmpty)) {
                  itemWidgets.add(pw.SizedBox(height: 4));
                  itemWidgets.add(pw.Text('Itens do Pedido:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)));
                  for (var item in pedidoOriginal.produtos) {
                    itemWidgets.add(pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8, top: 2),
                      child: pw.Text('- ${item.quantidade}x ${item.nome} (${formatoMoeda.format(item.quantidade * item.preco)})', style: const pw.TextStyle(fontSize: 10)),
                    ));
                  }
                  for (var serv in pedidoOriginal.servicos) {
                    itemWidgets.add(pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8, top: 2),
                      child: pw.Text('- 1x ${serv.descricao} (${formatoMoeda.format(serv.valor + serv.valorAdicional)})', style: const pw.TextStyle(fontSize: 10)),
                    ));
                  }
                }
              }

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Compra: ${formatoData.format(dataCompra)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.Text('Vencimento: ${formatoData.format(c.dataVencimento)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.RichText(
                          text: pw.TextSpan(
                            text: 'Descrição: ${c.descricao} ',
                            children: [
                              pw.TextSpan(
                                text: '[$statusStr]',
                                style: pw.TextStyle(color: statusColor, fontWeight: pw.FontWeight.bold, fontSize: 10),
                              )
                            ]
                          )
                        ),
                        pw.Text(valorTexto, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                    ...itemWidgets,
                  ],
                )
              );
            }).toList(),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (totalPendente > 0)
                      pw.Row(children: [
                        pw.Text('TOTAL PENDENTE: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(formatoMoeda.format(totalPendente), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      ]),
                    if (totalPago > 0)
                      pw.Row(children: [
                        pw.Text('TOTAL PAGO: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(formatoMoeda.format(totalPago), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                      ]),
                    if (totalPendente == 0 && totalPago == 0)
                      pw.Row(children: [
                        pw.Text('TOTAL: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(formatoMoeda.format(0), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      ]),
                  ]
                )
              ]
            ),
          ];
        }
      )
    );
    return doc;
  }

  Future<void> _gerarEVisualizarPDF(List<ContaPagar> contasLote, bool incluirItens) async {
    contasLote.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    final nomesClientes = contasLote.map((c) => c.fornecedorNome ?? 'Não informado').where((n) => n != 'Não informado').toList();
    String nomeCliente = nomesClientes.isEmpty ? 'Cliente não informado' : nomesClientes.first;
    
    final doc = await _criarDocumentoPDF(contasLote, incluirItens, nomeCliente);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Extrato_${nomeCliente.replaceAll(' ', '_')}.pdf',
    );
  }

  Future<void> _compartilharPDF(List<ContaPagar> contasLote, bool incluirItens) async {
    contasLote.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    final nomesClientes = contasLote.map((c) => c.fornecedorNome ?? 'Não informado').where((n) => n != 'Não informado').toList();
    String nomeCliente = nomesClientes.isEmpty ? 'Cliente não informado' : nomesClientes.first;
    
    final doc = await _criarDocumentoPDF(contasLote, incluirItens, nomeCliente);
    
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Extrato_${nomeCliente.replaceAll(' ', '_')}.pdf',
    );
  }

  Future<void> _enviarWhatsAppExtratoPDF(List<ContaPagar> contasLote, bool incluirItens) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma empresa configurada.'), backgroundColor: Colors.red));
      return;
    }
    
    final hasApi = empresa.whatsappApiUrl != null && empresa.whatsappApiKey != null;
    bool isConnected = false;
    
    if (hasApi) {
      final service = WhatsAppService.fromEmpresa(empresa);
      isConnected = await service.isConectado();
    }
    
    if (!hasApi || !isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API do WhatsApp não configurada ou desconectada. Use a opção de Enviar PDF via app.'), backgroundColor: Colors.orange)
      );
      _compartilharPDF(contasLote, incluirItens);
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Enviar Extrato (PDF)', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'WhatsApp do Cliente (DDD + Número)', labelStyle: TextStyle(color: Colors.white70)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    
    if (!mounted) return;
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF25D366))),
    );

    try {
      final nomesClientes = contasLote.map((c) => c.fornecedorNome ?? 'Não informado').where((n) => n != 'Não informado').toList();
      String nomeCliente = nomesClientes.isEmpty ? 'Cliente não informado' : nomesClientes.first;
      final doc = await _criarDocumentoPDF(contasLote, incluirItens, nomeCliente);
      final pdfBytes = await doc.save();
      final base64Pdf = base64Encode(pdfBytes);
      
      final service = WhatsAppService.fromEmpresa(empresa);
      final sucesso = await service.enviarArquivo(
        numero: result,
        base64Content: base64Pdf,
        fileName: 'Extrato_${nomeCliente.replaceAll(' ', '_')}.pdf',
        caption: 'Segue o extrato de contas em anexo.',
      );
      
      if (mounted) Navigator.pop(context); // fecha loading
      
      if (sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Extrato enviado com sucesso!'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha ao enviar extrato via WhatsApp.'), backgroundColor: Colors.red));
      }
    } catch(e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }

  void _confirmarBaixaLote(List<ContaPagar> contasNaTela) {
    final contasLote = contasNaTela.where((c) => _selecionadas.contains(c.id) && c.statusAtualizado != StatusContaPagar.pago && c.statusAtualizado != StatusContaPagar.cancelado).toList();
    if (contasLote.isEmpty) return;
    
    // Ordenar da mais antiga para a mais nova
    contasLote.sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    final totalPendente = contasLote.fold(0.0, (sum, item) => sum + item.valorPendente);
    TipoPagamento forma1 = TipoPagamento.dinheiro;
    TipoPagamento forma2 = TipoPagamento.pix;
    double valor1 = totalPendente;
    double valor2 = 0.0;
    bool usarDuasFormas = false;

    final ctrlValor1 = TextEditingController(text: valor1.toStringAsFixed(2));
    final ctrlValor2 = TextEditingController(text: valor2.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          
          double v1 = double.tryParse(ctrlValor1.text.replaceAll(',', '.')) ?? 0;
          double v2 = usarDuasFormas ? (double.tryParse(ctrlValor2.text.replaceAll(',', '.')) ?? 0) : 0;
          double totalDigitado = v1 + v2;
          bool excedeu = totalDigitado > (totalPendente + 0.01); // Margem de erro

          return AlertDialog(
            title: const Text('Receber em Lote / Parcial'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Você selecionou ${contasLote.length} contas.'),
                  const SizedBox(height: 8),
                  Text('Total Pendente: R\$ ${totalPendente.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  // Forma 1
                  const Text('Forma de Pagamento 1:'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<TipoPagamento>(
                          value: forma1,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          dropdownColor: const Color(0xFF1E1E2E),
                          items: TipoPagamento.values.map((t) => DropdownMenuItem(value: t, child: Text(t.nome))).toList(),
                          onChanged: (val) { if (val != null) setStateDialog(() => forma1 = val); },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: ctrlValor1,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            prefixText: 'R\$ ',
                          ),
                          onChanged: (_) => setStateDialog(() {}),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  if (!usarDuasFormas)
                    TextButton.icon(
                      onPressed: () {
                        setStateDialog(() {
                          usarDuasFormas = true;
                          ctrlValor2.text = '0.00';
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar outra forma de pagamento', style: TextStyle(fontSize: 12)),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Forma de Pagamento 2:'),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setStateDialog(() {
                              usarDuasFormas = false;
                              ctrlValor2.text = '0.00';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<TipoPagamento>(
                            value: forma2,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            dropdownColor: const Color(0xFF1E1E2E),
                            items: TipoPagamento.values.map((t) => DropdownMenuItem(value: t, child: Text(t.nome))).toList(),
                            onChanged: (val) { if (val != null) setStateDialog(() => forma2 = val); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: ctrlValor2,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              prefixText: 'R\$ ',
                            ),
                            onChanged: (_) => setStateDialog(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: excedeu ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: excedeu ? Colors.red : Colors.green),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total a Receber:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('R\$ ${totalDigitado.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: excedeu ? Colors.red : Colors.green)),
                      ],
                    ),
                  ),
                  if (excedeu)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('O total a receber não pode ser maior que o pendente!', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: (totalDigitado <= 0 || excedeu) ? null : () async {
                  Navigator.pop(ctx);
                  await _processarBaixaLote(contasLote, v1, forma1, v2, forma2, usarDuasFormas);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      )
    );
  }

  Future<void> _processarBaixaLote(List<ContaPagar> contasLote, double valor1, TipoPagamento forma1, double valor2, TipoPagamento forma2, bool usarDuas) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final hoje = DateTime.now();

    double saldo1 = valor1;
    double saldo2 = usarDuas ? valor2 : 0.0;
    double totalRecebido = 0.0;
    String nomeCliente = '';

    for (final conta in contasLote) {
      if (saldo1 <= 0.001 && saldo2 <= 0.001) break;

      double pendente = conta.valorPendente;
      if (pendente <= 0.001) continue;
      
      double aplicado1 = 0;
      if (saldo1 > 0.001) {
        aplicado1 = saldo1 > pendente ? pendente : saldo1;
        saldo1 -= aplicado1;
        pendente -= aplicado1;
      }
      
      double aplicado2 = 0;
      if (pendente > 0.001 && saldo2 > 0.001) {
        aplicado2 = saldo2 > pendente ? pendente : saldo2;
        saldo2 -= aplicado2;
        pendente -= aplicado2;
      }
      
      final valorAplicado = aplicado1 + aplicado2;
      if (valorAplicado <= 0.001) continue;

      totalRecebido += valorAplicado;
      if (nomeCliente.isEmpty && conta.fornecedorNome != null) {
        nomeCliente = conta.fornecedorNome!;
      }

      if (conta.id.startsWith('venda_')) {
        final idReal = conta.id.replaceFirst('venda_', '');
        try {
            final vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
            final novoRecebido = (vendaOriginal.valorRecebido ?? 0.0) + valorAplicado;
            
            final vendaAtualizada = vendaOriginal.copyWith(
              // NÃO altera tipoPagamento — mantém fiado/crediário para a conta continuar aparecendo
              valorRecebido: novoRecebido,
              updatedAt: hoje,
            );
            await dataService.updateVendaBalcao(vendaAtualizada);

            // Atualizar saldo devedor do cliente (fiado E crediário)
            if ((vendaOriginal.tipoPagamento == TipoPagamento.fiado || vendaOriginal.tipoPagamento == TipoPagamento.crediario) && vendaOriginal.clienteId != null) {
              final cliente = dataService.clientes.firstWhere(
                (c) => c.id == vendaOriginal.clienteId,
                orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje),
              );
              if (cliente.id.isNotEmpty) {
                final novoSaldo = (cliente.saldoDevedor - valorAplicado).clamp(0.0, double.infinity);
                await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
              }
            }
            // Sincronizar Pedido vinculado à VendaBalcao
            try {
              final pedidoVinculado = dataService.pedidos.firstWhere((p) => p.id == vendaOriginal.id);
              final novosPagamentosPedido = <PagamentoPedido>[];
              double valorRestanteSync = valorAplicado;
              for (final pag in pedidoVinculado.pagamentos) {
                if (!pag.recebido && valorRestanteSync > 0.001 && (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario || pag.tipoOriginal == TipoPagamento.fiado || pag.tipoOriginal == TipoPagamento.crediario)) {
                  if (valorRestanteSync >= pag.valor) {
                    novosPagamentosPedido.add(PagamentoPedido(id: pag.id, tipo: forma1, tipoOriginal: pag.tipo, valor: pag.valor, recebido: true, dataRecebimento: hoje, dataVencimento: pag.dataVencimento, observacao: 'Recebido via Contas a Receber'));
                    valorRestanteSync -= pag.valor;
                  } else {
                    novosPagamentosPedido.add(PagamentoPedido(id: '${pag.id}_pago', tipo: forma1, tipoOriginal: pag.tipo, valor: valorRestanteSync, recebido: true, dataRecebimento: hoje, observacao: 'Recebimento parcial via Contas a Receber'));
                    novosPagamentosPedido.add(PagamentoPedido(id: '${pag.id}_resto', tipo: pag.tipo, valor: pag.valor - valorRestanteSync, recebido: false, dataVencimento: pag.dataVencimento, observacao: 'Restante'));
                    valorRestanteSync = 0;
                  }
                } else {
                  novosPagamentosPedido.add(pag);
                }
              }
              final todosRecebidosSync = novosPagamentosPedido.every((p) => p.recebido);
              await dataService.updatePedido(pedidoVinculado.copyWith(
                status: todosRecebidosSync ? 'Pago' : pedidoVinculado.status,
                pagamentos: novosPagamentosPedido,
                updatedAt: hoje,
              ));
            } catch (_) {}
        } catch(e) {}
      } else if (conta.id.startsWith('pedido_')) {
        // Processar pedido — atualizar pagamentos fiado/crediário (igual ao PDV)
        final idReal = conta.id.replaceFirst('pedido_', '');
        try {
          final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
          
          // Determinar o tipo de crédito original (fiado ou crediario)
          TipoPagamento? tipoCredito;
          for (final pag in pedido.pagamentos) {
            if (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario) {
              tipoCredito = pag.tipo;
              break;
            }
          }
          if (tipoCredito == null) {
            // Sem fiado/crediário — usar o fluxo antigo
            List<RegistroPagamento> novosRegistros = [];
            if (aplicado1 > 0.001) {
              novosRegistros.add(RegistroPagamento(
                id: const Uuid().v4(), dataPagamento: hoje, valor: aplicado1, formaPagamento: forma1.nome,
              ));
            }
            if (aplicado2 > 0.001) {
              novosRegistros.add(RegistroPagamento(
                id: const Uuid().v4(), dataPagamento: hoje, valor: aplicado2, formaPagamento: forma2.nome,
              ));
            }
            final novoHistorico = [...conta.historicoPagamentos, ...novosRegistros];
            final novoValorPago = (conta.valorPago ?? 0.0) + valorAplicado;
            final novoStatus = novoValorPago >= (conta.valor - 0.001) ? StatusContaPagar.pago : StatusContaPagar.pendente;
            await dataService.updateContaPagar(conta.copyWith(
              valorPago: novoValorPago,
              status: novoStatus,
              dataPagamento: novoStatus == StatusContaPagar.pago ? hoje : conta.dataPagamento,
              formaPagamento: forma1.nome,
              historicoPagamentos: novoHistorico,
              updatedAt: hoje,
            ));
            continue;
          }

          // Fluxo PDV: atualizar pagamentos do pedido diretamente
          final valorRestante = valorAplicado;
          double valorAProcessar = valorRestante;
          final novosPagamentos = <PagamentoPedido>[];

          for (final pag in pedido.pagamentos) {
            if (pag.tipo == tipoCredito && !pag.recebido && valorAProcessar > 0) {
              if (valorAProcessar >= pag.valor) {
                novosPagamentos.add(PagamentoPedido(
                  id: pag.id,
                  tipo: forma1,
                  tipoOriginal: tipoCredito,
                  valor: pag.valor,
                  recebido: true,
                  dataRecebimento: hoje,
                  dataVencimento: pag.dataVencimento,
                  observacao: 'Recebido do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "crediário"}',
                ));
                valorAProcessar -= pag.valor;
              } else {
                novosPagamentos.add(PagamentoPedido(
                  id: '${pag.id}_pago',
                  tipo: forma1,
                  tipoOriginal: tipoCredito,
                  valor: valorAProcessar,
                  recebido: true,
                  dataRecebimento: hoje,
                  observacao: 'Recebimento parcial',
                ));
                novosPagamentos.add(PagamentoPedido(
                  id: '${pag.id}_resto',
                  tipo: tipoCredito,
                  valor: pag.valor - valorAProcessar,
                  recebido: false,
                  dataVencimento: pag.dataVencimento,
                  observacao: 'Restante do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "crediário"}',
                ));
                valorAProcessar = 0;
              }
            } else {
              novosPagamentos.add(pag);
            }
          }

          final todosRecebidos = novosPagamentos.every((p) => p.recebido);
          final pedidoAtualizado = pedido.copyWith(
            status: todosRecebidos ? 'Pago' : pedido.status,
            pagamentos: novosPagamentos,
            updatedAt: hoje,
          );
          await dataService.updatePedido(pedidoAtualizado);

          // Atualizar saldo devedor do cliente (fiado E crediário)
          if ((tipoCredito == TipoPagamento.fiado || tipoCredito == TipoPagamento.crediario) && pedido.clienteId != null) {
            final cliente = dataService.clientes.firstWhere(
              (c) => c.id == pedido.clienteId,
              orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje),
            );
            if (cliente.id.isNotEmpty) {
              final novoSaldo = (cliente.saldoDevedor - valorAplicado).clamp(0.0, double.infinity);
              await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
            }
          }
        } catch(e) {}
      } else {
        // Conta avulsa — fluxo antigo
        List<RegistroPagamento> novosPagamentos = [];
        if (aplicado1 > 0.001) {
          novosPagamentos.add(RegistroPagamento(
            id: const Uuid().v4(),
            dataPagamento: hoje,
            valor: aplicado1,
            formaPagamento: forma1.nome,
          ));
        }
        if (aplicado2 > 0.001) {
          novosPagamentos.add(RegistroPagamento(
            id: const Uuid().v4(),
            dataPagamento: hoje,
            valor: aplicado2,
            formaPagamento: forma2.nome,
          ));
        }
        
        final novoHistorico = [...conta.historicoPagamentos, ...novosPagamentos];
        final novoValorPago = (conta.valorPago ?? 0.0) + valorAplicado;
        final novoStatus = novoValorPago >= (conta.valor - 0.001) ? StatusContaPagar.pago : StatusContaPagar.pendente;
        
        await dataService.updateContaPagar(conta.copyWith(
          valorPago: novoValorPago,
          dataPagamento: novoStatus == StatusContaPagar.pago ? hoje : conta.dataPagamento,
          status: novoStatus,
          formaPagamento: forma1.nome,
          historicoPagamentos: novoHistorico,
          updatedAt: hoje,
        ));
      }
    }
    
    setState(() {
      _selecionadas.clear();
    });

    if (mounted && totalRecebido > 0) {
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final clienteLabel = nomeCliente.isNotEmpty ? nomeCliente : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Recebimento Concluído', style: TextStyle(color: Colors.white)),
          content: Text(
            'Deseja imprimir o recibo de ${formatoMoeda.format(totalRecebido)}${clienteLabel.isNotEmpty ? ' para $clienteLabel' : ''}?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Não', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _imprimirReciboBaixa(contasLote, totalRecebido, forma1, nomeCliente);
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Imprimir Recibo'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      );
    }
  }

  void _imprimirReciboBaixa(List<ContaPagar> contasLote, double totalRecebido, TipoPagamento forma, String nomeCliente) async {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context ctx) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('RECIBO DE RECEBIMENTO', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            if (empresa != null) pw.Text(empresa.razaoSocial, style: pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 8),
            pw.Text('Data: ${formatoData.format(DateTime.now())}'),
            if (nomeCliente.isNotEmpty) pw.Text('Cliente: $nomeCliente'),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 8),
            ...contasLote.where((c) => c.statusAtualizado != StatusContaPagar.pago).map((c) =>
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(c.descricao, style: const pw.TextStyle(fontSize: 10))),
                    pw.Text(formatoMoeda.format(c.valorPendente), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Recebido:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(formatoMoeda.format(totalRecebido), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
              ],
            ),
            pw.Text('Forma: ${forma.nome}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 30),
            pw.Text('_______________________________', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Assinatura', style: const pw.TextStyle(fontSize: 10)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Recibo_${nomeCliente.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
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
    final isPago = statusAtual == StatusContaPagar.pago;
    final isCancelado = statusAtual == StatusContaPagar.cancelado;
    final isSelecionado = _selecionadas.contains(conta.id);
    final podeReceber = !isPago && !isCancelado;

    // Corresponde ao estilo do PDV/Pedidos
    final gradient = isSelecionado
        ? [Colors.blue.shade700.withOpacity(0.4), Colors.blue.shade900.withOpacity(0.3)]
        : isCancelado
        ? [Colors.red.shade900, Colors.red.shade800]
        : isPago
        ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
        : isVencida
        ? [const Color(0xFF8B0000), const Color(0xFFB71C1C)]
        : isProximoVenc
        ? [const Color(0xFFE65100), const Color(0xFFEF6C00)]
        : [const Color(0xFF2C3E50), const Color(0xFF34495E)];

    final Color corBorda = isSelecionado
        ? Colors.blueAccent
        : isCancelado
        ? Colors.redAccent
        : isPago
        ? Colors.greenAccent
        : isVencida
        ? Colors.redAccent
        : isProximoVenc
        ? Colors.orangeAccent
        : Colors.blueAccent;

    final borderWidth = isSelecionado ? 3.0 : 2.0;

    // Texto do tipo de crédito
    String tipoTexto = '';
    if (conta.id.startsWith('venda_')) {
      final idReal = conta.id.replaceFirst('venda_', '');
      try {
        final v = Provider.of<DataService>(context, listen: false).vendasBalcao.firstWhere((v) => v.id == idReal);
        tipoTexto = v.tipoPagamento == TipoPagamento.fiado ? 'Fiado' : v.tipoPagamento == TipoPagamento.crediario ? 'Crediário' : v.tipoPagamento.nome;
      } catch (_) {
        tipoTexto = 'Venda';
      }
    } else if (conta.id.startsWith('pedido_')) {
      tipoTexto = 'Fiado';
    } else {
      tipoTexto = 'Avulsa';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corBorda, width: borderWidth),
      ),
      child: InkWell(                    onTap: podeReceber
            ? () => _mostrarDialogoPagamento(context, conta)
            : (conta.id.startsWith('venda_') ? () => _mostrarDetalhesVendaPrazo(context, conta) : (conta.id.startsWith('pedido_') ? () => _mostrarDetalhesPedidoPrazo(context, conta) : null)),
        onLongPress: () {
          setState(() {
            if (isSelecionado) _selecionadas.remove(conta.id);
            else _selecionadas.add(conta.id);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Checkbox + Descrição + Badge + Valor
              Row(
                children: [
                  Checkbox(
                    value: isSelecionado,
                    activeColor: Colors.green,
                    side: BorderSide(color: Colors.white.withOpacity(0.4)),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) _selecionadas.add(conta.id);
                        else _selecionadas.remove(conta.id);
                      });
                    },
                  ),
                  // Ícone de status
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: corBorda.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPago ? Icons.check_circle : isVencida ? Icons.error : isProximoVenc ? Icons.warning : Icons.pending,
                      color: corBorda,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Descrição + Badge tipo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                conta.descricao,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPago ? Colors.green.withOpacity(0.3) : isVencida ? Colors.red.withOpacity(0.3) : Colors.blue.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tipoTexto,
                                style: TextStyle(
                                  color: isPago ? Colors.greenAccent : isVencida ? Colors.redAccent : Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Recebível',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Valor
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'R\$ ${conta.valor.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      if (podeReceber && conta.valorPago != null && conta.valorPago! > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Falta: R\$ ${conta.valorPendente.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              // Barra de progresso (parcialmente pago)
              if (podeReceber && conta.valorPago != null && conta.valorPago! > 0 && !isPago) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ((conta.valorPago! / conta.valor).clamp(0.0, 1.0)),
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recebido: R\$ ${conta.valorPago!.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                    ),
                    Text(
                      '${((conta.valorPago! / conta.valor) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Linha 2: Cliente
              if (conta.fornecedorNome != null && conta.fornecedorNome!.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.white.withOpacity(0.6), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        conta.fornecedorNome!,
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Linha 3: Data + Status + Botão receber
              Row(
                children: [
                  // Data vencimento
                  Icon(Icons.calendar_today, size: 12, color: Colors.white.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Venc: ${formatoData.format(conta.dataVencimento)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: corBorda.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusAtual.nome,
                      style: TextStyle(
                        color: corBorda,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Botão receber (se pendente/vencida)
                  if (podeReceber)
                    ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoPagamento(context, conta),
                      icon: const Icon(Icons.payment, size: 14),
                      label: Text(
                        'Receber R\$ ${conta.valorPendente.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  // Botão ver extrato do cliente
                  if (conta.fornecedorNome != null && conta.fornecedorNome!.isNotEmpty && conta.fornecedorNome != 'Cliente não informado') ...[
                    const SizedBox(width: 6),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      color: Colors.blueAccent,
                      tooltip: 'Extrato do Cliente',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ContaReceberExtratoPage(
                              clienteNome: conta.fornecedorNome!,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              // Histórico de pagamentos (se houver)
              if (conta.historicoPagamentos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, color: Colors.blue, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Pagamentos (${conta.historicoPagamentos.length})',
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...conta.historicoPagamentos.reversed.take(3).map((pag) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                '${formatoData.format(pag.dataPagamento)} - ${pag.formaPagamento ?? ""}',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
                              ),
                              const Spacer(),
                              Text(
                                formatoMoeda.format(pag.valor),
                                style: TextStyle(color: Colors.green[300], fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Pago em (se pago)
              if (isPago && conta.dataPagamento != null && conta.historicoPagamentos.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Pago em ${formatoData.format(conta.dataPagamento!)}',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      if (conta.formaPagamento != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${conta.formaPagamento})',
                          style: TextStyle(color: Colors.green.withOpacity(0.7), fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
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


  void _mostrarDetalhesVendaPrazo(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final vendaId = conta.id.replaceAll('venda_', '');
    final venda = dataService.vendasBalcao.firstWhere((v) => v.id == vendaId);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text('Detalhes - ${venda.numero}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cliente: ${venda.clienteNome ?? "Não informado"}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (venda.clienteNome == null || venda.clienteNome!.isEmpty) ...[
                const SizedBox(height: 8),
                Autocomplete<Cliente>(
                  displayStringForOption: (c) => c.nome,
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) return dataService.clientes;
                    return dataService.clientes.where((c) => c.nome.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  onSelected: (c) async {
                    final vendaAtualizada = venda.copyWith(
                      clienteId: c.id,
                      clienteNome: c.nome,
                      updatedAt: DateTime.now(),
                    );
                    await dataService.updateVendaBalcao(vendaAtualizada);
                    if (context.mounted) Navigator.pop(ctx);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Vincular Cliente...',
                        prefixIcon: const Icon(Icons.person_add, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: const Color(0xFF1E1E2E),
                        elevation: 4.0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: SizedBox(
                          width: 250,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: options.length,
                            shrinkWrap: true,
                            itemBuilder: (BuildContext context, int index) {
                              final Cliente option = options.elementAt(index);
                              return ListTile(
                                leading: const Icon(Icons.person, color: Colors.orange, size: 20),
                                title: Text(option.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              Text('Total da Venda: ${formatoMoeda.format(venda.valorTotal)}'),
              Text('Já Recebido: ${formatoMoeda.format(venda.valorRecebido ?? 0.0)}', style: const TextStyle(color: Colors.green)),
              Text('Pendente: ${formatoMoeda.format(venda.valorTotal - (venda.valorRecebido ?? 0.0))}', style: const TextStyle(color: Colors.orange)),
              const Divider(),
              Text('Vencimento: ${formatoData.format(conta.dataVencimento)}'),
              const SizedBox(height: 16),
              const Text('Itens da Venda:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...venda.itens.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text('- ${i.quantidade}x ${i.nome} (${formatoMoeda.format(i.quantidade * i.precoUnitario)})'),
              )).toList(),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('Alterar Vencimento'),
            onPressed: () async {
              final data = await showDatePicker(
                context: context,
                initialDate: conta.dataVencimento,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (data != null) {
                // Atualiza observação da venda com a nova tag
                String novaObs = venda.observacoes ?? '';
                novaObs = novaObs.replaceAll(RegExp(r'\[VENC:\s*(\d{4}-\d{2}-\d{2})\]'), '').trim();
                final tag = '[VENC: ${data.toIso8601String().substring(0, 10)}]';
                novaObs = novaObs.isEmpty ? tag : '$novaObs $tag';
                
                final vendaAtualizada = venda.copyWith(
                  observacoes: novaObs,
                  updatedAt: DateTime.now(),
                );
                await dataService.updateVendaBalcao(vendaAtualizada);
                Navigator.pop(ctx);
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.receipt, size: 18),
            label: const Text('Extrato'),
            onPressed: () {
              // Mostra o extrato
              String extrato = 'EXTRATO DE COMPRA\n';
              extrato += 'Sistema Exodo\n';
              extrato += '------------------------\n';
              extrato += 'Cliente: ${venda.clienteNome ?? "Não informado"}\n';
              extrato += 'Venda: ${venda.numero}\n';
              extrato += 'Data: ${formatoData.format(venda.dataVenda)}\n';
              extrato += '------------------------\n';
              for (var i in venda.itens) {
                extrato += '${i.quantidade}x ${i.nome} = ${formatoMoeda.format(i.quantidade * i.precoUnitario)}\n';
              }
              extrato += '------------------------\n';
              extrato += 'Total: ${formatoMoeda.format(venda.valorTotal)}\n';
              extrato += 'Pago: ${formatoMoeda.format(venda.valorRecebido ?? 0)}\n';
              extrato += 'Falta: ${formatoMoeda.format(venda.valorTotal - (venda.valorRecebido ?? 0))}\n';
              extrato += 'Vencimento: ${formatoData.format(conta.dataVencimento)}\n';
              
              showDialog(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('Extrato'),
                  content: SelectableText(extrato, style: const TextStyle(fontFamily: 'monospace')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Fechar'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(extrato)}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('WhatsApp não instalado ou inacessível.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('WhatsApp'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ],
                )
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }


  void _mostrarDetalhesPedidoPrazo(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final pedidoId = conta.id.replaceAll('pedido_', '');
    Pedido? pedido;
    try {
      pedido = dataService.pedidos.firstWhere((p) => p.id == pedidoId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido não encontrado'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    // pedido é não-nulo a partir daqui
    final p = pedido;
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Calcular valores do pedido
    double valorCredito = 0;
    double valorPago = 0;
    for (final pag in p.pagamentos) {
      if (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario ||
          pag.tipoOriginal == TipoPagamento.fiado || pag.tipoOriginal == TipoPagamento.crediario) {
        valorCredito += pag.valor;
        if (pag.recebido) valorPago += pag.valor;
      }
    }
    final valorPendente = valorCredito - valorPago;
    final isFiado = p.pagamentos.any((pg) => pg.tipo == TipoPagamento.fiado);
    final tipoLabel = isFiado ? 'Fiado' : 'Crediário';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isFiado ? Icons.handshake : Icons.credit_score, color: isFiado ? Colors.deepOrange : Colors.pink),
            const SizedBox(width: 8),
            Expanded(child: Text('Detalhes - ${p.numero}', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tipo: $tipoLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Cliente: ${p.clienteNome ?? "Não informado"}'),
              Text('Data: ${formatoData.format(p.dataPedido)}'),
              const Divider(),
              Text('Total do Pedido: ${formatoMoeda.format(p.totalGeral)}'),
              Text('Valor Pago: ${formatoMoeda.format(valorPago)}', style: const TextStyle(color: Colors.green)),
              Text('Pendente: ${formatoMoeda.format(valorPendente)}', style: const TextStyle(color: Colors.orange)),
              const SizedBox(height: 12),
              const Text('Itens:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...p.produtos.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('- ${i.quantidade}x ${i.nome} (${formatoMoeda.format(i.quantidade * i.preco)})'),
              )),
              if (p.servicos.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Serviços:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...p.servicos.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('- ${s.descricao} (${formatoMoeda.format(s.valor)})'),
                )),
              ],
              if (p.observacoes != null && p.observacoes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Obs: ${p.observacoes}', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          // Botão Extrato
          TextButton.icon(
            icon: const Icon(Icons.receipt, size: 18),
            label: const Text('Extrato'),
            onPressed: () async {
              Navigator.pop(ctx);
              final empresa = dataService.empresaAtual;
              if (empresa == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Empresa não configurada.'), backgroundColor: Colors.red),
                  );
                }
                return;
              }
              String? clienteCodigo;
              if (p.clienteId != null) {
                final cli = dataService.clientes.firstWhere(
                  (c) => c.id == p.clienteId,
                  orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
                );
                if (cli.id.isNotEmpty) {
                  clienteCodigo = cli.dadosExtras?['codigo']?.toString();
                }
              }
              await _mostrarDialogoTipoImpressaoExtratoPedido(
                pedidos: [p],
                clienteNome: p.clienteNome ?? 'Cliente',
                clienteCodigo: clienteCodigo,
                empresa: empresa,
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoTipoImpressaoExtratoPedido({
    required List<Pedido> pedidos,
    required String clienteNome,
    required String? clienteCodigo,
    required Empresa empresa,
  }) async {
    bool mostrarItens = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Imprimir Extrato', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Mostrar itens de cada venda', style: TextStyle(color: Colors.white70, fontSize: 14)),
                value: mostrarItens,
                activeColor: Colors.deepOrange,
                checkColor: Colors.white,
                onChanged: (val) => setDialogState(() => mostrarItens = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                title: const Text('A4 / Compartilhar', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await PedidoPDFService.imprimirExtratoFiado(
                    context: context,
                    pedidos: pedidos,
                    clienteNome: clienteNome,
                    clienteCodigo: clienteCodigo,
                    empresa: empresa,
                    mostrarItens: mostrarItens,
                  );
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.blueAccent),
                title: const Text('Impressora Térmica (80mm)', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await PedidoPDFService.imprimirExtratoFiadoTermico(
                    context: context,
                    pedidos: pedidos,
                    clienteNome: clienteNome,
                    clienteCodigo: clienteCodigo,
                    empresa: empresa,
                    mostrarItens: mostrarItens,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    final valorPendente = conta.valorPendente;
    final acrescimoController = TextEditingController(text: '0,00');
    final descontoController = TextEditingController(text: '0,00');
    final valorController = TextEditingController(
      text: valorPendente.toStringAsFixed(2).replaceAll('.', ','),
    );
    TipoPagamento? formaSelecionada;

    // Determine if fiado or crediario
    String tipoCreditoLabel = 'Fiado';
    if (conta.id.startsWith('pedido_')) {
      final idReal = conta.id.replaceFirst('pedido_', '');
      try {
        final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
        for (final pag in pedido.pagamentos) {
          if (pag.tipo == TipoPagamento.crediario) {
            tipoCreditoLabel = 'Credito';
            break;
          }
        }
      } catch (_) {}
    } else if (conta.id.contains('crediario') || conta.id.contains('credito')) {
      tipoCreditoLabel = 'Credito';
    }

    final corPrincipal = tipoCreditoLabel == 'Fiado' ? const Color(0xFFD84315) : const Color(0xFFE91E63);

    // Formas de recebimento (sem fiado nem crediario)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado && t != TipoPagamento.crediario)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final acrescimo = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
          final desconto = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
          final totalComAcerto = valorPendente + acrescimo - desconto;
          final valorDigitado = double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0;
          final isParcial = valorDigitado > 0 && valorDigitado < totalComAcerto - 0.01;
          final valorRestante = totalComAcerto - valorDigitado;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corPrincipal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments, color: corPrincipal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Receber $tipoCreditoLabel', style: const TextStyle(color: Colors.white, fontSize: 18)),
                      Text(
                        conta.fornecedorNome ?? 'Cliente',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
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
                  // Total pendente
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: corPrincipal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: corPrincipal.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Pendente', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                            Text('1 venda(s)', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                          ],
                        ),
                        Text(formatoMoeda.format(valorPendente), style: TextStyle(color: corPrincipal, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Acrecimo e Desconto
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Acréscimo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: acrescimoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              onChanged: (_) {
                                final a = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                                final d = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                                valorController.text = (valorPendente + a - d).toStringAsFixed(2).replaceAll('.', ',');
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Desconto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: descontoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              onChanged: (_) {
                                final a = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                                final d = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                                valorController.text = (valorPendente + a - d).toStringAsFixed(2).replaceAll('.', ',');
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Valor a receber
                  const Text('Valor a receber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 24, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: corPrincipal)),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),

                  if (isParcial) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pagamento parcial: restará ${formatoMoeda.format(valorRestante)}',
                              style: const TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Forma de recebimento
                  const Text('Forma de recebimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setDialogState(() => formaSelecionada = tipo),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? cor.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? cor : Colors.white.withOpacity(0.2), width: isSelected ? 2 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getIconeTipoRecebimento(tipo), color: isSelected ? cor : Colors.white54, size: 18),
                                const SizedBox(width: 6),
                                Text(tipo.nome, style: TextStyle(color: isSelected ? cor : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: (formaSelecionada == null || valorDigitado <= 0 || valorDigitado > totalComAcerto + 0.01)
                    ? null
                    : () async {
                        final forma = formaSelecionada!;
                        final acrescimoVal = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                        final descontoVal = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                        final hoje = DateTime.now();
                        final totalReceber = valorDigitado - acrescimoVal + descontoVal;

                        // ======== VENDA ========
                        if (conta.id.startsWith('venda_')) {
                          final idReal = conta.id.replaceFirst('venda_', '');
                          try {
                            final vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
                            final novoRecebido = (vendaOriginal.valorRecebido ?? 0.0) + totalReceber;
                            await dataService.updateVendaBalcao(vendaOriginal.copyWith(
                              // NÃO altera tipoPagamento — mantém fiado/crediário para a conta continuar aparecendo
                              valorRecebido: novoRecebido,
                              updatedAt: hoje,
                            ));
                            // Baixa saldo devedor do cliente (fiado E crediário)
                            if ((vendaOriginal.tipoPagamento == TipoPagamento.fiado || vendaOriginal.tipoPagamento == TipoPagamento.crediario) && vendaOriginal.clienteId != null) {
                              final cliente = dataService.clientes.firstWhere((c) => c.id == vendaOriginal.clienteId, orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje));
                              if (cliente.id.isNotEmpty) {
                                final novoSaldo = (cliente.saldoDevedor - totalReceber).clamp(0.0, double.infinity);
                                await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
                              }
                            }
                            // Sincronizar Pedido vinculado à VendaBalcao (para que a tela de Pedidos reflita o pagamento)
                            try {
                              final pedidoVinculado = dataService.pedidos.firstWhere((p) => p.id == vendaOriginal.id);
                              final novoValorRecebidoPedido = (vendaOriginal.valorRecebido ?? 0.0);
                              // Atualizar pagamentos do pedido: marcar como recebidos
                              final novosPagamentosPedido = <PagamentoPedido>[];
                              double valorRestanteSync = totalReceber;
                              for (final pag in pedidoVinculado.pagamentos) {
                                if (!pag.recebido && valorRestanteSync > 0 && (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario || pag.tipoOriginal == TipoPagamento.fiado || pag.tipoOriginal == TipoPagamento.crediario)) {
                                  if (valorRestanteSync >= pag.valor) {
                                    novosPagamentosPedido.add(PagamentoPedido(id: pag.id, tipo: forma, tipoOriginal: pag.tipo, valor: pag.valor, recebido: true, dataRecebimento: hoje, dataVencimento: pag.dataVencimento, observacao: 'Recebido via Contas a Receber'));
                                    valorRestanteSync -= pag.valor;
                                  } else {
                                    novosPagamentosPedido.add(PagamentoPedido(id: '${pag.id}_pago', tipo: forma, tipoOriginal: pag.tipo, valor: valorRestanteSync, recebido: true, dataRecebimento: hoje, observacao: 'Recebimento parcial via Contas a Receber'));
                                    novosPagamentosPedido.add(PagamentoPedido(id: '${pag.id}_resto', tipo: pag.tipo, valor: pag.valor - valorRestanteSync, recebido: false, dataVencimento: pag.dataVencimento, observacao: 'Restante'));
                                    valorRestanteSync = 0;
                                  }
                                } else {
                                  novosPagamentosPedido.add(pag);
                                }
                              }
                              final todosRecebidosSync = novosPagamentosPedido.every((p) => p.recebido);
                              await dataService.updatePedido(pedidoVinculado.copyWith(
                                status: todosRecebidosSync ? 'Pago' : pedidoVinculado.status,
                                pagamentos: novosPagamentosPedido,
                                updatedAt: hoje,
                              ));
                            } catch (_) {
                              // Pedido não encontrado — pode ser venda direta sem pedido vinculado
                            }
                          } catch (e) { debugPrint('Erro ao atualizar venda: $e'); }
                        }

                        // ======== PEDIDO ========
                        else if (conta.id.startsWith('pedido_')) {
                          final idReal = conta.id.replaceFirst('pedido_', '');
                          try {
                            final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
                            TipoPagamento? tipoCredito;
                            for (final pag in pedido.pagamentos) {
                              if (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario) {
                                tipoCredito = pag.tipo;
                                break;
                              }
                            }
                            if (tipoCredito != null) {
                              double valorRest = valorDigitado - acrescimoVal + descontoVal;
                              final novosPagamentos = <PagamentoPedido>[];
                              bool aplicouTaxas = false;
                              for (final pag in pedido.pagamentos) {
                                if (pag.tipo == tipoCredito && !pag.recebido && valorRest > 0) {
                                  if (!aplicouTaxas) {
                                    if (acrescimoVal > 0) { novosPagamentos.add(PagamentoPedido(id: 'acrescimo_${DateTime.now().millisecondsSinceEpoch}', tipo: forma, tipoOriginal: tipoCredito, valor: acrescimoVal, recebido: true, dataRecebimento: hoje, observacao: 'Acréscimo recebimento')); }
                                    if (descontoVal > 0) { novosPagamentos.add(PagamentoPedido(id: 'desconto_${DateTime.now().millisecondsSinceEpoch}', tipo: forma, tipoOriginal: tipoCredito, valor: -descontoVal, recebido: true, dataRecebimento: hoje, observacao: 'Desconto recebimento')); }
                                    aplicouTaxas = true;
                                  }
                                  if (valorRest >= pag.valor) {
                                    novosPagamentos.add(PagamentoPedido(id: pag.id, tipo: forma, tipoOriginal: tipoCredito, valor: pag.valor, recebido: true, dataRecebimento: hoje, dataVencimento: pag.dataVencimento, observacao: 'Recebido do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "credito"}'));
                                    valorRest -= pag.valor;
                                  } else {
                                    novosPagamentos.add(PagamentoPedido(id: '${pag.id}_pago', tipo: forma, tipoOriginal: tipoCredito, valor: valorRest, recebido: true, dataRecebimento: hoje, observacao: 'Recebimento parcial'));
                                    novosPagamentos.add(PagamentoPedido(id: '${pag.id}_resto', tipo: tipoCredito, valor: pag.valor - valorRest, recebido: false, dataVencimento: pag.dataVencimento, observacao: 'Restante do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "credito"}'));
                                    valorRest = 0;
                                  }
                                } else {
                                  novosPagamentos.add(pag);
                                }
                              }
                              final todosRecebidos = novosPagamentos.every((p) => p.recebido);
                              await dataService.updatePedido(pedido.copyWith(
                                total: aplicouTaxas ? (pedido.total + acrescimoVal - descontoVal) : pedido.total,
                                status: todosRecebidos ? 'Pago' : pedido.status,
                                pagamentos: novosPagamentos,
                                updatedAt: hoje,
                              ));
                            }
                            // Baixa saldo devedor do cliente (fiado E crediário)
                            if ((tipoCredito == TipoPagamento.fiado || tipoCredito == TipoPagamento.crediario) && pedido.clienteId != null) {
                              final cliente = dataService.clientes.firstWhere((c) => c.id == pedido.clienteId, orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje));
                              if (cliente.id.isNotEmpty) {
                                final novoSaldo = (cliente.saldoDevedor - totalReceber).clamp(0.0, double.infinity);
                                await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
                              }
                            }
                          } catch (e) { debugPrint('Erro ao atualizar pedido: $e'); }
                        }

                        // ======== AVULSA ========
                        else {
                          final novoValorPago = (conta.valorPago ?? 0.0) + totalReceber;
                          final novoStatus = (novoValorPago >= conta.valor - 0.01) ? StatusContaPagar.pago : conta.status;
                          final novoRegistro = RegistroPagamento(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            valor: totalReceber,
                            dataPagamento: hoje,
                            formaPagamento: forma.nome,
                          );
                          final novoHistorico = List<RegistroPagamento>.from(conta.historicoPagamentos)..add(novoRegistro);
                          final contaAtualizada = conta.copyWith(
                            valorPago: novoValorPago,
                            dataPagamento: novoStatus == StatusContaPagar.pago ? hoje : conta.dataPagamento,
                            status: novoStatus,
                            formaPagamento: forma.nome,
                            historicoPagamentos: novoHistorico,
                            updatedAt: hoje,
                          );
                          await dataService.updateContaPagar(contaAtualizada);
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        setState(() {});

                        final msg = (valorDigitado >= totalComAcerto - 0.01)
                            ? 'Recebimento concluido com sucesso!'
                            : 'Pagamento parcial de ${formatoMoeda.format(valorDigitado)} registrado. Restante: ${formatoMoeda.format(totalComAcerto - valorDigitado)}';
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(seconds: 3)));
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (formaSelecionada != null && valorDigitado > 0) ? corPrincipal : Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getIconeTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      case TipoPagamento.transferencia:
        return Icons.swap_horiz;
    }
  }

  Color _getCorTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return const Color(0xFF00BFA5);
      case TipoPagamento.cartaoCredito:
        return Colors.deepPurple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return const Color(0xFFE91E63);
      case TipoPagamento.fiado:
        return const Color(0xFFD84315);
      case TipoPagamento.outro:
        return Colors.grey;
      case TipoPagamento.alimentacao:
        return const Color(0xFF00897B);
      case TipoPagamento.transferencia:
        return const Color(0xFF42A5F5);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ABA ATRASADOS — Relatório completo de contas vencidas
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAbaAtrasados(List<ContaPagar> todasContas, NumberFormat formatoMoeda, DateFormat formatoData) {
    final hoje = DateTime.now();
    final atrasadas = todasContas.where((c) {
      final st = c.statusAtualizado;
      return st == StatusContaPagar.vencido;
    }).toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    final totalAtrasado = atrasadas.fold<double>(0.0, (s, c) => s + c.valorPendente);

    // Faixas de atraso
    final ate7 = atrasadas.where((c) => hoje.difference(c.dataVencimento).inDays <= 7).toList();
    final de8a30 = atrasadas.where((c) {
      final d = hoje.difference(c.dataVencimento).inDays;
      return d > 7 && d <= 30;
    }).toList();
    final de31a60 = atrasadas.where((c) {
      final d = hoje.difference(c.dataVencimento).inDays;
      return d > 30 && d <= 60;
    }).toList();
    final mais60 = atrasadas.where((c) => hoje.difference(c.dataVencimento).inDays > 60).toList();

    if (atrasadas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 80, color: Colors.greenAccent.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('Nenhuma conta atrasada!', style: TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Todos os pagamentos estão em dia', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho de risco
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF8B0000).withOpacity(0.9), const Color(0xFFB71C1C).withOpacity(0.9)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
                const SizedBox(height: 10),
                Text(formatoMoeda.format(totalAtrasado), style: const TextStyle(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                Text('${atrasadas.length} conta(s) atrasada(s)', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Resumo por faixa
          _buildResumoFaixas(ate7.length, de8a30.length, de31a60.length, mais60.length),
          const SizedBox(height: 20),

          // Lista por faixa de atraso
          if (ate7.isNotEmpty) ...[
            _secaoAtraso('Até 7 dias', Colors.orangeAccent, ate7, formatoMoeda, formatoData),
            const SizedBox(height: 16),
          ],
          if (de8a30.isNotEmpty) ...[
            _secaoAtraso('8 a 30 dias', Colors.deepOrangeAccent, de8a30, formatoMoeda, formatoData),
            const SizedBox(height: 16),
          ],
          if (de31a60.isNotEmpty) ...[
            _secaoAtraso('31 a 60 dias', Colors.redAccent, de31a60, formatoMoeda, formatoData),
            const SizedBox(height: 16),
          ],
          if (mais60.isNotEmpty) ...[
            _secaoAtraso('Mais de 60 dias', Colors.deepPurpleAccent, mais60, formatoMoeda, formatoData),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoFaixas(int ate7, int de8a30, int de31a60, int mais60) {
    return Row(
      children: [
        _faixaResumo('1-7d', ate7, Colors.orangeAccent),
        const SizedBox(width: 8),
        _faixaResumo('8-30d', de8a30, Colors.deepOrangeAccent),
        const SizedBox(width: 8),
        _faixaResumo('31-60d', de31a60, Colors.redAccent),
        const SizedBox(width: 8),
        _faixaResumo('60d+', mais60, Colors.deepPurpleAccent),
      ],
    );
  }

  Widget _faixaResumo(String label, int qtd, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cor.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text('$qtd', style: TextStyle(color: cor, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: cor.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _secaoAtraso(String faixa, Color cor, List<ContaPagar> contas, NumberFormat formatoMoeda, DateFormat formatoData) {
    final total = contas.fold<double>(0, (s, c) => s + c.valorPendente);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 22, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(faixa, style: TextStyle(color: cor, fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${contas.length} — ${formatoMoeda.format(total)}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        ...contas.map((c) => _buildCardAtrasado(c, cor, formatoMoeda, formatoData)),
      ],
    );
  }

  Widget _buildCardAtrasado(ContaPagar conta, Color cor, NumberFormat formatoMoeda, DateFormat formatoData) {
    final hoje = DateTime.now();
    final diasAtraso = hoje.difference(conta.dataVencimento).inDays;
    // Buscar itens
    final dataService = Provider.of<DataService>(context, listen: false);
    final itens = _buscarItensConta(conta, dataService);
    final isExpandida = _itensExpandidos.contains('${conta.id}_atri');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: itens.isNotEmpty ? () {
              setState(() {
                final key = '${conta.id}_atri';
                if (_itensExpandidos.contains(key)) _itensExpandidos.remove(key);
                else _itensExpandidos.add(key);
              });
            } : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Badge de dias
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(color: cor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$diasAtraso', style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('dias', style: TextStyle(color: cor.withOpacity(0.6), fontSize: 9)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(conta.descricao, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('Venc: ${formatoData.format(conta.dataVencimento)}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                        if (conta.fornecedorNome != null) Text(conta.fornecedorNome!, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                        if (itens.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.shopping_bag, size: 10, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(width: 4),
                            Text('${itens.length} item(ns)', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
                            if (!isExpandida) Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white.withOpacity(0.3)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatoMoeda.format(conta.valorPendente), style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold)),
                      if ((conta.valorPago ?? 0) > 0) Text('Pago: ${formatoMoeda.format(conta.valorPago)}', style: TextStyle(color: Colors.greenAccent.withOpacity(0.6), fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Itens expandidos
          if (isExpandida && itens.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 64, right: 12, bottom: 10),
              child: Column(
                children: itens.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Text('${item['qtd']}x ${item['nome']}', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11))),
                    Text(formatoMoeda.format(item['subtotal']), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ABA RELATÓRIO — Resumo financeiro completo
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAbaRelatorio(List<ContaPagar> contas, NumberFormat formatoMoeda, DateFormat formatoData, double totalPendente, double totalVencido, double totalRecebido) {
    final hoje = DateTime.now();
    final totalGeral = contas.fold<double>(0, (s, c) => s + c.valor);
    final qtdTotal = contas.length;
    final qtdPendentes = contas.where((c) => c.statusAtualizado == StatusContaPagar.pendente).length;
    final qtdVencidas = contas.where((c) => c.statusAtualizado == StatusContaPagar.vencido).length;
    final qtdPagas = contas.where((c) => c.statusAtualizado == StatusContaPagar.pago).length;
    final percentRecebido = totalGeral > 0 ? ((totalRecebido / totalGeral) * 100) : 0.0;

    // Agrupar por tipo
    final fiadoContas = contas.where((c) => c.id.contains('fiado') || _isFiado(c)).toList();
    final crediarioContas = contas.where((c) => c.id.contains('crediario') || _isCrediario(c)).toList();
    final avulsasContas = contas.where((c) => !fiadoContas.contains(c) && !crediarioContas.contains(c)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumo Geral
          _buildRelatorioCard(
            'Resumo Geral', Icons.assessment, Colors.blueAccent,
            [
              _relatorioLinha('Total de Contas', '$qtdTotal', Colors.white),
              _relatorioLinha('Pendentes', '$qtdPendentes', Colors.orangeAccent),
              _relatorioLinha('Vencidas', '$qtdVencidas', Colors.redAccent),
              _relatorioLinha('Pagas', '$qtdPagas', Colors.greenAccent),
              const Divider(color: Colors.white12),
              _relatorioLinha('Valor Total', formatoMoeda.format(totalGeral), Colors.white),
              _relatorioLinha('Recebido', formatoMoeda.format(totalRecebido), Colors.greenAccent),
              _relatorioLinha('Pendente', formatoMoeda.format(totalPendente), Colors.orangeAccent),
              _relatorioLinha('Vencido', formatoMoeda.format(totalVencido), Colors.redAccent),
            ],
          ),
          const SizedBox(height: 12),

          // Barra de progresso
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Taxa de Recebimento', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('${percentRecebido.toStringAsFixed(1)}%', style: TextStyle(color: percentRecebido >= 70 ? Colors.greenAccent : percentRecebido >= 40 ? Colors.orangeAccent : Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: percentRecebido / 100,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(percentRecebido >= 70 ? Colors.greenAccent : percentRecebido >= 40 ? Colors.orangeAccent : Colors.redAccent),
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Por Tipo
          if (fiadoContas.isNotEmpty) _buildRelatorioCard(
            'Fiado', Icons.handshake, const Color(0xFFD84315),
            [
              _relatorioLinha('Quantidade', '${fiadoContas.length}', Colors.white),
              _relatorioLinha('Total', formatoMoeda.format(fiadoContas.fold<double>(0, (s, c) => s + c.valor)), Colors.white),
              _relatorioLinha('Pago', formatoMoeda.format(fiadoContas.fold<double>(0, (s, c) => s + (c.valorPago ?? 0))), Colors.greenAccent),
              _relatorioLinha('Aberto', formatoMoeda.format(fiadoContas.fold<double>(0, (s, c) => s + c.valorPendente)), Colors.orangeAccent),
            ],
          ),
          if (fiadoContas.isNotEmpty) const SizedBox(height: 12),

          if (crediarioContas.isNotEmpty) _buildRelatorioCard(
            'Crediário', Icons.credit_score, const Color(0xFFE91E63),
            [
              _relatorioLinha('Quantidade', '${crediarioContas.length}', Colors.white),
              _relatorioLinha('Total', formatoMoeda.format(crediarioContas.fold<double>(0, (s, c) => s + c.valor)), Colors.white),
              _relatorioLinha('Pago', formatoMoeda.format(crediarioContas.fold<double>(0, (s, c) => s + (c.valorPago ?? 0))), Colors.greenAccent),
              _relatorioLinha('Aberto', formatoMoeda.format(crediarioContas.fold<double>(0, (s, c) => s + c.valorPendente)), Colors.orangeAccent),
            ],
          ),
          if (crediarioContas.isNotEmpty) const SizedBox(height: 12),

          if (avulsasContas.isNotEmpty) _buildRelatorioCard(
            'Avulsas', Icons.receipt, Colors.blueAccent,
            [
              _relatorioLinha('Quantidade', '${avulsasContas.length}', Colors.white),
              _relatorioLinha('Total', formatoMoeda.format(avulsasContas.fold<double>(0, (s, c) => s + c.valor)), Colors.white),
              _relatorioLinha('Pago', formatoMoeda.format(avulsasContas.fold<double>(0, (s, c) => s + (c.valorPago ?? 0))), Colors.greenAccent),
              _relatorioLinha('Aberto', formatoMoeda.format(avulsasContas.fold<double>(0, (s, c) => s + c.valorPendente)), Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelatorioCard(String titulo, IconData icone, Color cor, List<Widget> linhas) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 8),
            Text(titulo, style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          ...linhas,
        ],
      ),
    );
  }

  Widget _relatorioLinha(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
          Text(valor, style: TextStyle(color: cor, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  bool _isFiado(ContaPagar c) {
    final dataService = Provider.of<DataService>(context, listen: false);
    if (c.id.startsWith('venda_')) {
      try {
        final v = dataService.vendasBalcao.firstWhere((v) => v.id == c.id.replaceFirst('venda_', ''));
        return v.tipoPagamento == TipoPagamento.fiado;
      } catch (_) {}
    } else if (c.id.startsWith('pedido_')) {
      try {
        final p = dataService.pedidos.firstWhere((p) => p.id == c.id.replaceFirst('pedido_', ''));
        return p.pagamentos.any((pag) => pag.tipo == TipoPagamento.fiado);
      } catch (_) {}
    }
    return false;
  }

  bool _isCrediario(ContaPagar c) {
    final dataService = Provider.of<DataService>(context, listen: false);
    if (c.id.startsWith('venda_')) {
      try {
        final v = dataService.vendasBalcao.firstWhere((v) => v.id == c.id.replaceFirst('venda_', ''));
        return v.tipoPagamento == TipoPagamento.crediario;
      } catch (_) {}
    } else if (c.id.startsWith('pedido_')) {
      try {
        final p = dataService.pedidos.firstWhere((p) => p.id == c.id.replaceFirst('pedido_', ''));
        return p.pagamentos.any((pag) => pag.tipo == TipoPagamento.crediario);
      } catch (_) {}
    }
    return false;
  }

  List<Map<String, dynamic>> _buscarItensConta(ContaPagar conta, DataService ds) {
    if (conta.id.startsWith('venda_')) {
      final idReal = conta.id.replaceFirst('venda_', '');
      try {
        final venda = ds.vendasBalcao.firstWhere((v) => v.id == idReal);
        return venda.itens.map((i) => {'qtd': i.quantidade, 'nome': i.nome, 'subtotal': i.quantidade * i.precoUnitario}).toList();
      } catch (_) {}
    } else if (conta.id.startsWith('pedido_')) {
      final idReal = conta.id.replaceFirst('pedido_', '');
      try {
        final pedido = ds.pedidos.firstWhere((p) => p.id == idReal);
        final itens = <Map<String, dynamic>>[];
        for (final p in pedido.produtos) {
          itens.add({'qtd': p.quantidade, 'nome': p.nome, 'subtotal': p.quantidade * p.preco});
        }
        for (final s in pedido.servicos) {
          itens.add({'qtd': 1, 'nome': s.descricao, 'subtotal': s.valor + s.valorAdicional});
        }
        return itens;
      } catch (_) {}
    }
    return [];
  }
}

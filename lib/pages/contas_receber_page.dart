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
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'conta_receber_form_page.dart';
import '../widgets/sync_status_widget.dart';

class ContasReceberPage extends StatefulWidget {
  const ContasReceberPage({super.key});

  @override
  State<ContasReceberPage> createState() => _ContasReceberPageState();
}

class _ContasReceberPageState extends State<ContasReceberPage> {
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

  final List<String> _statusDisponiveis = [
    'Todos',
    'Pendente',
    'Vencido',
    'Pago',
    'Cancelado',
  ];

  final List<String> _tiposDisponiveis = [
    'Todos',
    'Vendas PDV',
    'Pedidos',
    'Avulsas',
  ];


  @override
  void initState() {
    super.initState();
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

  List<ContaPagar> _filtrarContas(List<ContaPagar> contas) {
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
          case 'Vendas PDV':
            return c.id.startsWith('venda_');
          case 'Pedidos':
            return c.id.startsWith('pedido_');
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
    
    // Obter vendas (todas as não canceladas para aparecerem no extrato do cliente)
    final vendasPrazo = dataService.vendasBalcao.where((v) {
      if (v.cancelado) return false;
      return true;
    }).map((v) {
      final valPago = v.valorRecebido ?? 0.0;
      final status = valPago >= v.valorTotal ? StatusContaPagar.pago : StatusContaPagar.pendente;
      return ContaPagar(
        id: 'venda_${v.id}',
        numero: v.numero,
        tipo: TipoContaPagar.despesaVariavel, // Fictício
        categoria: 'Recebível',
        descricao: 'Venda PDV - ${v.numero}',
        observacoes: v.observacoes,
        valor: v.valorTotal,
        valorPago: valPago,
        dataVencimento: _extractDueDate(v.observacoes) ?? v.dataVenda.add(const Duration(days: 30)),
        dataPagamento: valPago >= v.valorTotal ? v.updatedAt : null,
        dataCriacao: v.createdAt,
        updatedAt: v.updatedAt,
        createdAt: v.createdAt,
        status: status,
        fornecedorNome: v.clienteNome?.isNotEmpty == true ? v.clienteNome : 'Cliente não informado',
        ativo: true,
      );
    }).toList();
    
    // Obter pedidos (todos os não cancelados para aparecerem no extrato do cliente)
    final pedidosPrazo = dataService.pedidos.where((p) {
      if (p.status == 'Cancelado') return false;
      return true;
    }).map((p) {
      // IMPORTANTE: usar totalmenteRecebido (só pagamentos com recebido=true), NÃO
      // pagamentoCompleto. Venda FIADO lança o pagamento (recebido=false), então
      // pagamentoCompleto daria true e a conta apareceria como PAGO — mas deve
      // ficar EM ABERTO até o caixa confirmar o recebimento.
      final valPago = p.totalRecebido;
      final status = p.totalmenteRecebido ? StatusContaPagar.pago : StatusContaPagar.pendente;
      return ContaPagar(
        id: 'pedido_${p.id}',
        numero: p.numero,
        tipo: TipoContaPagar.despesaVariavel, // Fictício
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

    final contas = _filtrarContas(todasContas);
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
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Ver / Imprimir PDF'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _gerarEVisualizarPDF(contasLote, incluirItens);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
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

    for (final conta in contasLote) {
      if (saldo1 <= 0.001 && saldo2 <= 0.001) break; // Terminou o dinheiro

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
      
      if (aplicado1 <= 0.001 && aplicado2 <= 0.001) continue;

      if (conta.id.startsWith('venda_')) {
        final idReal = conta.id.replaceFirst('venda_', '');
        try {
            final vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
            final novoRecebido = (vendaOriginal.valorRecebido ?? 0.0) + aplicado1 + aplicado2;
            
            final vendaAtualizada = vendaOriginal.copyWith(
              tipoPagamento: (vendaOriginal.valorRecebido != null && vendaOriginal.valorRecebido! > 0) ? vendaOriginal.tipoPagamento : forma1,
              valorRecebido: novoRecebido,
              updatedAt: hoje,
            );
            await dataService.updateVendaBalcao(vendaAtualizada);
        } catch(e) {}
      } else {
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
        final novoValorPago = (conta.valorPago ?? 0.0) + aplicado1 + aplicado2;
        final novoStatus = novoValorPago >= (conta.valor - 0.001) ? StatusContaPagar.pago : StatusContaPagar.pendente;
        
        final contaAtualizada = ContaPagar(
          id: conta.id,
          numero: conta.numero,
          tipo: conta.tipo,
          categoria: conta.categoria,
          descricao: conta.descricao,
          observacoes: conta.observacoes,
          valor: conta.valor,
          valorPago: novoValorPago,
          dataVencimento: conta.dataVencimento,
          dataPagamento: novoStatus == StatusContaPagar.pago ? hoje : conta.dataPagamento,
          status: novoStatus,
          formaPagamento: forma1.nome,
          historicoPagamentos: novoHistorico,
          recorrente: conta.recorrente,
          intervaloRecorrencia: conta.intervaloRecorrencia,
          proximaDataRecorrencia: conta.proximaDataRecorrencia,
          ativo: conta.ativo,
          usuarioCriacao: conta.usuarioCriacao,
          usuarioPagamento: conta.usuarioPagamento,
          notaEntradaId: conta.notaEntradaId,
          notaEntradaNumero: conta.notaEntradaNumero,
          fornecedorId: conta.fornecedorId,
          fornecedorNome: conta.fornecedorNome,
          updatedAt: hoje,
        );
        await dataService.updateContaPagar(contaAtualizada);
      }
    }
    
    setState(() {
      _selecionadas.clear();
    });
    if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Baixa realizada com sucesso!'), backgroundColor: Colors.green)
        );
    }
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

    bool podeReceber = statusAtual != StatusContaPagar.pago && statusAtual != StatusContaPagar.cancelado;

    return GestureDetector(
      onTap: () {
        if (conta.id.startsWith('venda_')) {
          _mostrarDetalhesVendaPrazo(context, conta);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ContaReceberFormPage(contaPagar: conta),
            ),
          ).then((_) => setState(() {}));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: corCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: corBorda.withOpacity(0.5), width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Checkbox(
                  value: _selecionadas.contains(conta.id),
                  activeColor: Colors.green,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) _selecionadas.add(conta.id);
                      else _selecionadas.remove(conta.id);
                    });
                  },
                ),
              ),
            Expanded(
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              conta.descricao,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              conta.id.startsWith('venda_')
                                  ? 'Venda'
                                  : conta.id.startsWith('pedido_')
                                      ? 'Pedido'
                                      : 'Avulsa',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
                    conta.id.startsWith('venda_') || conta.id.startsWith('pedido_')
                        ? Icons.person_outline
                        : Icons.business,
                    size: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      conta.fornecedorNome!,
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
                      ? 'Receber R\$ ${formatoMoeda.format(conta.valorPendente)}'
                      : 'Receber (pode ser parcial)',
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
            ], // closes spread
          ], // closes Column children
        ), // closes Column
      ), // closes Expanded
    ], // closes Row children
  ), // closes Row
), // closes Container
); // closes GestureDetector
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
              Text('Registrar Recebimento'),
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
                    labelText: 'Valor a Receber (pode ser parcial)',
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

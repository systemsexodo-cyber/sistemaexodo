import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/mesa_comanda.dart';
import '../models/conta_pagar.dart';
import '../widgets/sync_status_widget.dart';

/// Página de histórico completo de operações (rastreamento)
class HistoricoOperacoesPage extends StatefulWidget {
  final MesaComanda? mesaComanda; // Se fornecido, mostra apenas desta mesa/comanda

  const HistoricoOperacoesPage({super.key, this.mesaComanda});

  @override
  State<HistoricoOperacoesPage> createState() => _HistoricoOperacoesPageState();
}

class _HistoricoOperacoesPageState extends State<HistoricoOperacoesPage> {
  String _filtroTipo = 'Todos'; // Todos, Mesas, Comandas
  String _filtroStatus = 'Todos'; // Todos, Abertas, Fechadas
  String _termoBusca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);
    final formatoData = DateFormat('dd/MM/yyyy HH:mm:ss');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // Filtrar mesas/comandas
    var mesasComandas = widget.mesaComanda != null
        ? [widget.mesaComanda!]
        : dataService.mesasComandas;

    if (_filtroTipo != 'Todos') {
      mesasComandas = mesasComandas.where((m) {
        if (_filtroTipo == 'Mesas') return m.tipo == TipoControle.mesa;
        if (_filtroTipo == 'Comandas') return m.tipo == TipoControle.comanda;
        return true;
      }).toList();
    }

    if (_filtroStatus != 'Todos') {
      mesasComandas = mesasComandas.where((m) {
        if (_filtroStatus == 'Abertas') return m.status == 'Aberta';
        if (_filtroStatus == 'Fechadas') return m.status == 'Fechada';
        return true;
      }).toList();
    }

    if (_termoBusca.isNotEmpty) {
      mesasComandas = mesasComandas.where((m) {
        final buscaLower = _termoBusca.toLowerCase();
        return m.numero.toLowerCase().contains(buscaLower) ||
            (m.clienteNome?.toLowerCase().contains(buscaLower) ?? false);
      }).toList();
    }

    // Ordenar por data de criação (mais recente primeiro)
    mesasComandas.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: Text(
          widget.mesaComanda != null
              ? 'Histórico - ${widget.mesaComanda!.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${widget.mesaComanda!.numero}'
              : 'Histórico de Operações',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          const SyncStatusWidget(),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          if (widget.mesaComanda == null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _buscaController,
                    onChanged: (value) {
                      setState(() {
                        _termoBusca = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar por número ou cliente...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.orange),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filtroTipo,
                          decoration: InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                          ),
                          dropdownColor: const Color(0xFF1E1E2E),
                          style: const TextStyle(color: Colors.white),
                          items: ['Todos', 'Mesas', 'Comandas']
                              .map((tipo) => DropdownMenuItem(
                                    value: tipo,
                                    child: Text(tipo),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _filtroTipo = value ?? 'Todos';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filtroStatus,
                          decoration: InputDecoration(
                            labelText: 'Status',
                            labelStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                          ),
                          dropdownColor: const Color(0xFF1E1E2E),
                          style: const TextStyle(color: Colors.white),
                          items: ['Todos', 'Abertas', 'Fechadas']
                              .map((status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _filtroStatus = value ?? 'Todos';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Lista de operações
          Expanded(
            child: mesasComandas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 80, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma operação encontrada',
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: mesasComandas.length,
                    itemBuilder: (context, index) {
                      final mesaComanda = mesasComandas[index];
                      return _buildCardOperacao(mesaComanda, formatoData, formatoMoeda);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardOperacao(
    MesaComanda mesaComanda,
    DateFormat formatoData,
    NumberFormat formatoMoeda,
  ) {
    // Buscar comandas vinculadas se for uma mesa
    final comandasVinculadas = mesaComanda.tipo == TipoControle.mesa
        ? Provider.of<DataService>(context, listen: false)
            .mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaComanda.id)
            .toList()
        : <MesaComanda>[];
    
    // Coletar todos os itens (mesa + comandas vinculadas)
    final todosItens = <Map<String, dynamic>>[];
    
    // Itens da mesa
    for (final item in mesaComanda.itens) {
      todosItens.add({
        'item': item,
        'origem': 'Mesa ${mesaComanda.numero}',
        'origemTipo': 'mesa',
      });
    }
    
    // Itens das comandas vinculadas
    for (final comanda in comandasVinculadas) {
      for (final item in comanda.itens) {
        todosItens.add({
          'item': item,
          'origem': 'Comanda ${comanda.numero}',
          'origemTipo': 'comanda',
        });
      }
    }
    
    // Ordenar por data/hora
    todosItens.sort((a, b) {
      final itemA = a['item'] as ItemMesaComanda;
      final itemB = b['item'] as ItemMesaComanda;
      return itemB.dataHora.compareTo(itemA.dataHora);
    });
    
    // Coletar todos os pagamentos (mesa + comandas vinculadas)
    final todosPagamentos = <Map<String, dynamic>>[];
    
    // Pagamentos da mesa
    for (final pagamento in mesaComanda.historicoPagamentos) {
      todosPagamentos.add({
        'pagamento': pagamento,
        'origem': 'Mesa ${mesaComanda.numero}',
        'origemTipo': 'mesa',
      });
    }
    
    // Pagamentos das comandas vinculadas
    for (final comanda in comandasVinculadas) {
      for (final pagamento in comanda.historicoPagamentos) {
        todosPagamentos.add({
          'pagamento': pagamento,
          'origem': 'Comanda ${comanda.numero}',
          'origemTipo': 'comanda',
          'comanda': comanda, // Passar a comanda completa para buscar itens
        });
      }
    }
    
    // Ordenar pagamentos por data (mais recente primeiro)
    todosPagamentos.sort((a, b) {
      final pagA = a['pagamento'] as RegistroPagamento;
      final pagB = b['pagamento'] as RegistroPagamento;
      return pagB.dataPagamento.compareTo(pagA.dataPagamento);
    });
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF1E1E2E),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(
              mesaComanda.tipo == TipoControle.mesa
                  ? Icons.table_restaurant
                  : Icons.receipt_long,
              color: mesaComanda.tipo == TipoControle.mesa
                  ? Colors.orange
                  : Colors.purple,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${mesaComanda.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${mesaComanda.numero}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (mesaComanda.clienteNome != null)
                    Text(
                      'Cliente: ${mesaComanda.clienteNome}',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatoMoeda.format(mesaComanda.totalCalculado),
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: mesaComanda.status == 'Aberta'
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: mesaComanda.status == 'Aberta'
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                  child: Text(
                    mesaComanda.status,
                    style: TextStyle(
                      color: mesaComanda.status == 'Aberta'
                          ? Colors.green
                          : Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mesaComanda.usuarioCriou != null)
                Text(
                  'Criado por: ${mesaComanda.usuarioCriou}',
                  style: TextStyle(color: Colors.blue, fontSize: 11),
                ),
              Text(
                'Aberta em: ${formatoData.format(mesaComanda.dataAbertura)}',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              if (mesaComanda.dataFechamento != null)
                Text(
                  'Fechada em: ${formatoData.format(mesaComanda.dataFechamento!)}',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Informações gerais
                const Divider(),
                const SizedBox(height: 8),
                _buildInfoRow('Total', formatoMoeda.format(mesaComanda.totalCalculado)),
                _buildInfoRow('Pago', formatoMoeda.format(mesaComanda.totalPago)),
                _buildInfoRow('Pendente', formatoMoeda.format(mesaComanda.totalPendente)),
                if (mesaComanda.usuarioModificou != null)
                  _buildInfoRow('Última modificação por', mesaComanda.usuarioModificou!),

                // Histórico de itens
                const SizedBox(height: 16),
                const Text(
                  'Histórico de Itens:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (todosItens.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nenhum item lançado',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...todosItens.map((itemData) {
                    final item = itemData['item'] as ItemMesaComanda;
                    final origem = itemData['origem'] as String;
                    return _buildItemHistorico(item, formatoData, formatoMoeda, origem: origem);
                  }),

                // Histórico de pagamentos
                if (todosPagamentos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Histórico de Pagamentos:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...todosPagamentos.map((pagamentoData) {
                    final pagamento = pagamentoData['pagamento'] as RegistroPagamento;
                    final origem = pagamentoData['origem'] as String;
                    final comandaOrigem = pagamentoData['comanda'] as MesaComanda?;
                    return _buildPagamentoHistorico(
                      pagamento, 
                      formatoData, 
                      formatoMoeda, 
                      origem: origem,
                      comandaOrigem: comandaOrigem,
                      mesaComanda: mesaComanda,
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItemHistorico(
    ItemMesaComanda item,
    DateFormat formatoData,
    NumberFormat formatoMoeda, {
    String? origem,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getStatusColor(item.status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${item.quantidade}x ${item.nome}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                formatoMoeda.format(item.preco * item.quantidade),
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getStatusColor(item.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _getStatusColor(item.status)),
                ),
                child: Text(
                  _getStatusNome(item.status),
                  style: TextStyle(
                    color: _getStatusColor(item.status),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (item.local != null) ...[
                const SizedBox(width: 8),
                Text(
                  item.local!,
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          if (origem != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.purple.withOpacity(0.5)),
              ),
              child: Text(
                origem,
                style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Lançado em: ${formatoData.format(item.dataHora)}',
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
          if (item.usuarioCriou != null)
            Text(
              'Por: ${item.usuarioCriou}',
              style: TextStyle(color: Colors.blue, fontSize: 10),
            ),
          if (item.usuarioModificou != null) ...[
            Text(
              'Modificado por: ${item.usuarioModificou}',
              style: TextStyle(color: Colors.orange, fontSize: 10),
            ),
            if (item.dataModificacao != null)
              Text(
                'Em: ${formatoData.format(item.dataModificacao!)}',
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
            if (item.acaoRealizada != null)
              Text(
                'Ação: ${item.acaoRealizada}',
                style: TextStyle(color: Colors.yellow, fontSize: 10),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagamentoHistorico(
    RegistroPagamento pagamento,
    DateFormat formatoData,
    NumberFormat formatoMoeda, {
    String? origem,
    MesaComanda? comandaOrigem,
    MesaComanda? mesaComanda,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Origem do pagamento
          if (origem != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.purple.withOpacity(0.5)),
              ),
              child: Text(
                origem,
                style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatoMoeda.format(pagamento.valor),
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                pagamento.formaPagamento ?? 'Não informado',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Data: ${formatoData.format(pagamento.dataPagamento)}',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
          if (pagamento.pessoaPagou != null && pagamento.pessoaPagou!.isNotEmpty)
            Text(
              'Pagou: ${pagamento.pessoaPagou}',
              style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          if (pagamento.observacao != null && pagamento.observacao!.isNotEmpty)
            Text(
              pagamento.observacao!,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          // Listar itens pagos com detalhes
          if (pagamento.itensPagos != null && pagamento.itensPagos!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Itens pagos (${pagamento.itensPagos!.length}):',
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...pagamento.itensPagos!.map((itemId) {
                    // Buscar item na comanda ou na mesa
                    ItemMesaComanda? item;
                    if (comandaOrigem != null) {
                      try {
                        item = comandaOrigem.itens.firstWhere((i) => i.id == itemId);
                      } catch (e) {
                        item = null;
                      }
                    } else if (mesaComanda != null) {
                      try {
                        item = mesaComanda.itens.firstWhere((i) => i.id == itemId);
                      } catch (e) {
                        item = null;
                      }
                    }
                    
                    if (item == null) return const SizedBox.shrink();
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${item.quantidade}x ${item.nome} - ${formatoMoeda.format(item.preco * item.quantidade)}',
                        style: TextStyle(color: Colors.white70, fontSize: 9),
                      ),
                    );
                  }).where((widget) => widget is! SizedBox),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return Colors.red;
      case StatusItem.emPreparo:
        return Colors.orange;
      case StatusItem.pronto:
        return Colors.green;
      case StatusItem.entregue:
        return Colors.blue;
      case StatusItem.cancelado:
        return Colors.grey;
    }
  }

  String _getStatusNome(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return 'Pendente';
      case StatusItem.emPreparo:
        return 'Em Preparo';
      case StatusItem.pronto:
        return 'Pronto';
      case StatusItem.entregue:
        return 'Entregue';
      case StatusItem.cancelado:
        return 'Cancelado';
    }
  }
}


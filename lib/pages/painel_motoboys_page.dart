import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/motorista.dart';
import '../models/delivery_info.dart';
import '../models/entrega.dart';
import '../services/pedido_pdf_service.dart';
import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../utils/rota_texto.dart';

class PainelMotoboysPage extends StatefulWidget {
  const PainelMotoboysPage({super.key});

  @override
  State<PainelMotoboysPage> createState() => _PainelMotoboysPageState();
}

class _PainelMotoboysPageState extends State<PainelMotoboysPage> {
  final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  
  // Set para guardar os IDs dos pedidos selecionados
  final Set<String> _selecionadosIds = {};
  
  // Toggle para mostrar pedidos já entregues
  bool _mostrarEntregues = false;

  // ── Filtros do painel ──────────────────────────────────────────────
  // Sentinela do dropdown de motoboy: "todos" (não filtra nada) e "sem
  // motoboy" (as entregas que ainda aguardam delegação). Os demais valores
  // são o id do motorista.
  static const String _filtroTodos = '__todos__';
  static const String _filtroSemMotoboy = '__sem_motoboy__';

  String _motoristaFiltro = _filtroTodos;
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _alternarSelecao(String id) {
    setState(() {
      if (_selecionadosIds.contains(id)) {
        _selecionadosIds.remove(id);
      } else {
        _selecionadosIds.add(id);
      }
    });
  }

  void _limparSelecao() {
    setState(() {
      _selecionadosIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    
    // Pegar pedidos pendentes/em rota que tenham DeliveryInfo ou que deveriam ter
    final pedidosEntrega = dataService.pedidos.where((p) {
      final s = p.status.toLowerCase();
      if (s == 'cancelado') return false;
      
      final dInfo = p.deliveryInfo;
      if (dInfo != null) {
        final st = dInfo.status.toLowerCase();
        if (st == 'cancelado') return false;
        if (st == 'entregue' && !_mostrarEntregues) return false;
        return true;
      }
      
      if (s == 'pendente' || s == 'em preparo') return true;
      return false;
    }).where((p) => _passaNoFiltro(p)).toList();

    // Agrupar por motoboy
    final entregasPorMotoboy = <String?, List<Pedido>>{};
    
    for (final pedido in pedidosEntrega) {
      final motoristaId = pedido.deliveryInfo?.motoristaId;
      if (!entregasPorMotoboy.containsKey(motoristaId)) {
        entregasPorMotoboy[motoristaId] = [];
      }
      entregasPorMotoboy[motoristaId]!.add(pedido);
    }

    // Comissão: só a entrega ENTREGUE gera valor a pagar (mesma regra da tela
    // de Comissões). O que ainda está em rota aparece como previsão.
    var totalComissao = 0.0;
    var totalEntregues = 0;
    for (final pedido in pedidosEntrega) {
      if (_pedidoEntregue(pedido)) {
        totalEntregues++;
        totalComissao += _comissaoDoPedido(pedido, dataService);
      }
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Painel de Motoboys'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Row(
              children: [
                const Text('Ver Entregues', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _mostrarEntregues,
                  onChanged: (val) => setState(() => _mostrarEntregues = val),
                  activeColor: Colors.orangeAccent,
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // Filtros por motoboy e por entrega
            _buildBarraFiltros(dataService),
            // Total de comissões — só faz sentido no modo "Ver Entregues"
            if (_mostrarEntregues)
              _buildResumoComissoes(totalComissao, totalEntregues),
            // Barra flutuante se houver itens selecionados
            if (_selecionadosIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.orangeAccent.withOpacity(0.2),
                child: Row(
                  children: [
                    Text(
                      '${_selecionadosIds.length} selecionado(s)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _limparSelecao,
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Limpar'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        final selecionados = dataService.pedidos
                            .where((p) => _selecionadosIds.contains(p.id))
                            .toList();
                        _mostrarDialogTransferenciaEmMassa(context, selecionados, dataService);
                      },
                      icon: const Icon(Icons.two_wheeler),
                      label: const Text('DELEGAR'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                    ),
                  ],
                ),
              ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (pedidosEntrega.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          'Nenhuma entrega encontrada com os filtros atuais.',
                          style: TextStyle(color: Colors.white.withOpacity(0.6)),
                        ),
                      ),
                    ),
                  // 1. Aguardando Motoboy
                  if (entregasPorMotoboy.containsKey(null) || entregasPorMotoboy.containsKey(''))
                    _buildSessaoMotoboy(
                      context: context,
                      dataService: dataService,
                      motorista: null,
                      pedidos: entregasPorMotoboy[null] ?? [],
                    ),
                  
                  // 2. Por Motoboy
                  ...dataService.motoristas.map((motorista) {
                    final pedidosDeste = entregasPorMotoboy[motorista.id] ?? [];
                    if (pedidosDeste.isEmpty) return const SizedBox.shrink();
                    
                    return _buildSessaoMotoboy(
                      context: context,
                      dataService: dataService,
                      motorista: motorista,
                      pedidos: pedidosDeste,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessaoMotoboy({
    required BuildContext context,
    required DataService dataService,
    required Motorista? motorista,
    required List<Pedido> pedidos,
  }) {
    if (pedidos.isEmpty) return const SizedBox.shrink();

    final nome = motorista?.nome ?? 'Aguardando Motoboy';
    final cor = motorista == null ? Colors.redAccent : Colors.blueAccent;
    final icone = motorista == null ? Icons.hourglass_empty : Icons.two_wheeler;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, color: cor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                nome,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (motorista != null)
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white70),
                tooltip: 'Copiar rota (para enviar no WhatsApp do motoboy)',
                onPressed: () => _copiarRota(context, motorista, pedidos),
              ),
            if (motorista != null)
              IconButton(
                icon: const Icon(Icons.print, color: Colors.white70),
                tooltip: 'Imprimir todas as entregas',
                onPressed: () {
                  if (dataService.empresaAtual != null) {
                    PedidoPDFService.imprimirLotePedidosTermico(
                      pedidos: pedidos,
                      empresa: dataService.empresaAtual!,
                      context: context,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erro: Empresa não identificada para impressão.')),
                    );
                  }
                },
              ),
          ],
        ),
        subtitle: _buildSubtituloSessao(dataService, pedidos),
        children: pedidos.map((p) => _buildCardPedido(context, p, motorista, dataService)).toList(),
      ),
    );
  }

  /// Monta o texto da rota deste motoboy e copia para a área de transferência,
  /// para o operador colar no WhatsApp dele.
  Future<void> _copiarRota(
    BuildContext context,
    Motorista motorista,
    List<Pedido> pedidos,
  ) async {
    if (pedidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma entrega para copiar.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final itens = pedidos.map((p) {
      final entregue = p.deliveryInfo?.status.toLowerCase() == 'entregue';
      final endereco = (p.deliveryInfo != null &&
              p.deliveryInfo!.enderecoCompleto.trim().isNotEmpty)
          ? p.deliveryInfo!.enderecoCompleto
          : p.clienteEndereco;
      return RotaItemTexto(
        numero: p.numero,
        cliente: p.clienteNome,
        telefone: p.clienteTelefone,
        endereco: endereco,
        valor: p.totalGeral,
        pago: p.totalmenteRecebido,
        entregue: entregue,
        observacao: p.observacoes,
      );
    }).toList();

    final texto = RotaTexto.montar(
      titulo: 'ROTA DO MOTOBOY',
      motorista: motorista.nome,
      data: DateTime.now(),
      itens: itens,
    );

    await RotaTexto.copiar(texto);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rota copiada! Agora é só colar no WhatsApp do motoboy.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildCardPedido(BuildContext context, Pedido pedido, Motorista? motoristaAtual, DataService dataService) {
    final isSelecionado = _selecionadosIds.contains(pedido.id);
    final isEntregue = pedido.deliveryInfo?.status.toLowerCase() == 'entregue';
    // Comissão deste motoboy para ESTA entrega (null quando ainda não há
    // motoboy definido).
    final comissao = motoristaAtual == null
        ? null
        : _comissaoDoPedido(pedido, dataService);
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelecionado ? Colors.orangeAccent.withOpacity(0.1) : const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelecionado ? Colors.orangeAccent : Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: isSelecionado,
            onChanged: (val) => _alternarSelecao(pedido.id),
            activeColor: Colors.orangeAccent,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt, color: Colors.white38, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      pedido.numero, 
                      style: TextStyle(
                        color: Colors.white, 
                        fontWeight: FontWeight.bold,
                        decoration: isEntregue ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (isEntregue)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('ENTREGUE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatoMoeda.format(pedido.totalGeral),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)
                        ),
                        if (comissao != null)
                          Text(
                            '${isEntregue ? 'Comissão' : 'Prevista'}: ${formatoMoeda.format(comissao)}',
                            style: TextStyle(
                              color: isEntregue ? Colors.greenAccent : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${pedido.clienteNome ?? "Sem nome"} ${pedido.clienteTelefone != null ? "- ${pedido.clienteTelefone}" : ""}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        pedido.clienteEndereco ?? 'Endereço não informado',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              if (!isEntregue)
                OutlinedButton.icon(
                  onPressed: () => _mostrarDialogTransferencia(context, pedido, dataService),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Transferir', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    side: const BorderSide(color: Colors.orangeAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              if (motoristaAtual != null && !isEntregue) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _marcarComoEntregue(pedido, dataService),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Entregue', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
              // Já entregue: permite DESFAZER. Volta a entrega para "Saiu para
              // entrega" e ela sai da conta da comissão do motoboy.
              if (isEntregue)
                TextButton.icon(
                  onPressed: () => _desmarcarComoEntregue(pedido, dataService),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Não entregue', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _mostrarDialogTransferenciaEmMassa(BuildContext context, List<Pedido> pedidos, DataService dataService) {
    if (dataService.motoristas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum entregador cadastrado.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    Motorista? motoristaSelecionado;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Delegar ${pedidos.length} Pedido(s)', style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Escolha o motoboy para as entregas:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Motorista>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A3E),
                      value: motoristaSelecionado,
                      hint: const Text('Escolha o motoboy...', style: TextStyle(color: Colors.white54)),
                      items: dataService.motoristas.map((m) {
                        return DropdownMenuItem<Motorista>(
                          value: m,
                          child: Text(m.nome, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          motoristaSelecionado = val;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: motoristaSelecionado == null ? null : () {
                  Navigator.pop(ctx);
                  for (final p in pedidos) {
                    _transferirPara(p, motoristaSelecionado!, dataService, mostrarSnackBar: false);
                  }
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('${pedidos.length} pedido(s) delegado(s) para ${motoristaSelecionado!.nome}!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _limparSelecao();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                child: const Text('CONFIRMAR', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarDialogTransferencia(BuildContext context, Pedido pedido, DataService dataService) {
    if (dataService.motoristas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum entregador cadastrado.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    Motorista? motoristaSelecionado;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Transferir Entrega', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido: ${pedido.numero}', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Motorista>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A3E),
                      value: motoristaSelecionado,
                      hint: const Text('Escolha o novo motoboy...', style: TextStyle(color: Colors.white54)),
                      items: dataService.motoristas.map((m) {
                        return DropdownMenuItem<Motorista>(
                          value: m,
                          child: Text(m.nome, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          motoristaSelecionado = val;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: motoristaSelecionado == null ? null : () {
                  Navigator.pop(ctx);
                  _transferirPara(pedido, motoristaSelecionado!, dataService);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                child: const Text('CONFIRMAR', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _transferirPara(Pedido pedido, Motorista motorista, DataService dataService, {bool mostrarSnackBar = true}) {
    DeliveryInfo novoDeliveryInfo;
    
    if (pedido.deliveryInfo != null) {
      novoDeliveryInfo = pedido.deliveryInfo!.copyWith(
        motoristaId: motorista.id,
        motoristaNome: motorista.nome,
        status: 'Saiu para entrega',
        dataSaida: DateTime.now(),
      );
    } else {
      novoDeliveryInfo = DeliveryInfo(
        id: DateTime.now().millisecondsSinceEpoch.toString() + pedido.id,
        enderecoId: '',
        logradouro: 'Não informado',
        numero: '',
        bairro: '',
        cidade: '',
        uf: '',
        status: 'Saiu para entrega',
        motoristaId: motorista.id,
        motoristaNome: motorista.nome,
        dataSaida: DateTime.now(),
      );
    }

    final pedidoAtualizado = pedido.copyWith(
      deliveryInfo: novoDeliveryInfo,
      updatedAt: DateTime.now(),
    );
    
    dataService.updatePedido(pedidoAtualizado);

    // A ENTREGA (tabela `entregas`) é quem alimenta a comissão do motoboy na
    // tela de Comissões. Delegar aqui só mexia no PEDIDO: a entrega continuava
    // sem motorista (ou nem existia) e a taxa cadastrada nunca contava.
    unawaited(
      _sincronizarEntregaDoPedido(
        pedido: pedido,
        deliveryInfo: novoDeliveryInfo,
        dataService: dataService,
      ),
    );

    if (mostrarSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido ${pedido.numero} transferido para ${motorista.nome}!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Cria/atualiza a ENTREGA correspondente ao pedido.
  ///
  /// É a `entregas` que a tela de Comissões lê para pagar o motoboy (status
  /// 'Entregue' + motorista). Antes, delegar e marcar como entregue pelo painel
  /// só alterava o pedido — a comissão da taxa cadastrada não contabilizava.
  Future<void> _sincronizarEntregaDoPedido({
    required Pedido pedido,
    required DeliveryInfo deliveryInfo,
    required DataService dataService,
    bool entregue = false,
    bool desmarcar = false,
    DateTime? quando,
  }) async {
    final agora = quando ?? DateTime.now();
    final novoStatus =
        entregue ? StatusEntrega.entregue : StatusEntrega.emEntrega;

    final index = dataService.entregas.indexWhere(
      (e) => e.pedidoId.isNotEmpty && e.pedidoId == pedido.id,
    );

    if (index >= 0) {
      final existente = dataService.entregas[index];
      await dataService.updateEntrega(
        existente.copyWith(
          pedidoNumero: pedido.numero,
          clienteNome: pedido.clienteNome ?? existente.clienteNome,
          clienteTelefone: pedido.clienteTelefone ?? existente.clienteTelefone,
          motoristaId: deliveryInfo.motoristaId,
          motoristaNome: deliveryInfo.motoristaNome,
          taxaEntrega: deliveryInfo.taxaEntrega ?? existente.taxaEntrega,
          status: novoStatus,
          dataEntrega: entregue ? agora : existente.dataEntrega,
          limparDataEntrega: desmarcar,
        ),
      );
      return;
    }

    // Sem entrega registrada ainda: cria uma com o estado atual da delegação.
    final dInfo = deliveryInfo;
    await dataService.addEntrega(
      Entrega(
        id: const Uuid().v4(),
        pedidoId: pedido.id,
        pedidoNumero: pedido.numero,
        clienteNome: pedido.clienteNome ?? 'Cliente',
        clienteTelefone: pedido.clienteTelefone,
        enderecoEntrega:
            '${dInfo.logradouro}, ${dInfo.numero}'.trim(),
        bairro: dInfo.bairro,
        cidade: dInfo.cidade,
        cep: dInfo.cep,
        status: novoStatus,
        dataCriacao: agora,
        dataEntrega: entregue ? agora : null,
        motoristaId: dInfo.motoristaId,
        motoristaNome: dInfo.motoristaNome,
        taxaEntrega: dInfo.taxaEntrega,
        observacoes: pedido.observacoes,
      ),
    );
  }

  Future<void> _marcarComoEntregue(
    Pedido pedido,
    DataService dataService,
  ) async {
    final dInfo = pedido.deliveryInfo;
    if (dInfo == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final agora = DateTime.now();
    final novoDeliveryInfo = dInfo.copyWith(
      status: 'Entregue',
      dataEntrega: agora,
    );

    final pedidoAtualizado = pedido.copyWith(
      deliveryInfo: novoDeliveryInfo,
      // O status do PEDIDO acompanha o da entrega: é ele que as outras telas e
      // relatórios leem. Antes só o deliveryInfo mudava, então a entrega podia
      // aparecer como entregue aqui e continuar "em rota" no resto do sistema.
      status: pedido.status.toLowerCase() == 'cancelado'
          ? pedido.status
          : 'Entregue',
      updatedAt: agora,
    );

    // Aguardado de propósito: o pedido e a ENTREGA precisam estar gravados (no
    // banco local) antes de o usuário sair da tela — é ela que entra no cálculo
    // da comissão do motoboy. Antes só o pedido ficava "Entregue" e a entrega
    // continuava "Aguardando", então a taxa cadastrada não contabilizava.
    await dataService.updatePedido(pedidoAtualizado);
    await _sincronizarEntregaDoPedido(
      pedido: pedido,
      deliveryInfo: novoDeliveryInfo,
      dataService: dataService,
      entregue: true,
      quando: agora,
    );
    // Fecha a janela do debounce: sem este flush a alteração ficava só na
    // memória e o estado antigo voltava ao reabrir a tela.
    await dataService.persistirAlteracoesPendentes();

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Pedido ${pedido.numero} marcado como entregue!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Desfaz o "Entregue": volta o pedido para "Saiu para entrega" e reabre a
  /// ENTREGA correspondente (status Em Entrega).
  ///
  /// É essa reabertura que tira a entrega da comissão: a tela de Comissões só
  /// conta entrega com status 'Entregue'.
  Future<void> _desmarcarComoEntregue(
    Pedido pedido,
    DataService dataService,
  ) async {
    final dInfo = pedido.deliveryInfo;
    if (dInfo == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final agora = DateTime.now();
    final novoDeliveryInfo = dInfo.copyWith(
      status: 'Saiu para entrega',
      limparDataEntrega: true,
    );

    await dataService.updatePedido(
      pedido.copyWith(
        deliveryInfo: novoDeliveryInfo,
        // Desfaz também o status geral do pedido: se ele tinha sido marcado
        // como "Entregue", volta para "Saiu para entrega" (senão o pedido
        // continuava contando como concluído nos relatórios).
        status: pedido.status.toLowerCase() == 'entregue'
            ? 'Saiu para entrega'
            : pedido.status,
        updatedAt: agora,
      ),
    );

    await _sincronizarEntregaDoPedido(
      pedido: pedido,
      deliveryInfo: novoDeliveryInfo,
      dataService: dataService,
      desmarcar: true,
    );
    await dataService.persistirAlteracoesPendentes();

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Pedido ${pedido.numero} voltou para "Saiu para entrega" e saiu da comissão.',
        ),
        backgroundColor: Colors.orangeAccent,
      ),
    );
  }

  // ── Comissão do motoboy (mesma regra da tela de Comissões) ────────────

  bool _pedidoEntregue(Pedido pedido) =>
      pedido.deliveryInfo?.status.toLowerCase() == 'entregue';

  Motorista? _motoristaDoPedido(Pedido pedido, DataService dataService) {
    final id = pedido.deliveryInfo?.motoristaId;
    if (id == null || id.isEmpty) return null;
    for (final m in dataService.motoristas) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Taxa da entrega usada no cálculo: a da ENTREGA quando ela já existe (é a
  /// fonte que a tela de Comissões lê); senão, a taxa do próprio pedido.
  double _taxaDaEntrega(Pedido pedido, DataService dataService) {
    for (final entrega in dataService.entregas) {
      if (entrega.pedidoId.isNotEmpty && entrega.pedidoId == pedido.id) {
        return entrega.taxaEntrega ?? pedido.deliveryInfo?.taxaEntrega ?? 0.0;
      }
    }
    return pedido.deliveryInfo?.taxaEntrega ?? 0.0;
  }

  double _comissaoDoPedido(Pedido pedido, DataService dataService) {
    return comissaoPorEntregaDoMotoboy(
      motorista: _motoristaDoPedido(pedido, dataService),
      taxaEntrega: _taxaDaEntrega(pedido, dataService),
    );
  }

  /// Subtítulo do grupo: quantidade de entregas + comissão do motoboy.
  Widget _buildSubtituloSessao(DataService dataService, List<Pedido> pedidos) {
    var comissaoEntregue = 0.0;
    var entregues = 0;
    var previsao = 0.0;
    for (final pedido in pedidos) {
      final comissao = _comissaoDoPedido(pedido, dataService);
      previsao += comissao;
      if (_pedidoEntregue(pedido)) {
        entregues++;
        comissaoEntregue += comissao;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${pedidos.length} entrega(s)',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        if (previsao > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Comissão: ${formatoMoeda.format(comissaoEntregue)}'
              '${previsao > comissaoEntregue ? ' • previsto ${formatoMoeda.format(previsao)}' : ''}'
              '${entregues > 0 ? ' ($entregues entregue(s))' : ''}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ── Filtros ───────────────────────────────────────────────────────────

  /// Motoboy escolhido + busca textual (nº do pedido, cliente, endereço...).
  bool _passaNoFiltro(Pedido pedido) {
    final motoristaId = pedido.deliveryInfo?.motoristaId ?? '';

    if (_motoristaFiltro == _filtroSemMotoboy) {
      if (motoristaId.isNotEmpty) return false;
    } else if (_motoristaFiltro != _filtroTodos &&
        motoristaId != _motoristaFiltro) {
      return false;
    }

    if (_busca.isEmpty) return true;
    final termo = _busca.toLowerCase();
    final campos = <String?>[
      pedido.numero,
      pedido.clienteNome,
      pedido.clienteTelefone,
      pedido.clienteEndereco,
      pedido.deliveryInfo?.enderecoCompleto,
      pedido.deliveryInfo?.bairro,
      pedido.deliveryInfo?.motoristaNome,
      pedido.observacoes,
    ];
    return campos.any((c) => c != null && c.toLowerCase().contains(termo));
  }

  Widget _buildBarraFiltros(DataService dataService) {
    // Se o motoboy filtrado saiu do cadastro, o dropdown voltaria a um valor
    // inexistente e quebraria; cai para "Todos".
    final ids = dataService.motoristas.map((m) => m.id).toSet();
    final valorAtual = (_motoristaFiltro == _filtroTodos ||
            _motoristaFiltro == _filtroSemMotoboy ||
            ids.contains(_motoristaFiltro))
        ? _motoristaFiltro
        : _filtroTodos;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withOpacity(0.85),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2A3E),
                value: valorAtual,
                icon: const Icon(Icons.two_wheeler,
                    color: Colors.white54, size: 18),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: _filtroTodos,
                    child: Text('Todos os motoboys',
                        style: TextStyle(color: Colors.white)),
                  ),
                  const DropdownMenuItem<String>(
                    value: _filtroSemMotoboy,
                    child: Text('Aguardando motoboy',
                        style: TextStyle(color: Colors.white)),
                  ),
                  ...dataService.motoristas.map(
                    (m) => DropdownMenuItem<String>(
                      value: m.id,
                      child: Text(m.nome,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
                onChanged: (valor) => setState(
                  () => _motoristaFiltro = valor ?? _filtroTodos,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _buscaController,
            onChanged: (valor) => setState(() => _busca = valor.trim()),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filtrar entrega (nº do pedido, cliente, endereço...)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white38, size: 18),
              suffixIcon: _busca.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear,
                          size: 16, color: Colors.white54),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _busca = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.orangeAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoComissoes(double total, int entregues) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.greenAccent.withOpacity(0.12),
      child: Row(
        children: [
          const Icon(Icons.attach_money, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Comissões (entregues)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            '$entregues entrega(s) • ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          Text(
            formatoMoeda.format(total),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Comissão do motoboy por UMA entrega — mesma conta da tela de Comissões
/// ([Motorista.comissaoPorEntregas]): valor fixo por entrega, % sobre a taxa,
/// ou R$ 0 quando o combinado é só diária.
///
/// Pura de propósito (não toca em widget) para poder ser verificada sem abrir
/// tela.
double comissaoPorEntregaDoMotoboy({
  required Motorista? motorista,
  required double taxaEntrega,
}) {
  if (motorista == null) return 0.0;
  return motorista.comissaoPorEntregas(
    entregas: 1,
    somaTaxasEntregas: taxaEntrega,
  );
}

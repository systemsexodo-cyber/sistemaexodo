import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/motorista.dart';
import '../models/delivery_info.dart';
import '../services/pedido_pdf_service.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

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
    }).toList();

    // Agrupar por motoboy
    final entregasPorMotoboy = <String?, List<Pedido>>{};
    
    for (final pedido in pedidosEntrega) {
      final motoristaId = pedido.deliveryInfo?.motoristaId;
      if (!entregasPorMotoboy.containsKey(motoristaId)) {
        entregasPorMotoboy[motoristaId] = [];
      }
      entregasPorMotoboy[motoristaId]!.add(pedido);
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
        subtitle: Text(
          '${pedidos.length} entrega(s)',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        children: pedidos.map((p) => _buildCardPedido(context, p, motorista, dataService)).toList(),
      ),
    );
  }

  Widget _buildCardPedido(BuildContext context, Pedido pedido, Motorista? motoristaAtual, DataService dataService) {
    final isSelecionado = _selecionadosIds.contains(pedido.id);
    final isEntregue = pedido.deliveryInfo?.status.toLowerCase() == 'entregue';
    
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
                    Text(
                      formatoMoeda.format(pedido.totalGeral), 
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)
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

    if (mostrarSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido ${pedido.numero} transferido para ${motorista.nome}!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  void _marcarComoEntregue(Pedido pedido, DataService dataService) {
    if (pedido.deliveryInfo != null) {
      final novoDeliveryInfo = pedido.deliveryInfo!.copyWith(
        status: 'Entregue',
        dataEntrega: DateTime.now(),
      );
      
      final pedidoAtualizado = pedido.copyWith(
        deliveryInfo: novoDeliveryInfo,
        updatedAt: DateTime.now(),
      );
      
      dataService.updatePedido(pedidoAtualizado);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido ${pedido.numero} marcado como entregue!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

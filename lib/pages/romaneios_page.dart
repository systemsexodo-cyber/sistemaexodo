import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/services/pedido_pdf_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/entrega.dart';
import '../services/whatsapp_service.dart';
import 'criar_romaneio_page.dart';

class RomaneiosPage extends StatefulWidget {
  final String? romaneioIdToOpen;

  const RomaneiosPage({super.key, this.romaneioIdToOpen});

  @override
  State<RomaneiosPage> createState() => _RomaneiosPageState();
}

class _RomaneiosPageState extends State<RomaneiosPage> {
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    
    var romaneios = dataService.romaneios.reversed.toList();

    // Filtro por data
    if (_dataInicioFiltro != null) {
      romaneios = romaneios.where((r) => !r.dataCriacao.isBefore(_dataInicioFiltro!)).toList();
    }
    if (_dataFimFiltro != null) {
      final dataFim = _dataFimFiltro!.add(const Duration(days: 1));
      romaneios = romaneios.where((r) => !r.dataCriacao.isAfter(dataFim)).toList();
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Romaneios de Entrega'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildFiltroData(),
            if (_dataInicioFiltro != null || _dataFimFiltro != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${romaneios.length} romaneios encontrados',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _dataInicioFiltro = null;
                          _dataFimFiltro = null;
                        });
                      },
                      child: const Text('Limpar', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: romaneios.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: romaneios.length,
                      itemBuilder: (context, index) {
                        return _buildCardRomaneio(romaneios[index], dataService);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _mostrarSelecaoMultiplaPedidos(context, dataService),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.add_box),
          label: const Text('NOVO ROMANEIO'),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 80, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Nenhum romaneio gerado ainda.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Clique no botão "NOVO ROMANEIO" abaixo.',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCardRomaneio(Romaneio romaneio, DataService dataService) {
    final corStatus = _getCorStatus(romaneio.status);
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ExpansionTile(
        initiallyExpanded: romaneio.id == widget.romaneioIdToOpen || romaneio.numero == widget.romaneioIdToOpen,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: corStatus.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.delivery_dining, color: corStatus),
        ),
        title: Text(
          romaneio.numero,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Motorista: ${romaneio.motoristaNome ?? 'Não informado'}',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            Text(
              formatoData.format(romaneio.dataCriacao),
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatoMoeda.format(romaneio.valorTotal),
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: corStatus.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                romaneio.status.name.toUpperCase(),
                style: TextStyle(color: corStatus, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: Colors.white12),
                const SizedBox(height: 10),
                const Text('Pedidos incluídos:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...romaneio.entregaIds.map((id) {
                  final pedido = dataService.pedidos.where((p) => p.id == id).firstOrNull;
                  if (pedido == null) return const SizedBox();
                  
                  final bool isEntregue = romaneio.pedidosEntregues.contains(id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isEntregue ? Colors.green.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isEntregue ? Colors.green.withOpacity(0.3) : Colors.transparent,
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: isEntregue,
                            activeColor: Colors.green,
                            onChanged: (val) {
                              _alternarStatusEntrega(romaneio, id, val ?? false, dataService);
                            },
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
                                    const Spacer(),
                                    Text(
                                      formatoMoeda.format(pedido.totalGeral), 
                                      style: TextStyle(
                                        color: isEntregue ? Colors.green : Colors.white60, 
                                        fontSize: 12,
                                        fontWeight: isEntregue ? FontWeight.bold : FontWeight.normal,
                                      )
                                    ),
                                  ],
                                ),
                                if (pedido.clienteNome != null || pedido.clienteTelefone != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 22, top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person, size: 12, color: Colors.white54),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${pedido.clienteNome ?? "Sem nome"} ${pedido.clienteTelefone != null ? "- ${pedido.clienteTelefone}" : ""}',
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (pedido.clienteEndereco != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 22, top: 2),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on, size: 12, color: Colors.orangeAccent),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            pedido.clienteEndereco!,
                                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (romaneio.observacoes != null && romaneio.observacoes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Observações:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  Text(romaneio.observacoes!, style: const TextStyle(color: Colors.white38)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            if (dataService.empresaAtual == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma empresa selecionada.')));
                              return;
                            }
                            final pedidosDoRomaneio = romaneio.entregaIds
                                .map((id) => dataService.pedidos.where((p) => p.id == id).firstOrNull)
                                .whereType<Pedido>()
                                .toList();
                            
                            await PedidoPDFService.imprimirDocumentoRomaneio(
                              romaneio: romaneio,
                              pedidos: pedidosDoRomaneio,
                              empresa: dataService.empresaAtual!,
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao imprimir: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('IMPRIMIR'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _abrirRotaMaps(romaneio, dataService),
                        icon: const Icon(Icons.map),
                        label: const Text('MAPA'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      ),
                    ),
                  ],
                ),
                if (romaneio.status == StatusRomaneio.emPreparacao) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _iniciarEntregaRomaneio(romaneio, dataService),
                      icon: const Icon(Icons.local_shipping),
                      label: const Text('INICIAR ROTA DE ENTREGA'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCorStatus(StatusRomaneio status) {
    switch (status) {
      case StatusRomaneio.emPreparacao:
        return Colors.orange;
      case StatusRomaneio.emEntrega:
        return Colors.blue;
      case StatusRomaneio.concluido:
        return Colors.green;
      case StatusRomaneio.cancelado:
        return Colors.red;
    }
  }

  Widget _buildFiltroData() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 16, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _buildBotaoData(
                  label: _dataInicioFiltro != null
                      ? DateFormat('dd/MM/yyyy').format(_dataInicioFiltro!)
                      : 'Início',
                  onTap: () => _selecionarData(true),
                  isSet: _dataInicioFiltro != null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('até', style: TextStyle(color: Colors.white24, fontSize: 12)),
                ),
                _buildBotaoData(
                  label: _dataFimFiltro != null
                      ? DateFormat('dd/MM/yyyy').format(_dataFimFiltro!)
                      : 'Fim',
                  onTap: () => _selecionarData(false),
                  isSet: _dataFimFiltro != null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoData({required String label, required VoidCallback onTap, bool isSet = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isSet ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSet ? Colors.green.withOpacity(0.3) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSet ? Colors.greenAccent : Colors.white54,
              fontSize: 12,
              fontWeight: isSet ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _selecionarData(bool isInicio) async {
    final data = await showDatePicker(
      context: context,
      initialDate: (isInicio ? _dataInicioFiltro : _dataFimFiltro) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.green,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (data != null) {
      setState(() {
        if (isInicio) {
          _dataInicioFiltro = DateTime(data.year, data.month, data.day);
        } else {
          _dataFimFiltro = DateTime(data.year, data.month, data.day, 23, 59, 59);
        }
      });
    }
  }


  void _alternarStatusEntrega(Romaneio romaneio, String pedidoId, bool isEntregue, DataService dataService) {
    final novosEntregues = List<String>.from(romaneio.pedidosEntregues);
    if (isEntregue) {
      if (!novosEntregues.contains(pedidoId)) {
        novosEntregues.add(pedidoId);
      }
    } else {
      novosEntregues.remove(pedidoId);
    }

    // Verificar se todos os pedidos foram entregues
    final todosEntregues = novosEntregues.length == romaneio.entregaIds.length;
    
    // Atualizar status do romaneio
    StatusRomaneio novoStatus = romaneio.status;
    if (todosEntregues) {
      novoStatus = StatusRomaneio.concluido;
    } else if (novosEntregues.isNotEmpty && romaneio.status == StatusRomaneio.emPreparacao) {
      novoStatus = StatusRomaneio.emEntrega;
    } else if (novosEntregues.isEmpty && romaneio.status == StatusRomaneio.concluido) {
      novoStatus = StatusRomaneio.emEntrega;
    }

    final romaneioAtualizado = romaneio.copyWith(
      pedidosEntregues: novosEntregues,
      status: novoStatus,
    );

    dataService.updateRomaneio(romaneioAtualizado);

    // SINCRONIZAÇÃO: Atualizar o status da Entrega correspondente
    final entregaIndex = dataService.entregas.indexWhere((e) => e.pedidoId == pedidoId);
    if (entregaIndex != -1) {
      final entrega = dataService.entregas[entregaIndex];
      final statusFinal = isEntregue ? StatusEntrega.entregue : StatusEntrega.romaneioCriado;
      
      // Só atualizar se for uma mudança real
      if (entrega.status != statusFinal) {
        final evento = EventoEntrega(
          id: Uuid().v4(),
          dataHora: DateTime.now(),
          status: statusFinal,
          descricao: isEntregue ? 'Entregue via Romaneio ${romaneio.numero}' : 'Retornado para Romaneio ${romaneio.numero}',
        );
        dataService.updateEntrega(entrega.adicionarEvento(evento).copyWith(
          dataEntrega: isEntregue ? DateTime.now() : null,
        ));
      }
    }
    
    if (todosEntregues && romaneio.status != StatusRomaneio.concluido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Romaneio concluído! Todas as entregas foram realizadas.'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _abrirRotaMaps(Romaneio romaneio, DataService dataService) async {
    final enderecos = <String>[];
    
    for (final id in romaneio.entregaIds) {
      final pedido = dataService.pedidos.where((p) => p.id == id).firstOrNull;
      if (pedido != null && pedido.clienteEndereco != null && pedido.clienteEndereco!.isNotEmpty) {
        enderecos.add(pedido.clienteEndereco!);
      }
    }
    
    if (enderecos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum endereço encontrado nos pedidos deste romaneio'), backgroundColor: Colors.red),
      );
      return;
    }
    
    // Constrói URL do Maps com os waypoints (deixamos a origem vazia para o Maps usar a localização atual do celular do entregador)
    final path = enderecos.map((e) => Uri.encodeComponent(e)).join('/');
    final url = Uri.parse('https://www.google.com/maps/dir//$path');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o Google Maps'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _iniciarEntregaRomaneio(Romaneio romaneio, DataService dataService) {
    // 1. Atualizar o romaneio para "emEntrega"
    final romaneioAtualizado = romaneio.copyWith(
      status: StatusRomaneio.emEntrega,
      dataSaida: DateTime.now(),
    );
    dataService.updateRomaneio(romaneioAtualizado);

    // 2. Atualizar todas as entregas vinculadas para "emEntrega"
    for (final id in romaneio.entregaIds) {
      final entregaIndex = dataService.entregas.indexWhere((e) => e.pedidoId == id);
      if (entregaIndex != -1) {
        final entrega = dataService.entregas[entregaIndex];
        // Só atualizar se estiver em aguardando ou romaneioCriado
        if (entrega.status == StatusEntrega.aguardando || entrega.status == StatusEntrega.romaneioCriado) {
          final evento = EventoEntrega(
            id: Uuid().v4(),
            dataHora: DateTime.now(),
            status: StatusEntrega.emEntrega,
            descricao: 'Saiu para entrega no Romaneio ${romaneio.numero}',
          );
          dataService.updateEntrega(entrega.adicionarEvento(evento));
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Romaneio ${romaneio.numero} iniciado! As entregas agora estão "Em Rota".'),
        backgroundColor: Colors.deepPurple,
      ),
    );

    // 3. Notificar via WhatsApp se configurado
    if (dataService.empresaAtual?.whatsappApiKey != null) {
      _notificarClientesSaida(romaneio, dataService);
    }
  }

  Future<void> _notificarClientesSaida(Romaneio romaneio, DataService dataService) async {
    try {
      final whatsapp = WhatsAppService.fromEmpresa(dataService.empresaAtual!);
      int sucessos = 0;

      for (final id in romaneio.entregaIds) {
        final pedido = dataService.pedidos.where((p) => p.id == id).firstOrNull;
        if (pedido != null && pedido.clienteTelefone != null) {
          final msg = '🚚 *Boa notícia!* Seu pedido *${pedido.numero}* saiu para entrega agora com o motorista *${romaneio.motoristaNome}*. Fique atento!';
          final enviado = await whatsapp.enviarMensagem(pedido.clienteTelefone!, msg);
          if (enviado) sucessos++;
        }
      }

      if (sucessos > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$sucessos clientes notificados via WhatsApp! ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao notificar WhatsApp: $e');
    }
  }

  void _mostrarSelecaoMultiplaPedidos(BuildContext context, DataService dataService) {
    final pedidosElegiveis = dataService.pedidos
        .where((p) => p.status != 'Cancelado')
        .toList();
    
    // Ordenar por data (mais recentes primeiro)
    pedidosElegiveis.sort((a, b) => b.dataPedido.compareTo(a.dataPedido));
    
    if (pedidosElegiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há pedidos elegíveis para entrega.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final Set<String> selecionados = {};
    String filtro = '';
    DateTime? dataInicio;
    DateTime? dataFim;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Selecionar Pedidos para o Romaneio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${selecionados.length} selecionado(s)',
                        style: const TextStyle(color: Colors.greenAccent),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (val) {
                          setSheetState(() {
                            filtro = val.toLowerCase();
                          });
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar por pedido, cliente ou endereço...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Filtro de Data no Modal
                      Row(
                        children: [
                          Expanded(
                            child: _buildBotaoDataModal(
                              label: dataInicio != null
                                  ? DateFormat('dd/MM/yy').format(dataInicio!)
                                  : 'Data Início',
                              onTap: () async {
                                final d = await _selecionarDataGenerica(context, dataInicio);
                                if (d != null) {
                                  setSheetState(() => dataInicio = DateTime(d.year, d.month, d.day));
                                }
                              },
                              isSet: dataInicio != null,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('até', style: TextStyle(color: Colors.white24, fontSize: 12)),
                          ),
                          Expanded(
                            child: _buildBotaoDataModal(
                              label: dataFim != null
                                  ? DateFormat('dd/MM/yy').format(dataFim!)
                                  : 'Data Fim',
                              onTap: () async {
                                final d = await _selecionarDataGenerica(context, dataFim);
                                if (d != null) {
                                  setSheetState(() => dataFim = DateTime(d.year, d.month, d.day, 23, 59, 59));
                                }
                              },
                              isSet: dataFim != null,
                            ),
                          ),
                          if (dataInicio != null || dataFim != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                              onPressed: () => setSheetState(() {
                                dataInicio = null;
                                dataFim = null;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final listaFiltrada = pedidosElegiveis.where((p) {
                        bool matchSearch = true;
                        if (filtro.isNotEmpty) {
                          matchSearch = p.numero.toLowerCase().contains(filtro) ||
                              (p.clienteNome?.toLowerCase().contains(filtro) ?? false) ||
                              (p.clienteEndereco?.toLowerCase().contains(filtro) ?? false);
                        }

                        bool matchDate = true;
                        if (dataInicio != null && p.dataPedido.isBefore(dataInicio!)) matchDate = false;
                        if (dataFim != null && p.dataPedido.isAfter(dataFim!)) matchDate = false;

                        return matchSearch && matchDate;
                      }).toList();

                      return ListView.builder(
                        controller: scrollController,
                        itemCount: listaFiltrada.length,
                        itemBuilder: (context, index) {
                          final pedido = listaFiltrada[index];
                          final isSelected = selecionados.contains(pedido.id);
                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: Colors.greenAccent,
                            checkColor: Colors.black,
                            title: Text(
                              pedido.numero,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pedido.clienteNome ?? 'Cliente não informado',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                ),
                                if (pedido.clienteEndereco != null)
                                  Text(
                                    pedido.clienteEndereco!,
                                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            secondary: Text(
                              'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                            ),
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  selecionados.add(pedido.id);
                                } else {
                                  selecionados.remove(pedido.id);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selecionados.isEmpty
                          ? null
                          : () {
                              Navigator.pop(context); // Fechar sheet
                              final pedidosParaRomaneio = dataService.pedidos
                                  .where((p) => selecionados.contains(p.id))
                                  .toList();
                              
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CriarRomaneioPage(pedidosSelecionados: pedidosParaRomaneio),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        disabledBackgroundColor: Colors.grey.shade800,
                      ),
                      child: const Text('GERAR ROMANEIO COM SELECIONADOS'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  Widget _buildBotaoDataModal({required String label, required VoidCallback onTap, bool isSet = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSet ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSet ? Colors.green.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSet ? Colors.greenAccent : Colors.white54,
            fontSize: 11,
            fontWeight: isSet ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<DateTime?> _selecionarDataGenerica(BuildContext context, DateTime? initial) async {
    return await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.green,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}


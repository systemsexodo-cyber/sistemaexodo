import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/entrega.dart';

class CriarRomaneioPage extends StatefulWidget {
  final List<Pedido> pedidosSelecionados;

  const CriarRomaneioPage({super.key, required this.pedidosSelecionados});

  @override
  State<CriarRomaneioPage> createState() => _CriarRomaneioPageState();
}

class _CriarRomaneioPageState extends State<CriarRomaneioPage> {
  final _observacoesController = TextEditingController();
  Motorista? _motoristaSelecionado;
  String? _veiculoPlaca;
  bool _salvando = false;
  late List<Pedido> _pedidos;

  @override
  void initState() {
    super.initState();
    _pedidos = List.from(widget.pedidosSelecionados);
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _salvarRomaneio() async {
    if (_motoristaSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um motorista'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _salvando = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      
      final novoRomaneio = Romaneio(
        id: Uuid().v4(),
        numero: dataService.gerarProximoNumeroRomaneio(),
        dataCriacao: DateTime.now(),
        motoristaId: _motoristaSelecionado!.id,
        motoristaNome: _motoristaSelecionado!.nome,
        veiculoPlaca: _veiculoPlaca ?? _motoristaSelecionado!.veiculoPlaca,
        entregaIds: _pedidos.map((p) => p.id).toList(),
        observacoes: _observacoesController.text,
        valorTotal: _pedidos.fold(0.0, (sum, p) => sum + p.totalGeral),
        status: StatusRomaneio.emPreparacao,
      );

      await dataService.addRomaneio(novoRomaneio);

      // Atualizar ou criar entregas para os pedidos vinculados
      for (final pedido in _pedidos) {
        final entregaIndex = dataService.entregas.indexWhere((e) => e.pedidoId == pedido.id);
        
        if (entregaIndex != -1) {
          // 1. Já existe uma entrega: Atualizar status
          final entrega = dataService.entregas[entregaIndex];
          if (entrega.status == StatusEntrega.aguardando) {
            final evento = EventoEntrega(
              id: const Uuid().v4(),
              dataHora: DateTime.now(),
              status: StatusEntrega.romaneioCriado,
              descricao: 'Vinculado ao Romaneio ${novoRomaneio.numero}',
            );
            dataService.updateEntrega(entrega.adicionarEvento(evento));
          }
        } else {
          // 2. Não existe entrega: Criar uma nova já com o status correto
          final novaEntrega = Entrega(
            id: const Uuid().v4(),
            pedidoId: pedido.id,
            pedidoNumero: pedido.numero,
            clienteNome: pedido.clienteNome ?? 'Cliente não informado',
            clienteTelefone: pedido.clienteTelefone,
            enderecoEntrega: pedido.clienteEndereco ?? 'Endereço não informado',
            status: StatusEntrega.romaneioCriado,
            dataCriacao: DateTime.now(),
            dataPrevisao: DateTime.now().add(const Duration(days: 1)),
            motoristaId: novoRomaneio.motoristaId,
            motoristaNome: novoRomaneio.motoristaNome,
            veiculoPlaca: novoRomaneio.veiculoPlaca,
            historico: [
              EventoEntrega(
                id: const Uuid().v4(),
                dataHora: DateTime.now(),
                status: StatusEntrega.romaneioCriado,
                descricao: 'Entrega gerada automaticamente via Romaneio ${novoRomaneio.numero}',
              )
            ],
          );
          dataService.addEntrega(novaEntrega);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Romaneio ${novoRomaneio.numero} criado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar romaneio: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final motoristas = dataService.motoristas;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerar Romaneio'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSecaoTitulo('1. Selecione o Motorista'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Motorista>(
                          value: _motoristaSelecionado,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E1E2E),
                          hint: const Text('Escolha o motorista', style: TextStyle(color: Colors.white54)),
                          style: const TextStyle(color: Colors.white),
                          items: motoristas.map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(m.nome),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _motoristaSelecionado = val;
                              _veiculoPlaca = val?.veiculoPlaca;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_motoristaSelecionado != null) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _veiculoPlaca,
                        onChanged: (val) => _veiculoPlaca = val,
                        style: const TextStyle(color: Colors.white),
                        decoration: AppTheme.inputDecoration('Placa do Veículo', icon: Icons.directions_car),
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSecaoTitulo('2. Ordem de Entrega'),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _pedidos.sort((a, b) => 
                                (a.deliveryInfo?.bairro ?? '').compareTo(b.deliveryInfo?.bairro ?? '')
                              );
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Rota organizada por bairro!')),
                            );
                          },
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Otimizar (Bairro)', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pedidos.length,
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = _pedidos.removeAt(oldIndex);
                          _pedidos.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final pedido = _pedidos[index];
                        return Container(
                          key: ValueKey(pedido.id),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.receipt, color: Colors.blueAccent, size: 16),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pedido.numero, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    Text(pedido.clienteNome ?? 'Sem cliente', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(
                                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(pedido.totalGeral),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.drag_handle, color: Colors.white54),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildSecaoTitulo('3. Observações'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _observacoesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: AppTheme.inputDecoration('Observações do romaneio', icon: Icons.notes),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -5)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total do Romaneio', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(
                            _pedidos.fold(0.0, (sum, p) => sum + p.totalGeral)
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _salvando ? null : _salvarRomaneio,
                    icon: _salvando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                    label: const Text('SALVAR ROMANEIO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

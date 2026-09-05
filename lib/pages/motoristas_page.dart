import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/motorista.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../widgets/sync_status_widget.dart';

class MotoristasPage extends StatefulWidget {
  final bool isEmbedded;
  const MotoristasPage({super.key, this.isEmbedded = false});

  @override
  State<MotoristasPage> createState() => _MotoristasPageState();
}

class _MotoristasPageState extends State<MotoristasPage> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final motoristas = dataService.motoristas.where((m) {
      if (_termoBusca.isEmpty) return true;
      return m.nome.toLowerCase().contains(_termoBusca.toLowerCase()) ||
             (m.veiculoPlaca?.toLowerCase().contains(_termoBusca.toLowerCase()) ?? false);
    }).toList();

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _buscaController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou placa...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add, color: Colors.blue),
                onPressed: () => _mostrarDialogoMotorista(context, dataService),
              ),
            ),
            onChanged: (v) => setState(() => _termoBusca = v),
          ),
        ),
        Expanded(
          child: motoristas.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: motoristas.length,
                  itemBuilder: (context, index) {
                    final m = motoristas[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withOpacity(0.2),
                          child: const Icon(Icons.motorcycle, color: Colors.blue),
                        ),
                        title: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(
                          '${m.veiculoModelo ?? "Moto"} - ${m.veiculoPlaca ?? "S/ Placa"}\nComissão: ${m.tipoComissao} (R\$ ${m.valorComissao.toStringAsFixed(2)})',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                              onPressed: () => _mostrarDialogoMotorista(context, dataService, motorista: m),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () => _confirmarExclusao(context, dataService, m),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.isEmbedded) return content;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Entregadores / Motoboys'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            const SyncStatusWidget(),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _mostrarDialogoMotorista(context, dataService),
            ),
          ],
        ),
        body: content,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('Nenhum entregador encontrado', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  void _mostrarDialogoMotorista(BuildContext context, DataService dataService, {Motorista? motorista}) {
    final nomeC = TextEditingController(text: motorista?.nome);
    final telefoneC = TextEditingController(text: motorista?.telefone);
    final placaC = TextEditingController(text: motorista?.veiculoPlaca);
    final modeloC = TextEditingController(text: motorista?.veiculoModelo);
    final valorComissaoC = TextEditingController(text: motorista?.valorComissao.toString() ?? '5.00');
    String tipoComissao = motorista?.tipoComissao ?? 'Fixo por Entrega';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(motorista == null ? 'Novo Entregador' : 'Editar Entregador', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomeC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nome *')),
                TextField(controller: telefoneC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Telefone')),
                TextField(controller: modeloC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Modelo Veículo')),
                TextField(controller: placaC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Placa')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: tipoComissao,
                  dropdownColor: const Color(0xFF2C3E50),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Tipo de Comissão'),
                  items: ['Fixo por Entrega', 'Diária', 'Porcentagem'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => tipoComissao = v!),
                ),
                TextField(
                  controller: valorComissaoC,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor (R\$ ou %)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () {
                if (nomeC.text.isEmpty) return;
                final m = Motorista(
                  id: motorista?.id,
                  nome: nomeC.text,
                  telefone: telefoneC.text,
                  veiculoPlaca: placaC.text,
                  veiculoModelo: modeloC.text,
                  tipoComissao: tipoComissao,
                  valorComissao: double.tryParse(valorComissaoC.text) ?? 0.0,
                  taxaPadrao: double.tryParse(valorComissaoC.text) ?? 0.0,
                  dataCadastro: motorista?.dataCadastro,
                );
                if (motorista == null) {
                  dataService.addMotorista(m);
                } else {
                  dataService.updateMotorista(m);
                }
                Navigator.pop(context);
              },
              child: const Text('SALVAR'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarExclusao(BuildContext context, DataService dataService, Motorista m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Excluir Entregador?', style: TextStyle(color: Colors.white)),
        content: Text('Deseja realmente excluir ${m.nome}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('NÃO')),
          ElevatedButton(
            onPressed: () {
              dataService.deleteMotorista(m.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SIM, EXCLUIR'),
          ),
        ],
      ),
    );
  }
}

import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/ordem_servico.dart';
import '../models/cliente.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

class OrdensServicoPage extends StatelessWidget {
  const OrdensServicoPage({super.key});

  static final List<Map<String, String>> ordens = [
    {'nome': 'OS 001', 'descricao': 'Cliente: João Silva'},
    {'nome': 'OS 002', 'descricao': 'Cliente: Maria Souza'},
  ];

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Ordens de Serviço'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _AdicionarOrdemServicoDialog(),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView.separated(
            itemCount: ordens.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final ordem = ordens[index];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B8D4), Color(0xFF43EA8E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  leading: const Icon(Icons.assignment, color: Colors.white),
                  title: Text(
                    ordem['nome']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    ordem['descricao']!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white70),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white70),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Modal de adicionar ordem de serviço na mesma tela
class _AdicionarOrdemServicoDialog extends StatefulWidget {
  @override
  State<_AdicionarOrdemServicoDialog> createState() =>
      _AdicionarOrdemServicoDialogState();
}

class _AdicionarOrdemServicoDialogState
    extends State<_AdicionarOrdemServicoDialog> {
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF23272A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nome da Ordem',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF181A1B),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white38),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descricaoController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Descrição',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF181A1B),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white38),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final dataService = Provider.of<DataService>(
                  context,
                  listen: false,
                );
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                final agora = DateTime.now();
                final cliente = Cliente(
                  id: 'c$id',
                  nome: _nomeController.text,
                  telefone: '',
                  createdAt: agora,
                  updatedAt: agora,
                );
                final ordem = OrdemServico(id: id, cliente: cliente);
                await dataService.addOrdemServico(ordem);
                Navigator.of(context).pop();
              },
              child: const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }
}

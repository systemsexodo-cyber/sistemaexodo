import 'package:flutter/material.dart';
import '../ordem_servico.dart';

class LancamentoServicoForm extends StatefulWidget {
  final OrdemServico? os;
  final Function(OrdemServico) onSave;

  const LancamentoServicoForm({super.key, this.os, required this.onSave});

  @override
  State<LancamentoServicoForm> createState() => _LancamentoServicoFormState();
}

class _LancamentoServicoFormState extends State<LancamentoServicoForm> {
  late TextEditingController _clienteController;
  late TextEditingController _valorController;

  @override
  void initState() {
    super.initState();
    _clienteController = TextEditingController(
      text: widget.os?.cliente.nome ?? '',
    );
    _valorController = TextEditingController(
      text: widget.os?.valorTotal.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Color(0xFF23272A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _clienteController,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              decoration: InputDecoration(
                labelText: 'Cliente',
                labelStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withOpacity(0.7),
                ),
                filled: true,
                fillColor: Color(0xFF181A1B),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.38),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _valorController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              decoration: InputDecoration(
                labelText: 'Valor Total',
                labelStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withOpacity(0.7),
                ),
                filled: true,
                fillColor: Color(0xFF181A1B),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.38),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                textStyle: TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                // Aqui você pode criar/atualizar a ordem de serviço
                Navigator.of(context).pop();
              },
              child: Text(
                'Salvar',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

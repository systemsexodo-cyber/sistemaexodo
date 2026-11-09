import 'package:flutter/material.dart';

/// Dropdown isolado de seleção de fornecedor, usado na aba de filtros da
/// aba de notas de entrada.
class DropdownFornecedor extends StatelessWidget {
  final List<String> fornecedores;
  final String? selecionado;
  final ValueChanged<String?> onChanged;

  const DropdownFornecedor({
    super.key,
    required this.fornecedores,
    required this.selecionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final temOpcoes = fornecedores.isNotEmpty;

    return DropdownButton<String>(
      value: selecionado,
      hint: const Text(
        'Fornecedor',
        style: TextStyle(color: Colors.white70),
      ),
      isExpanded: true,
      underline: const SizedBox(),
      icon: const Icon(Icons.sort, color: Colors.white70, size: 20),
      dropdownColor: const Color(0xFF2C3E50),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text(
            'Todos',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        if (temOpcoes)
          ...fornecedores.map(
            (nome) => DropdownMenuItem<String>(
              value: nome,
              child: Text(nome),
            ),
          ),
      ],
      onChanged: temOpcoes ? onChanged : null,
    );
  }
}

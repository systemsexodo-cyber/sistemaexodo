import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pergunta_selecao.dart';
import '../models/produto.dart';
import '../services/data_service.dart';

/// Diálogo modal interativo para escolher as opções dos combos/perguntas no PDV/Vendas.
class PopupPerguntasCombo extends StatefulWidget {
  final Produto produto;

  const PopupPerguntasCombo({super.key, required this.produto});

  @override
  State<PopupPerguntasCombo> createState() => _PopupPerguntasComboState();
}

class _PopupPerguntasComboState extends State<PopupPerguntasCombo> {
  // Guarda as opções selecionadas por pergunta: { perguntaId: [OpcaoPerguntaSelecao] }
  final Map<String, List<OpcaoPerguntaSelecao>> _selecoes = {};

  @override
  void initState() {
    super.initState();
    // Inicializa listas de seleções vazias para cada pergunta
    for (final pergunta in widget.produto.perguntasSelecao) {
      _selecoes[pergunta.id] = [];
    }
  }

  /// Verifica se todas as restrições obrigatórias foram cumpridas
  bool _podeConfirmar() {
    for (final pergunta in widget.produto.perguntasSelecao) {
      final selecionados = _selecoes[pergunta.id] ?? [];
      
      // Validação obrigatória e quantidade mínima
      if (pergunta.obrigatorio && selecionados.length < pergunta.minimo) {
        return false;
      }
      
      // Validação de quantidade máxima
      if (selecionados.length > pergunta.maximo) {
        return false;
      }
    }
    return true;
  }

  void _toggleOpcao(PerguntaSelecao pergunta, OpcaoPerguntaSelecao opcao) {
    setState(() {
      final selecionados = _selecoes[pergunta.id] ?? [];
      
      if (pergunta.maximo == 1) {
        // Seleção única (comportamento de Radio)
        if (selecionados.contains(opcao)) {
          selecionados.clear();
        } else {
          selecionados.clear();
          selecionados.add(opcao);
        }
      } else {
        // Seleção múltipla (comportamento de Checkbox)
        if (selecionados.contains(opcao)) {
          selecionados.remove(opcao);
        } else {
          if (selecionados.length < pergunta.maximo) {
            selecionados.add(opcao);
          } else {
            // Remove a primeira opção para dar lugar à nova (ou apenas ignora)
            selecionados.removeAt(0);
            selecionados.add(opcao);
          }
        }
      }
      _selecoes[pergunta.id] = selecionados;
    });
  }

  /// Mostra os itens fixos inclusos no combo (produtos compostos)
  Widget _buildItensInclusos() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                'Itens inclusos neste combo',
                style: TextStyle(
                  color: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.produto.composicao.map((itemComp) {
            final prod = dataService.produtos.cast<Produto?>().firstWhere(
              (p) => p?.id == itemComp.produtoId,
              orElse: () => null,
            );
            final nome = prod?.nome ?? 'Item do combo';
            final qtdFmt = itemComp.quantidade == itemComp.quantidade.roundToDouble()
                ? itemComp.quantidade.toStringAsFixed(0)
                : itemComp.quantidade.toStringAsFixed(2);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nome,
                      style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '×$qtdFmt',
                    style: TextStyle(
                      color: isDark ? Colors.white.withOpacity(0.5) : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF13131A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8FAFC),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.produto.nome,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Escolha as opções abaixo para montar este item:',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...widget.produto.perguntasSelecao.map((pergunta) {
              final selecionados = _selecoes[pergunta.id] ?? [];
              final totalSelecionados = selecionados.length;
              final temErro = pergunta.obrigatorio && totalSelecionados < pergunta.minimo;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: temErro ? Colors.redAccent.withOpacity(0.5) : Colors.white10,
                    width: temErro ? 1.5 : 1,
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
                            pergunta.titulo,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (pergunta.obrigatorio)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Obrigatório',
                              style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Selecione de ${pergunta.minimo} a ${pergunta.maximo} opção(ões) ($totalSelecionados selecionada(s))',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12),
                    ),
                    const Divider(color: Colors.white10, height: 20),
                    Column(
                      children: pergunta.opcoes.map((opcao) {
                        final isSelecionado = selecionados.contains(opcao);
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelecionado 
                                ? Colors.blueAccent.withOpacity(0.1) 
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelecionado ? Colors.blueAccent : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onTap: () => _toggleOpcao(pergunta, opcao),
                            leading: Icon(
                              pergunta.maximo == 1 
                                  ? (isSelecionado ? Icons.radio_button_checked : Icons.radio_button_off)
                                  : (isSelecionado ? Icons.check_box : Icons.check_box_outline_blank),
                              color: isSelecionado ? Colors.blueAccent : (isDark ? Colors.white30 : Colors.black26),
                            ),
                            title: Text(
                              opcao.nome,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: opcao.precoAdicional > 0
                                ? Text(
                                    '+ R\$ ${opcao.precoAdicional.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }),
            if (widget.produto.ehComposto && widget.produto.composicao.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildItensInclusos(),
            ],
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _podeConfirmar() ? Colors.blueAccent : Colors.white10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _podeConfirmar() 
              ? () {
                  // Achata todas as seleções em uma única lista de opções
                  final selecionadas = <OpcaoPerguntaSelecao>[];
                  for (final lista in _selecoes.values) {
                    selecionadas.addAll(lista);
                  }
                  Navigator.pop(context, selecionadas);
                }
              : null,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Confirmar Escolhas', 
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

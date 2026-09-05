import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Substituir a ação do botão "Confirmar Seleção"
target_btn = """                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: selecionadosLote.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selecionados.clear();
                                  _selecionados.addAll(selecionadosLote);
                                });
                                _validarEEmitir(itensFaturaveis, dataService);
                              },
                        child: const Text('Confirmar Seleção'),
                      )"""

replacement_btn = """                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: selecionadosLote.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selecionados.clear();
                                  _selecionados.addAll(selecionadosLote);
                                });
                                
                                // Se for apenas 1 venda/pedido, abre a tela de emissão manual pré-carregada
                                if (selecionadosLote.length == 1) {
                                  final idLote = selecionadosLote.first;
                                  final itemFat = itensFaturaveis.firstWhere((i) => i['id'] == idLote);
                                  if (itemFat['tipo'] == 'Venda') {
                                    _abrirFaturamentoManual(venda: itemFat);
                                  } else {
                                    _abrirFaturamentoManual(pedido: itemFat);
                                  }
                                } else {
                                  // Se forem múltiplos, oferece a opção de consolidar em uma nota ou emitir em lote
                                  showDialog(
                                    context: context,
                                    builder: (subCtx) => AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E2E),
                                      title: const Text('Opções de Faturamento', style: TextStyle(color: Colors.white)),
                                      content: Text('Você selecionou ${selecionadosLote.length} registros. Como deseja prosseguir?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(subCtx);
                                            // Abre a emissão manual consolidando todos os itens!
                                            final loteComItens = itensFaturaveis.where((i) => selecionadosLote.contains(i['id'])).toList();
                                            _abrirFaturamentoManual(lote: loteComItens);
                                          },
                                          child: const Text('Consolidar em 1 NF-e Manual', style: TextStyle(color: Colors.greenAccent)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(subCtx);
                                            _validarEEmitir(itensFaturaveis, dataService);
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                          child: const Text('Emitir em Lote (Direto)'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                        child: const Text('Confirmar Seleção'),
                      )"""

if target_btn in content:
    content = content.replace(target_btn, replacement_btn)
    print("BOTAO_CONFIRMAR_REDIRECIONADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_btn.replace("\r\n", "\n")
    normalized_replacement = replacement_btn.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("BOTAO_CONFIRMAR_REDIRECIONADO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_BOTAO_CONFIRMAR")


# 2. Injetar o método _abrirFaturamentoManual na classe _NFePageState
# Vamos achar um local apropriado, ex: logo após a definição de _confirmarEmissaoLote
target_confirmar = """  void _confirmarEmissaoLote() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),"""

replacement_confirmar = """  void _abrirFaturamentoManual({
    Map<String, dynamic>? venda,
    Map<String, dynamic>? pedido,
    List<Map<String, dynamic>>? lote,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _EmissaoManualPage(
        dataService: widget.dataService,
        vendaFaturar: venda,
        pedidoFaturar: pedido,
        loteFaturar: lote,
        numeroController: _numeroController,
        serieController: _serieController,
        ambienteHomologacao: _ambienteHomologacao,
        onEmitida: () {
          setState(() {
            _selecionados.clear();
          });
        },
      ),
    );
  }

  void _confirmarEmissaoLote() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),"""

if target_confirmar in content:
    content = content.replace(target_confirmar, replacement_confirmar)
    print("METODO_ABRIR_MANUAL_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_confirmar.replace("\r\n", "\n")
    normalized_replacement = replacement_confirmar.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("METODO_ABRIR_MANUAL_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_METODO_ABRIR_MANUAL")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

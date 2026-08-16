import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """  void _abrirFaturamentoManual({
    Map<String, dynamic>? venda,
    Map<String, dynamic>? pedido,
    List<Map<String, dynamic>>? lote,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _EmissaoManualPage(
        dataService: dataService,
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
  }"""

replacement = """  void _abrirFaturamentoManual({
    Map<String, dynamic>? venda,
    Map<String, dynamic>? pedido,
    List<Map<String, dynamic>>? lote,
  }) {
    final dataService = Provider.of<DataService>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => _EmissaoManualPage(
        dataService: dataService,
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
  }"""

if target in content:
    content = content.replace(target, replacement)
    print("DATASERVICE_MANUAL_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DATASERVICE_MANUAL_CORRIGIDO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_DATASERVICE_MANUAL")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

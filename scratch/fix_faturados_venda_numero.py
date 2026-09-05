import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Definir vId e vNum antes do service.emitir manual ---
target_before = """      final Map<String, double> qtdeMap = {for (var i in _itens) (i['produto'] as Produto).id: i['qtd'] as double};
      final total = _total;
      final numForcado = int.tryParse(widget.numeroController.text);
      final serieForcada = int.tryParse(widget.serieController.text);

      final responseNfce = await service.emitir("""

replacement_before = """      final Map<String, double> qtdeMap = {for (var i in _itens) (i['produto'] as Produto).id: i['qtd'] as double};
      final total = _total;
      final numForcado = int.tryParse(widget.numeroController.text);
      final serieForcada = int.tryParse(widget.serieController.text);

      // Determinar ID e Número da venda/pedido de origem
      String? vId;
      String? vNum;
      if (widget.vendaFaturar != null) {
        vId = widget.vendaFaturar!['id'];
        vNum = widget.vendaFaturar!['numero'];
      } else if (widget.pedidoFaturar != null) {
        vId = widget.pedidoFaturar!['id'];
        vNum = widget.pedidoFaturar!['numero'];
      } else if (widget.loteFaturar != null) {
        vId = widget.loteFaturar!.map((i) => i['id']).join(', ');
        vNum = widget.loteFaturar!.map((i) => i['numero']).join(', ');
      }

      final responseNfce = await service.emitir("""

if target_before in content:
    content = content.replace(target_before, replacement_before)
    print("VARIAVEIS_ORIGEM_INJETADAS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_before.replace("\r\n", "\n")
    normalized_replacement = replacement_before.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("VARIAVEIS_ORIGEM_INJETADAS_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_VARIAVEIS_ORIGEM")


# --- 2. Injetar vendaId e vendaNumero na chamada manual de emitir ---
target_emitir_params = """        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
      );"""

replacement_emitir_params = """        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
        vendaId: vId,
        vendaNumero: vNum,
      );"""

if target_emitir_params in content:
    content = content.replace(target_emitir_params, replacement_emitir_params)
    print("PARAMETROS_ORIGEM_EMITIR_INJETADOS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_emitir_params.replace("\r\n", "\n")
    normalized_replacement = replacement_emitir_params.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("PARAMETROS_ORIGEM_EMITIR_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_PARAMETROS_ORIGEM_EMITIR")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

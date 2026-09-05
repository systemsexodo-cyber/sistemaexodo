import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Corrigir widget.dataService na chamada de _abrirFaturamentoManual
content = content.replace("dataService: widget.dataService,", "dataService: dataService,")

# 2. Corrigir p.itens para p.produtos na leitura do faturamento de Pedido
target_itens1 = """      } else if (widget.pedidoFaturar != null) {
        final idPed = widget.pedidoFaturar!['id'];
        try {
          final p = widget.dataService.pedidos.firstWhere((p) => p.id == idPed);
          itensOriginais = p.itens;
        } catch (_) {}"""

replacement_itens1 = """      } else if (widget.pedidoFaturar != null) {
        final idPed = widget.pedidoFaturar!['id'];
        try {
          final p = widget.dataService.pedidos.firstWhere((p) => p.id == idPed);
          itensOriginais = p.produtos;
        } catch (_) {}"""

target_itens2 = """          } else {
            try {
              final p = widget.dataService.pedidos.firstWhere((p) => p.id == idLote);
              itensOriginais.addAll(p.itens);
            } catch (_) {}
          }"""

replacement_itens2 = """          } else {
            try {
              final p = widget.dataService.pedidos.firstWhere((p) => p.id == idLote);
              itensOriginais.addAll(p.produtos);
            } catch (_) {}
          }"""

if target_itens1 in content:
    content = content.replace(target_itens1, replacement_itens1)
    print("ITENS_PEDIDO_1_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_itens1.replace("\r\n", "\n")
    normalized_replacement = replacement_itens1.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("ITENS_PEDIDO_1_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_ITENS_PEDIDO_1")

if target_itens2 in content:
    content = content.replace(target_itens2, replacement_itens2)
    print("ITENS_PEDIDO_2_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_itens2.replace("\r\n", "\n")
    normalized_replacement = replacement_itens2.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("ITENS_PEDIDO_2_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_ITENS_PEDIDO_2")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

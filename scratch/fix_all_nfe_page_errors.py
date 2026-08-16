import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Escapar os '$' na aba de impostos
content = content.replace("decoration: _dec('Valor do Frete (R$)'", "decoration: _dec('Valor do Frete (R\\$)'")
content = content.replace("decoration: _dec('Valor do Seguro (R$)'", "decoration: _dec('Valor do Seguro (R\\$)'")
content = content.replace("decoration: _dec('Outras Despesas (R$)'", "decoration: _dec('Outras Despesas (R\\$)'")

# 2. Corrigir os nomes dos parâmetros de despesa na chamada do service.emitir
target_emitir = """        freteValor: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        seguroValor: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesasValor: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,"""

replacement_emitir = """        valorFrete: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        valorSeguro: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesas: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,"""

if target_emitir in content:
    content = content.replace(target_emitir, replacement_emitir)
    print("PARAMETROS_EMITIR_CORRIGIDOS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_emitir.replace("\r\n", "\n")
    normalized_replacement = replacement_emitir.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("PARAMETROS_EMITIR_CORRIGIDOS_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_PARAMETROS_EMITIR")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("CORRECAO_COMPLETA_SALVA")

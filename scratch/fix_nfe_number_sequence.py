import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """    // Descobrir a próxima numeração automaticamente se o controller estiver vazio
    if (_numeroController.text.isEmpty) {
      int maiorNumero = 0;
      for (final n in nfes) {
        final numInt = int.tryParse(n.numero.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        // Ignora timestamps ou IDs gigantes (números acima de 999.999.999) para não corromper a numeração
        if (numInt > maiorNumero && numInt <= 999999999) {
          maiorNumero = numInt;
        }
      }
      _numeroController.text = (maiorNumero + 1).toString();
    }"""

replacement = """    // Descobrir a próxima numeração automaticamente baseada na última nota cronológica emitida (não no maior número)
    if (_numeroController.text.isEmpty) {
      int ultimoNumeroEmitido = 0;
      if (nfes.isNotEmpty) {
        // Como nfes está ordenado por dataEmissao descrescente, o primeiro é o mais recente cronologicamente
        final maisRecente = nfes.first;
        final numInt = int.tryParse(maisRecente.numero.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (numInt <= 999999999) {
          ultimoNumeroEmitido = numInt;
        }
      }
      _numeroController.text = (ultimoNumeroEmitido + 1).toString();
    }"""

if target in content:
    content = content.replace(target, replacement)
    print("NUMERACAO_CRONOLOGICA_IMPLEMENTADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("NUMERACAO_CRONOLOGICA_NORMALIZADA")
    else:
        print("FALHA_AO_INJECTAR_NUMERACAO_CRONOLOGICA")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """            Text(
              'Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\\$').format(_total)}',
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),"""

replacement = """            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ICMS Estimado: R\\$ ${( _total * (double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0) / 100 ).toStringAsFixed(2)}  ',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    if (double.tryParse(_freteValorCtrl.text) != null && double.tryParse(_freteValorCtrl.text)! > 0)
                      Text(
                        'Frete: R\\$ ${double.tryParse(_freteValorCtrl.text)!.toStringAsFixed(2)}  ',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
                Text(
                  'Total Geral: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\\$').format(_total + (double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0))}',
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),"""

if target in content:
    content = content.replace(target, replacement)
    print("BOTTOM_TOTAL_FISCAL_ESTIMADO_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("BOTTOM_TOTAL_FISCAL_ESTIMADO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_BOTTOM_TOTAL")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

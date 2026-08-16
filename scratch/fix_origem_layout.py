import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """                                // ── Linha 2: Destinatário ──
                                Text(
                                  'Destinatário: ${n.nomeConsumidor ?? "Não informado"}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),"""

replacement = """                                // ── Linha 2: Destinatário ──
                                Text(
                                  'Destinatário: ${n.nomeConsumidor ?? "Não informado"}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),

                                // Exibir a Origem se faturada de Venda ou Pedido
                                if (n.vendaNumero != null && n.vendaNumero!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        n.vendaNumero!.startsWith('PED') ? Icons.assignment_outlined : Icons.shopping_bag_outlined,
                                        size: 13,
                                        color: Colors.blueAccent,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Faturamento Origem: ' + n.vendaNumero!,
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],"""

if target in content:
    content = content.replace(target, replacement)
    print("ORIGEM_LAYOUT_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("ORIGEM_LAYOUT_CORRIGIDO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_ORIGEM_LAYOUT")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

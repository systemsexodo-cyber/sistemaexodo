import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Injetar o método _obterOrigemDinamica no _NfePageState ---
# Vamos injetá-lo logo acima de _abrirFaturamentoManual
target_manual = """  void _abrirFaturamentoManual({"""

replacement_manual = """  String? _obterOrigemDinamica(NFCe nfe, DataService dataService) {
    if (nfe.vendaNumero != null && nfe.vendaNumero!.isNotEmpty) {
      return nfe.vendaNumero;
    }
    if (nfe.vendaId != null && nfe.vendaId!.isNotEmpty) {
      try {
        final v = dataService.vendasBalcao.firstWhere((v) => v.id == nfe.vendaId);
        return v.numero;
      } catch (_) {}
      try {
        final p = dataService.pedidos.firstWhere((p) => p.id == nfe.vendaId);
        return p.numero;
      } catch (_) {}
    }
    
    // Fallback inteligente por cliente e valor aproximado
    final docLimpoNfe = nfe.cpfCnpjConsumidor?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (docLimpoNfe.isNotEmpty) {
      try {
        final v = dataService.vendasBalcao.firstWhere((v) {
          final docLimpoVenda = v.clienteCpfCnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          return docLimpoVenda == docLimpoNfe && (v.valorTotal - nfe.valorTotal).abs() < 0.05;
        });
        return v.numero;
      } catch (_) {}

      try {
        final p = dataService.pedidos.firstWhere((p) {
          final docLimpoPed = p.clienteCpfCnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          return docLimpoPed == docLimpoNfe && (p.total - nfe.valorTotal).abs() < 0.05;
        });
        return p.numero;
      } catch (_) {}
    }
    return null;
  }

  void _abrirFaturamentoManual({"""

if target_manual in content:
    content = content.replace(target_manual, replacement_manual)
    print("METODO_ORIGEM_DINAMICA_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_manual.replace("\r\n", "\n")
    normalized_replacement = replacement_manual.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("METODO_ORIGEM_DINAMICA_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_METODO_ORIGEM_DINAMICA")


# --- 2. Atualizar a exibição da origem no card principal para usar a versão dinâmica ---
target_card_origem = """                                // Exibir a Origem se faturada de Venda ou Pedido
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

replacement_card_origem = """                                // Exibir a Origem se faturada de Venda ou Pedido
                                Builder(
                                  builder: (ctx) {
                                    final origem = _obterOrigemDinamica(n, dataService);
                                    if (origem == null) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        children: [
                                          Icon(
                                            origem.startsWith('PED') ? Icons.assignment_outlined : Icons.shopping_bag_outlined,
                                            size: 13,
                                            color: Colors.blueAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Faturamento Origem: ' + origem,
                                            style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),"""

if target_card_origem in content:
    content = content.replace(target_card_origem, replacement_card_origem)
    print("CARD_ORIGEM_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_card_origem.replace("\r\n", "\n")
    normalized_replacement = replacement_card_origem.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CARD_ORIGEM_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_CARD_ORIGEM")


# --- 3. Injetar a linha de Origem na modal de Detalhes da NF-e ---
target_modal_origem = """                  if (n.protocolo != null && n.protocolo!.isNotEmpty)
                    _buildDetailRow('Protocolo:', n.protocolo!),"""

replacement_modal_origem = """                  if (n.protocolo != null && n.protocolo!.isNotEmpty)
                    _buildDetailRow('Protocolo:', n.protocolo!),
                  Builder(
                    builder: (ctx) {
                      final origem = _obterOrigemDinamica(n, dataService);
                      if (origem != null) {
                        return _buildDetailRow('Origem do Faturamento:', origem);
                      }
                      return const SizedBox.shrink();
                    },
                  ),"""

if target_modal_origem in content:
    content = content.replace(target_modal_origem, replacement_modal_origem)
    print("MODAL_ORIGEM_INJETADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_modal_origem.replace("\r\n", "\n")
    normalized_replacement = replacement_modal_origem.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("MODAL_ORIGEM_NORMALIZADA")
    else:
        print("FALHA_AO_INJETAR_MODAL_ORIGEM")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Exibir a tag de Origem no card principal da listagem de notas ---
target_origem_layout = """                                // ── Linha 2: Destinatário ──
                                Text(
                                  'Destinatário: ${n.nomeConsumidor ?? "Não informado"}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                );"""

replacement_origem_layout = """                                // ── Linha 2: Destinatário ──
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

if target_origem_layout in content:
    content = content.replace(target_origem_layout, replacement_origem_layout)
    print("ORIGEM_LAYOUT_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_origem_layout.replace("\r\n", "\n")
    normalized_replacement = replacement_origem_layout.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("ORIGEM_LAYOUT_INJETADO_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_ORIGEM_LAYOUT")


# --- 2. Mapear e adicionar a flag 'faturado' nos itens da modal ---
target_itens_loop = """          final List<Map<String, dynamic>> itensFaturaveis = [];
          
          for (final v in vendas) {
            itensFaturaveis.add({
              'id': v.id,
              'numero': v.numero,
              'cliente': v.clienteNome ?? 'Consumidor Final',
              'clienteId': v.clienteId,
              'clienteCpfCnpj': v.clienteCpfCnpj,
              'data': v.dataVenda,
              'valor': v.valorTotal,
              'status': v.cancelado ? 'Cancelada' : 'Finalizada',
              'tipo': 'Venda',
              'origem': v,
            });
          }

          for (final p in pedidos) {
            itensFaturaveis.add({
              'id': p.id,
              'numero': p.numero,
              'cliente': p.clienteNome ?? 'Consumidor Final',
              'clienteId': p.clienteId,
              'clienteCpfCnpj': p.clienteCpfCnpj,
              'data': p.dataPedido,
              'valor': p.total,
              'status': p.status,
              'tipo': 'Pedido',
              'origem': p,
            });
          }"""

replacement_itens_loop = """          final List<Map<String, dynamic>> itensFaturaveis = [];
          
          // Mapeamento de notas autorizadas para identificar faturados
          final autorizadasVendasIds = dataService.nfces
              .where((n) => n.vendaId != null)
              .map((n) => n.vendaId!)
              .toSet();
          
          final autorizadasVendasNums = dataService.nfces
              .where((n) => n.vendaNumero != null)
              .map((n) => n.vendaNumero!)
              .toSet();
          
          for (final v in vendas) {
            final jaFaturado = autorizadasVendasIds.contains(v.id) || autorizadasVendasNums.contains(v.numero);
            itensFaturaveis.add({
              'id': v.id,
              'numero': v.numero,
              'cliente': v.clienteNome ?? 'Consumidor Final',
              'clienteId': v.clienteId,
              'clienteCpfCnpj': v.clienteCpfCnpj,
              'data': v.dataVenda,
              'valor': v.valorTotal,
              'status': v.cancelado ? 'Cancelada' : 'Finalizada',
              'tipo': 'Venda',
              'origem': v,
              'faturado': jaFaturado,
            });
          }

          for (final p in pedidos) {
            final jaFaturado = autorizadasVendasIds.contains(p.id) || autorizadasVendasNums.contains(p.numero);
            itensFaturaveis.add({
              'id': p.id,
              'numero': p.numero,
              'cliente': p.clienteNome ?? 'Consumidor Final',
              'clienteId': p.clienteId,
              'clienteCpfCnpj': p.clienteCpfCnpj,
              'data': p.dataPedido,
              'valor': p.total,
              'status': p.status,
              'tipo': 'Pedido',
              'origem': p,
              'faturado': jaFaturado,
            });
          }"""

if target_itens_loop in content:
    content = content.replace(target_itens_loop, replacement_itens_loop)
    print("ITENS_LOOP_MAINTAINED")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_itens_loop.replace("\r\n", "\n")
    normalized_replacement = replacement_itens_loop.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("ITENS_LOOP_NORMALIZADO")
    else:
        print("FALHA_AO_EDITAR_ITENS_LOOP")


# --- 3. Atualizar a listagem para exibir a tag FATURADO e desabilitar re-seleção ---
target_list_item = """                              return Card(
                                color: const Color(0xFF13131A),
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: CheckboxListTile(
                                  value: selecionado,
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item['tipo'] == 'Venda' ? Colors.green.withValues(alpha: 0.15) : Colors.purple.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(item['tipo'].toString().toUpperCase(), style: TextStyle(color: item['tipo'] == 'Venda' ? Colors.greenAccent : Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('Nº ${item['numero']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                  subtitle: Text('Cliente: ${item['cliente']}\\nValor: R\\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                  activeColor: Colors.blue,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selecionadosLote.add(id);
                                      } else {
                                        selecionadosLote.remove(id);
                                      }
                                    });
                                  },
                                ),
                              );"""

# Escapar regex para substituir
replacement_list_item = """                              final jaFaturado = item['faturado'] == true;
                              return Card(
                                color: jaFaturado ? const Color(0xFF1B2C1C) : const Color(0xFF13131A),
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: jaFaturado 
                                  ? ListTile(
                                      title: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item['tipo'] == 'Venda' ? Colors.green.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(item['tipo'].toString().toUpperCase(), style: TextStyle(color: item['tipo'] == 'Venda' ? Colors.greenAccent : Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Nº ${item['numero']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                      subtitle: Text('Cliente: ${item['cliente']}\\nValor: R\\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check, color: Colors.greenAccent, size: 12),
                                            SizedBox(width: 4),
                                            Text('FATURADO', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    )
                                  : CheckboxListTile(
                                      value: selecionado,
                                      title: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item['tipo'] == 'Venda' ? Colors.green.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(item['tipo'].toString().toUpperCase(), style: TextStyle(color: item['tipo'] == 'Venda' ? Colors.greenAccent : Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Nº ${item['numero']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                      subtitle: Text('Cliente: ${item['cliente']}\\nValor: R\\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      activeColor: Colors.blue,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          if (val == true) {
                                            selecionadosLote.add(id);
                                          } else {
                                            selecionadosLote.remove(id);
                                          }
                                        });
                                      },
                                    ),
                              );"""

if target_list_item in content:
    content = content.replace(target_list_item, replacement_list_item)
    print("LIST_ITEM_INJETADO")
else:
    # Caso contenha withValues em vez de withOpacity
    normalized_content = content.replace("\r\n", "\n")
    target_list_item_alt = target_list_item.replace("withValues(alpha: 0.15)", "withOpacity(0.15)")
    normalized_target = target_list_item_alt.replace("\r\n", "\n")
    normalized_replacement = replacement_list_item.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("LIST_ITEM_INJETADO_ALT")
    else:
        # Tenta com o withValues original que estava no nfe_page.dart
        normalized_target_values = target_list_item.replace("\r\n", "\n")
        if normalized_target_values in normalized_content:
            normalized_content = normalized_content.replace(normalized_target_values, normalized_replacement)
            content = normalized_content
            print("LIST_ITEM_INJETADO_VALUES")
        else:
            print("FALHA_AO_INJETAR_LIST_ITEM")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

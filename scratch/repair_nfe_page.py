import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Qtd: $qtd  |  Unit: R\\$ ${preco.toStringAsFixed(2)}  |  Total: R\\$ ${(qtd * preco).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('NCM: ${item['ncm']}  |  CFOP: ${item['cfop']}  |  UN: ${item['unidade']}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                ),
        ),
      ],
    );
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
          ),
        ],
      ),
    );
  }"""

replacement = """                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Qtd: $qtd  |  Unit: R\\$ ${preco.toStringAsFixed(2)}  |  Total: R\\$ ${(qtd * preco).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('NCM: ${item['ncm']}  |  CFOP: ${item['cfop']}  |  UN: ${item['unidade']}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Editar
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
                              tooltip: 'Editar item',
                              onPressed: () => _editarItem(idx),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                              tooltip: 'Remover',
                              onPressed: () => setState(() => _itens.removeAt(idx)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _editarItem(int idx) {
    final item = _itens[idx];
    final qtdCtrl = TextEditingController(text: (item['qtd'] as double).toString());
    final precoCtrl = TextEditingController(text: (item['preco'] as double).toStringAsFixed(2));
    final ncmCtrl = TextEditingController(text: item['ncm'] ?? '00000000');
    final cfopCtrl = TextEditingController(text: item['cfop'] ?? '5102');
    final unCtrl = TextEditingController(text: item['unidade'] ?? 'UN');
    final descCtrl = TextEditingController(text: item['descricao'] ?? (item['produto'] as Produto).nome);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Editar Item', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Descrição')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: qtdCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Quantidade'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: precoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Preço Unit.'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: ncmCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('NCM'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: cfopCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('CFOP'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: unCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Unidade'))),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() {
                _itens[idx] = {
                  ..._itens[idx],
                  'qtd': double.tryParse(qtdCtrl.text.replaceAll(',', '.')) ?? item['qtd'],
                  'preco': double.tryParse(precoCtrl.text.replaceAll(',', '.')) ?? item['preco'],
                  'ncm': ncmCtrl.text.trim(),
                  'cfop': cfopCtrl.text.trim(),
                  'unidade': unCtrl.text.trim(),
                  'descricao': descCtrl.text.trim(),
                };
              });
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // ─── ABA 3: IMPOSTOS ────────────────────────────────────
  Widget _buildTabImpostos() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONFIGURAÇÃO TRIBUTÁRIA (aplicada a todos os itens)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          const Text('Preencha conforme o regime tributário da empresa. Deixe em branco o que não se aplicar.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),

          // ICMS
          const Text('ICMS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _csosnCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CSOSN (Simples)', hint: 'Ex: 400'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _icmsCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST ICMS (Lucro Real)', hint: 'Ex: 00, 40'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _icmsAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota ICMS %', hint: '0.00'))),
          ]),
          const SizedBox(height: 20),

          // PIS / COFINS
          const Text('PIS / COFINS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _pisCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST PIS', hint: 'Ex: 07 (isento), 01'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _cofinsCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST COFINS', hint: 'Ex: 07 (isento), 01'))),
          ]),
          const SizedBox(height: 20),

          // IPI (opcional)
          const Text('IPI (opcional)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _ipiCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST IPI', hint: 'Ex: 53'))),
            const Expanded(flex: 2, child: SizedBox()),
          ]),
          const SizedBox(height: 20),

          // Despesas Acessórias
          const Text('DESPESAS E ACRÉSCIMOS GLOBAIS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _freteValorCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Valor do Frete (R$)', hint: '0.00'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _seguroValorCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Valor do Seguro (R$)', hint: '0.00'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _outrasDespCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Outras Despesas (R$)', hint: '0.00'))),
          ]),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blueAccent, size: 16), SizedBox(width: 6), Text('Referência rápida', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13))]),
                SizedBox(height: 8),
                Text('• Simples Nacional: use CSOSN (400 = tributado sem crédito, 102 = tributado sem ICMS)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('• Lucro Presumido/Real: use CST ICMS (00 = tributado, 40 = isento, 41 = não tributado)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('• PIS/COFINS isentos: CST 07 | tributados: CST 01 (cumulativo) ou 50 (não cumulativo)', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }"""

if target in content:
    content = content.replace(target, replacement)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("PATCH_APLICADO_COM_SUCESSO")
else:
    # Tenta substituição com normalização de quebras de linha
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(normalized_content)
        print("PATCH_APLICADO_COM_SUCESSO_NORMALIZADO")
    else:
        print("ALVO_NAO_ENCONTRADO")

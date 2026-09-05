import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Injetar o método _solicitarSenhaMaster e _desfaturarRegistro no _NfePageState ---
# Logo abaixo de _obterOrigemDinamica
target_manual = """  void _abrirFaturamentoManual({"""

replacement_manual = """  void _solicitarSenhaMaster({
    required BuildContext context,
    required String titulo,
    required String mensagem,
    required VoidCallback onConfirmar,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    final senhaDefinida = empresa?.configuracoes?['senha_admin']?.toString() ?? '';

    if (senhaDefinida.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Configure uma Senha Master Admin nas configurações da empresa para liberar o desfaturamento.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Senha Master Admin',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (controller.text.trim() == senhaDefinida.trim()) {
                Navigator.pop(ctx);
                onConfirmar();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Senha Master Incorreta.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _desfaturarRegistro(String id, String numero, DataService dataService) async {
    // 1. Procurar NF-e associada
    NFCe? nfeAssociada;
    try {
      nfeAssociada = dataService.nfces.firstWhere(
        (n) => n.vendaId == id || n.vendaNumero == numero,
      );
    } catch (_) {}

    if (nfeAssociada != null) {
      // Desvincular e cancelar nota fiscal local/Supabase
      final nfeAtualizada = nfeAssociada.copyWith(
        vendaId: null,
        vendaNumero: null,
        status: 'cancelada',
      );
      await dataService.atualizarNFCe(nfeAtualizada);

      // 2. Procurar e remover Conta a Receber correspondente
      try {
        final contas = dataService.contasPagar.where(
          (c) => c.numero == 'CR-' + nfeAssociada!.numero.toString() || c.descricao.contains('NF-e Nº ' + nfeAssociada.numero.toString()),
        ).toList();
        for (var c in contas) {
          dataService.deleteContaPagar(c.id);
        }
      } catch (_) {}
    }
  }

  void _abrirFaturamentoManual({"""

if target_manual in content:
    content = content.replace(target_manual, replacement_manual)
    print("METODOS_DESFATURAR_INJETADOS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_manual.replace("\r\n", "\n")
    normalized_replacement = replacement_manual.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("METODOS_DESFATURAR_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_METODOS_DESFATURAR")


# --- 2. Injetar o botão Desfaturar na renderização dos faturados na modal ---
target_trailing = """                                      trailing: Container(
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
                                      ),"""

replacement_trailing = """                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
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
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
                                            tooltip: 'Desfaturar (Exige Senha Master)',
                                            onPressed: () {
                                              _solicitarSenhaMaster(
                                                context: context,
                                                titulo: 'Desfaturar Venda/Pedido',
                                                mensagem: 'Tem certeza que deseja desfaturar a ' + item['tipo'] + ' Nº ' + item['numero'] + '? A nota correspondente será desvinculada e o recebível deletado.',
                                                onConfirmar: () async {
                                                  await _desfaturarRegistro(id, item['numero'], dataService);
                                                  setDialogState(() {
                                                    item['faturado'] = false;
                                                  });
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('✓ Registro desfaturado com sucesso!'), backgroundColor: Colors.green),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      ),"""

if target_trailing in content:
    content = content.replace(target_trailing, replacement_trailing)
    print("BOTAO_DESFATURAR_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_trailing.replace("\r\n", "\n")
    normalized_replacement = replacement_trailing.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("BOTAO_DESFATURAR_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_BOTAO_DESFATURAR")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

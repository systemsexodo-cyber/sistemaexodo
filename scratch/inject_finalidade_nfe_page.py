import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """  Widget _buildTabDestinatario() {
    final clientes = widget.dataService.clientes
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Busca rápida de cliente"""

replacement = """  Widget _buildTabDestinatario() {
    final clientes = widget.dataService.clientes
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── DADOS DA OPERAÇÃO ───
          const Text('DADOS DA OPERAÇÃO (NF-e)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _finalidade,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Finalidade de Emissão'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 – Normal')),
                  DropdownMenuItem(value: 4, child: Text('4 – Devolução')),
                ],
                onChanged: (v) {
                  setState(() {
                    _finalidade = v!;
                    if (_finalidade == 4) {
                      _natOpCtrl.text = 'DEVOLUCAO DE MERCADORIA';
                    } else {
                      _natOpCtrl.text = 'VENDA DE MERCADORIA';
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _natOpCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Natureza da Operação', hint: 'Ex: VENDA, DEVOLUCAO'),
              ),
            ),
          ]),
          if (_finalidade == 4) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _chaveRefCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              maxLength: 44,
              decoration: _dec('Chave de Acesso Referenciada *', hint: 'Chave de 44 dígitos da nota original'),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),

          // Busca rápida de cliente"""

if target in content:
    content = content.replace(target, replacement)
    print("FINALIDADE_INJETADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("FINALIDADE_INJETADA_NORMALIZADA")
    else:
        print("ALVO_FINALIDADE_NAO_ENCONTRADO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

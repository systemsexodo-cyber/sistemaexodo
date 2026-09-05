import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = "  // ─── EMISSÃO ─────────────────────────────────────────────"

transporte_code = """  // ─── ABA 4: TRANSPORTE ────────────────────────────────────
  Widget _buildTabTransporte() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DADOS DE TRANSPORTE E FRETE', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          const Text('Preencha as informações da transportadora e do frete se aplicável.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),

          // Modalidade de Frete
          DropdownButtonFormField<String>(
            value: _modFrete,
            dropdownColor: const Color(0xFF1E1E2E),
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Modalidade do Frete'),
            items: const [
              DropdownMenuItem(value: '0', child: Text('0 – Remetente (CIF)')),
              DropdownMenuItem(value: '1', child: Text('1 – Destinatário (FOB)')),
              DropdownMenuItem(value: '2', child: Text('2 – Terceiros')),
              DropdownMenuItem(value: '3', child: Text('3 – Próprio por conta do Remetente')),
              DropdownMenuItem(value: '4', child: Text('4 – Próprio por conta do Destinatário')),
              DropdownMenuItem(value: '9', child: Text('9 – Sem Ocorrência de Transporte')),
            ],
            onChanged: (v) => setState(() => _modFrete = v!),
          ),
          const SizedBox(height: 20),

          if (_modFrete != '9') ...[
            // Transportadora
            const Text('TRANSPORTADORA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: _transpNomeCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Razão Social / Nome'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpCnpjCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('CNPJ / CPF'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: _transpEndCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Logradouro / Endereço'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpInscEstCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Inscrição Estadual'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _transpMunicipioCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Município'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpUfCtrl, style: const TextStyle(color: Colors.white), maxLength: 2, decoration: _dec('UF'))),
            ]),
            const SizedBox(height: 20),

            // Veículo
            const Text('VEÍCULO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _transpPlacaCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Placa do Veículo'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpPlacaUfCtrl, style: const TextStyle(color: Colors.white), maxLength: 2, decoration: _dec('UF da Placa'))),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 20),

            // Volumes e Pesos
            const Text('VOLUMES E PESOS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _transpQtdVolCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('Quantidade de Volumes'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpEspecieVolCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Espécie (ex: Caixa, Palete)'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _transpPesoBVolCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Peso Bruto (kg)'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpPesoLVolCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Peso Líquido (kg)'))),
            ]),
          ],
        ],
      ),
    );
  }

"""

if target in content:
    content = content.replace(target, transporte_code + "\n" + target)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("TRANSPORTE_INJETADO_COM_SUCESSO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, transporte_code + "\n" + normalized_target)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(normalized_content)
        print("TRANSPORTE_INJETADO_NORMALIZADO")
    else:
        print("ALVO_EMISSAO_NAO_ENCONTRADO")

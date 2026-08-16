import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Declarar os novos controladores de destaque de ICMS ---
target_ctrls = """  // ── Impostos globais (aplicados a todos os itens por padrão) ──
  final _csosnCtrl = TextEditingController(text: '400');
  final _icmsCstCtrl = TextEditingController();
  final _pisCstCtrl = TextEditingController(text: '07');
  final _cofinsCstCtrl = TextEditingController(text: '07');
  final _icmsAliqCtrl = TextEditingController(text: '0.00');
  final _ipiCstCtrl = TextEditingController();"""

replacement_ctrls = """  // ── Impostos globais (aplicados a todos os itens por padrão) ──
  final _csosnCtrl = TextEditingController(text: '400');
  final _icmsCstCtrl = TextEditingController();
  final _pisCstCtrl = TextEditingController(text: '07');
  final _cofinsCstCtrl = TextEditingController(text: '07');
  final _icmsAliqCtrl = TextEditingController(text: '0.00');
  final _ipiCstCtrl = TextEditingController();

  // Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002 / CSOSN 900)
  final _icmsReducaoBcCtrl = TextEditingController(text: '0.00');
  final _icmsBaseCalculoCtrl = TextEditingController(text: '0.00');
  final _icmsValorCtrl = TextEditingController(text: '0.00');
  final _creditoAliqCtrl = TextEditingController(text: '0.00');
  final _creditoValorCtrl = TextEditingController(text: '0.00');
  bool _destacarIcmsNormalVal = false;"""

if target_ctrls in content:
    content = content.replace(target_ctrls, replacement_ctrls)
    print("CONTROLADORES_INJETADOS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_ctrls.replace("\r\n", "\n")
    normalized_replacement = replacement_ctrls.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CONTROLADORES_NORMALIZADOS")
    else:
        print("FALHA_AO_INJETAR_CONTROLADORES")


# --- 2. Injetar o dispose de todos os novos controladores ---
target_dispose = """    _buscaController.dispose();
    _serieController.dispose();
    _numeroController.dispose();
    super.dispose();"""

replacement_dispose = """    _buscaController.dispose();
    _serieController.dispose();
    _numeroController.dispose();
    _icmsReducaoBcCtrl.dispose();
    _icmsBaseCalculoCtrl.dispose();
    _icmsValorCtrl.dispose();
    _creditoAliqCtrl.dispose();
    _creditoValorCtrl.dispose();
    super.dispose();"""

if target_dispose in content:
    content = content.replace(target_dispose, replacement_dispose)
    print("DISPOSE_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_dispose.replace("\r\n", "\n")
    normalized_replacement = replacement_dispose.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DISPOSE_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_DISPOSE")


# --- 3. Atualizar a lógica do onChanged do seletor de finalidade para setar Base de Cálculo default do ICMS ---
target_finalidade_onchanged = """                        onChanged: (val) {
                          setDialogState(() {
                            _finalidade = int.tryParse(val ?? '1') ?? 1;
                            if (_finalidade == 4) {"""

# Vamos criar um método auxiliar para calcular os impostos dinamicamente quando a BC ou alíquotas mudarem
# e atualizar o _buildTabImpostos na UI.

# --- 4. Redesenhar a interface do _buildTabImpostos com destaque e cálculos automáticos ---
target_tab_impostos = """  // ─── ABA 3: IMPOSTOS ────────────────────────────────────
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
          const SizedBox(height: 20),"""

replacement_tab_impostos = """  // Método auxiliar para recalcular base e valores tributáveis do Simples Nacional / CSOSN 900
  void _recalcularValoresFiscais() {
    final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? _total;
    if (_icmsBaseCalculoCtrl.text.isEmpty || _icmsBaseCalculoCtrl.text == '0.00') {
      _icmsBaseCalculoCtrl.text = _total.toStringAsFixed(2);
    }
    
    // 1. Recalcular ICMS destacado
    final double aliqIcms = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (aliqIcms > 0.0) {
      final double valIcms = bc * (aliqIcms / 100.0);
      _icmsValorCtrl.text = valIcms.toStringAsFixed(2);
    } else {
      _icmsValorCtrl.text = '0.00';
    }

    // 2. Recalcular Crédito do Simples Nacional
    final double aliqCred = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (aliqCred > 0.0) {
      final double valCred = bc * (aliqCred / 100.0);
      _creditoValorCtrl.text = valCred.toStringAsFixed(2);
    } else {
      _creditoValorCtrl.text = '0.00';
    }
  }

  // ─── ABA 3: IMPOSTOS ────────────────────────────────────
  Widget _buildTabImpostos() {
    // Inicializar a base de cálculo se estiver vazia
    if (_icmsBaseCalculoCtrl.text == '0.00' || _icmsBaseCalculoCtrl.text.isEmpty) {
      _icmsBaseCalculoCtrl.text = _total.toStringAsFixed(2);
    }

    return StatefulBuilder(
      builder: (context, setStateImpostos) {
        // Listeners para auto-cálculos ao digitar
        _icmsBaseCalculoCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliqIcms = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliqCred = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          
          if (aliqIcms > 0.0) {
            _icmsValorCtrl.text = (bc * (aliqIcms / 100.0)).toStringAsFixed(2);
          }
          if (aliqCred > 0.0) {
            _creditoValorCtrl.text = (bc * (aliqCred / 100.0)).toStringAsFixed(2);
          }
        });

        _icmsAliqCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliq = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          _icmsValorCtrl.text = (bc * (aliq / 100.0)).toStringAsFixed(2);
        });

        _creditoAliqCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliq = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          _creditoValorCtrl.text = (bc * (aliq / 100.0)).toStringAsFixed(2);
        });

        final bool isCsosn900 = _csosnCtrl.text.trim() == '900';

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
                Expanded(
                  child: TextField(
                    controller: _csosnCtrl, 
                    keyboardType: TextInputType.number, 
                    style: const TextStyle(color: Colors.white), 
                    decoration: _dec('CSOSN (Simples)', hint: 'Ex: 400'),
                    onChanged: (val) {
                      setStateImpostos(() {});
                    },
                  )
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _icmsCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST ICMS (Lucro Real)', hint: 'Ex: 00, 40'))),
              ]),
              const SizedBox(height: 20),

              // Destaque de ICMS Normal para Simples Nacional (Exigido no CSOSN 900)
              if (isCsosn900) ...[
                Row(
                  children: [
                    Checkbox(
                      value: _destacarIcmsNormalVal,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) {
                        setStateImpostos(() {
                          _destacarIcmsNormalVal = val ?? false;
                        });
                      },
                    ),
                    const Text(
                      'Destaca ICMS Normal (Exigido para CSOSN 900)',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_destacarIcmsNormalVal) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13131A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Destaque do ICMS Normal', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _icmsReducaoBcCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('% Redução BC', hint: '0.00'))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: _icmsBaseCalculoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Base de Cálculo', hint: '0.00'))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _icmsAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota ICMS %', hint: '0.00'))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: _icmsValorCtrl, readOnly: true, style: const TextStyle(color: Colors.greenAccent), decoration: _dec('Valor do ICMS R$', hint: '0.00'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Crédito do Simples Nacional
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Crédito Simples Nacional', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _creditoAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota Crédito %', hint: 'Ex: 1.25'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _creditoValorCtrl, readOnly: true, style: const TextStyle(color: Colors.greenAccent), decoration: _dec('Valor do Crédito R$', hint: '0.00'))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: TextField(controller: _icmsAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota ICMS %', hint: '0.00'))),
                  ],
                ),
                const SizedBox(height: 20),
              ],"""

if target_tab_impostos in content:
    content = content.replace(target_tab_impostos, replacement_tab_impostos)
    print("TAB_IMPOSTOS_UI_ATUALIZADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_tab_impostos.replace("\r\n", "\n")
    normalized_replacement = replacement_tab_impostos.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("TAB_IMPOSTOS_UI_NORMALIZADA")
    else:
        print("FALHA_AO_ATUALIZAR_TAB_IMPOSTOS_UI")


# --- 5. Passar os novos parâmetros de destaque de ICMS na chamada manual de service.emitir ---
target_emitir_manual_call = """        destEmail: _emailDestCtrl.text.trim(),
        // ─── Novos campos de Devolução, Impostos e Transporte ───
        finalidade: _finalidade,
        naturezaOperacao: _natOpCtrl.text.trim(),
        chaveReferenciada: _finalidade == 4 ? _chaveRefCtrl.text.trim() : null,
        valorFrete: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        valorSeguro: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesas: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,
        modFrete: int.tryParse(_modFrete) ?? 9,
        transpNome: _transpNomeCtrl.text.trim().isNotEmpty ? _transpNomeCtrl.text.trim() : null,
        transpCnpjCpf: _transpCnpjCtrl.text.trim().isNotEmpty ? _transpCnpjCtrl.text.trim() : null,
        transpInscEst: _transpInscEstCtrl.text.trim().isNotEmpty ? _transpInscEstCtrl.text.trim() : null,
        transpEndereco: _transpEndCtrl.text.trim().isNotEmpty ? _transpEndCtrl.text.trim() : null,
        transpMunicipio: _transpMunicipioCtrl.text.trim().isNotEmpty ? _transpMunicipioCtrl.text.trim() : null,
        transpUf: _transpUfCtrl.text.trim().isNotEmpty ? _transpUfCtrl.text.trim() : null,
        transpPlaca: _transpPlacaCtrl.text.trim().isNotEmpty ? _transpPlacaCtrl.text.trim() : null,
        transpPlacaUf: _transpPlacaUfCtrl.text.trim().isNotEmpty ? _transpPlacaUfCtrl.text.trim() : null,
        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
        vendaId: vId,
        vendaNumero: vNum,
      );"""

# Mapear e calcular os destaques com base no estado do checkbox
replacement_emitir_manual_call = """        destEmail: _emailDestCtrl.text.trim(),
        // ─── Novos campos de Devolução, Impostos e Transporte ───
        finalidade: _finalidade,
        naturezaOperacao: _natOpCtrl.text.trim(),
        chaveReferenciada: _finalidade == 4 ? _chaveRefCtrl.text.trim() : null,
        valorFrete: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        valorSeguro: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesas: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,
        modFrete: int.tryParse(_modFrete) ?? 9,
        transpNome: _transpNomeCtrl.text.trim().isNotEmpty ? _transpNomeCtrl.text.trim() : null,
        transpCnpjCpf: _transpCnpjCtrl.text.trim().isNotEmpty ? _transpCnpjCtrl.text.trim() : null,
        transpInscEst: _transpInscEstCtrl.text.trim().isNotEmpty ? _transpInscEstCtrl.text.trim() : null,
        transpEndereco: _transpEndCtrl.text.trim().isNotEmpty ? _transpEndCtrl.text.trim() : null,
        transpMunicipio: _transpMunicipioCtrl.text.trim().isNotEmpty ? _transpMunicipioCtrl.text.trim() : null,
        transpUf: _transpUfCtrl.text.trim().isNotEmpty ? _transpUfCtrl.text.trim() : null,
        transpPlaca: _transpPlacaCtrl.text.trim().isNotEmpty ? _transpPlacaCtrl.text.trim() : null,
        transpPlacaUf: _transpPlacaUfCtrl.text.trim().isNotEmpty ? _transpPlacaUfCtrl.text.trim() : null,
        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
        vendaId: vId,
        vendaNumero: vNum,
        
        // Parâmetros tributários de Destaque de ICMS e Crédito
        icmsReducaoBc: _destacarIcmsNormalVal ? (double.tryParse(_icmsReducaoBcCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        icmsBaseCalculo: _destacarIcmsNormalVal ? (double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        icmsAliquota: double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0,
        icmsValor: _destacarIcmsNormalVal ? (double.tryParse(_icmsValorCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        creditoAliquota: _csosnCtrl.text.trim() == '900' ? (double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        creditoValor: _csosnCtrl.text.trim() == '900' ? (double.tryParse(_creditoValorCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
      );"""

if target_emitir_manual_call in content:
    content = content.replace(target_emitir_manual_call, replacement_emitir_manual_call)
    print("EMITIR_MANUAL_CALL_ATUALIZADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_emitir_manual_call.replace("\r\n", "\n")
    normalized_replacement = replacement_emitir_manual_call.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("EMITIR_MANUAL_CALL_NORMALIZADA")
    else:
        print("FALHA_AO_ATUALIZAR_EMITIR_MANUAL_CALL")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

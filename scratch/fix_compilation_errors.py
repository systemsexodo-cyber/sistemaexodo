import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Corrigir o dispose do _NfePageState ---
target_dispose_nfe = """  @override
  void dispose() {
    _buscaController.dispose();
    _serieController.dispose();
    _numeroController.dispose();
    _icmsReducaoBcCtrl.dispose();
    _icmsBaseCalculoCtrl.dispose();
    _icmsValorCtrl.dispose();
    _creditoAliqCtrl.dispose();
    _creditoValorCtrl.dispose();
    super.dispose();
  }"""

replacement_dispose_nfe = """  @override
  void dispose() {
    _buscaController.dispose();
    _serieController.dispose();
    _numeroController.dispose();
    super.dispose();
  }"""

if target_dispose_nfe in content:
    content = content.replace(target_dispose_nfe, replacement_dispose_nfe)
    print("DISPOSE_NFE_PAGE_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_dispose_nfe.replace("\r\n", "\n")
    normalized_replacement = replacement_dispose_nfe.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DISPOSE_NFE_PAGE_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_DISPOSE_NFE_PAGE")


# --- 2. Adicionar os novos controladores no dispose do _EmissaoManualPageState ---
target_dispose_emissao = """      _transpMunicipioCtrl, _transpUfCtrl, _transpPlacaCtrl, _transpPlacaUfCtrl,
      _transpQtdVolCtrl, _transpEspecieVolCtrl, _transpPesoBVolCtrl, _transpPesoLVolCtrl,
    ]) c.dispose();"""

replacement_dispose_emissao = """      _transpMunicipioCtrl, _transpUfCtrl, _transpPlacaCtrl, _transpPlacaUfCtrl,
      _transpQtdVolCtrl, _transpEspecieVolCtrl, _transpPesoBVolCtrl, _transpPesoLVolCtrl,
      _icmsReducaoBcCtrl, _icmsBaseCalculoCtrl, _icmsValorCtrl, _creditoAliqCtrl, _creditoValorCtrl,
    ]) c.dispose();"""

if target_dispose_emissao in content:
    content = content.replace(target_dispose_emissao, replacement_dispose_emissao)
    print("DISPOSE_EMISSAO_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_dispose_emissao.replace("\r\n", "\n")
    normalized_replacement = replacement_dispose_emissao.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DISPOSE_EMISSAO_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_DISPOSE_EMISSAO")


# --- 3. Corrigir o final do _buildTabImpostos fechando o StatefulBuilder ---
# O fechamento incorreto está no final do método, imediatamente antes do _buildTabTransporte()
target_end_impostos = """          ),
        ],
      ),
    );
  }

  // ─── ABA 4: TRANSPORTE ────────────────────────────────────"""

replacement_end_impostos = """          ),
        ],
      ),
    );
      },
    );
  }

  // ─── ABA 4: TRANSPORTE ────────────────────────────────────"""

if target_end_impostos in content:
    content = content.replace(target_end_impostos, replacement_end_impostos)
    print("END_IMPOSTOS_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_end_impostos.replace("\r\n", "\n")
    normalized_replacement = replacement_end_impostos.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("END_IMPOSTOS_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_END_IMPOSTOS")


# --- 4. Escapar os cifrões nas duas strings de destaque de ICMS ---
content = content.replace("decoration: _dec('Valor do ICMS R$', hint: '0.00')", "decoration: _dec('Valor do ICMS R\\$', hint: '0.00')")
content = content.replace("decoration: _dec('Valor do Crédito R$', hint: '0.00')", "decoration: _dec('Valor do Crédito R\\$', hint: '0.00')")
print("CIFROES_ESCAPADOS")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

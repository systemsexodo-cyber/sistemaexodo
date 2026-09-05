import os
import re

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar lógica de Auto-Preenchimento e Mudança de CFOPs ao trocar a finalidade ---
# Localizar o onChanged da Finalidade de Emissão
old_onchanged_finalidade = """                onChanged: (v) {
                  setState(() {
                    _finalidade = v!;
                    if (_finalidade == 4) {
                      _natOpCtrl.text = 'DEVOLUCAO DE MERCADORIA';
                    } else {
                      _natOpCtrl.text = 'VENDA DE MERCADORIA';
                    }
                  });
                },"""

new_onchanged_finalidade = """                onChanged: (v) {
                  setState(() {
                    _finalidade = v!;
                    if (_finalidade == 4) {
                      _natOpCtrl.text = 'DEVOLUCAO DE MERCADORIA';
                      _csosnCtrl.text = '900'; // Geralmente usado para devoluções
                      // Mudar CFOP dos itens existentes para Devolução (Ex: 5102 -> 5202)
                      for (var item in _itens) {
                        String cfopOriginal = item['cfop'] ?? '5102';
                        if (cfopOriginal == '5102' || cfopOriginal == '5101') {
                          item['cfop'] = '5202';
                        } else if (cfopOriginal == '6102' || cfopOriginal == '6101') {
                          item['cfop'] = '6202';
                        }
                      }
                      _cfopCtrl.text = '5202'; // Padrão para novos itens
                    } else {
                      _natOpCtrl.text = 'VENDA DE MERCADORIA';
                      _csosnCtrl.text = '400';
                      for (var item in _itens) {
                        String cfopOriginal = item['cfop'] ?? '5202';
                        if (cfopOriginal == '5202' || cfopOriginal == '5201') {
                          item['cfop'] = '5102';
                        } else if (cfopOriginal == '6202' || cfopOriginal == '6201') {
                          item['cfop'] = '6102';
                        }
                      }
                      _cfopCtrl.text = '5102';
                    }
                  });
                },"""

if old_onchanged_finalidade in content:
    content = content.replace(old_onchanged_finalidade, new_onchanged_finalidade)
    print("LOGICA_FINALIDADE_ATUALIZADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_onchanged_finalidade.replace("\r\n", "\n")
    normalized_new = new_onchanged_finalidade.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("LOGICA_FINALIDADE_ATUALIZADA_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_ONCHANGED_FINALIDADE")


# --- 2. Adicionar o display de resumo e auto-calculo de impostos destacados no bottom da tela ---
# Vamos procurar o bottomNavigationBar que exibe o total:
old_bottom_total = """            Text(
              'Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R$').format(_total)}',
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),"""

# Vamos trocar por um resumo fiscal inteligente com base de cálculo e impostos estimados em tempo real
new_bottom_total = """            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ICMS Estimado: R$ ${( _total * (double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0) / 100 ).toStringAsFixed(2)}  ',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    if (double.tryParse(_freteValorCtrl.text) != null && double.tryParse(_freteValorCtrl.text)! > 0)
                      Text(
                        'Frete: R$ ${double.tryParse(_freteValorCtrl.text)!.toStringAsFixed(2)}  ',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
                Text(
                  'Total Geral: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R$').format(_total + (double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0))}',
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),"""

if old_bottom_total in content:
    content = content.replace(old_bottom_total, new_bottom_total)
    print("BOTTOM_TOTAL_FISCAL_ESTIMADO_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_bottom_total.replace("\r\n", "\n")
    normalized_new = new_bottom_total.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("BOTTOM_TOTAL_FISCAL_ESTIMADO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_BOTTOM_TOTAL")


# --- 3. Adicionar validações fiscais completas pré-emissão no método _emitir ---
old_validacoes = """  Future<void> _emitir(AuthService authService) async {
    // Validações
    if (_nomeDestCtrl.text.trim().isEmpty || _docDestCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Preencha Nome e CPF/CNPJ do destinatário.'), backgroundColor: Colors.orange));
      return;
    }
    if (_logradouroCtrl.text.trim().isEmpty || _municipioCtrl.text.trim().isEmpty || _ufCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Preencha o endereço completo do destinatário (Logradouro, Município, UF).'), backgroundColor: Colors.orange));
      return;
    }
    if (_itens.isEmpty) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Adicione pelo menos um item.'), backgroundColor: Colors.orange));
      return;
    }"""

new_validacoes = """  Future<void> _emitir(AuthService authService) async {
    // Validações Inteligentes Avançadas (Evita Rejeição da SEFAZ)
    if (_nomeDestCtrl.text.trim().isEmpty || _docDestCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Preencha Nome e CPF/CNPJ do destinatário.'), backgroundColor: Colors.orange));
      return;
    }
    
    // CNPJ/CPF Destinatário Limpo
    final docLimpo = _docDestCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (docLimpo.length != 11 && docLimpo.length != 14) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ CPF/CNPJ do destinatário inválido.'), backgroundColor: Colors.orange));
      return;
    }

    if (_logradouroCtrl.text.trim().isEmpty || _municipioCtrl.text.trim().isEmpty || _ufCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ O endereço do destinatário é obrigatório e deve estar completo (Rua, Cidade, UF).'), backgroundColor: Colors.orange));
      return;
    }
    if (_cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length != 8) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ CEP do destinatário deve conter 8 dígitos.'), backgroundColor: Colors.orange));
      return;
    }

    // Validação de Devolução
    if (_finalidade == 4) {
      final chaveRef = _chaveRefCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (chaveRef.isEmpty) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Nota de Devolução exige a Chave de Acesso Referenciada.'), backgroundColor: Colors.orange));
        return;
      }
      if (chaveRef.length != 44) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ A Chave de Acesso Referenciada deve ter exatamente 44 dígitos (atual: ' + chaveRef.length.toString() + ').'), backgroundColor: Colors.orange));
        return;
      }
    }

    if (_itens.isEmpty) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Adicione pelo menos um item à nota.'), backgroundColor: Colors.orange));
      return;
    }"""

if old_validacoes in content:
    content = content.replace(old_validacoes, new_validacoes)
    print("VALIDACOES_EMITIR_ATUALIZADAS")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_validacoes.replace("\r\n", "\n")
    normalized_new = new_validacoes.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("VALIDACOES_EMITIR_ATUALIZADAS_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_VALIDACOES_EMITIR")


with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("TODAS_AUTOMACOES_FISCAIS_SALVAS")

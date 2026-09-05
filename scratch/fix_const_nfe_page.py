import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """      if (chaveRef.length != 44) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ A Chave de Acesso Referenciada deve ter exatamente 44 dígitos (atual: ' + chaveRef.length.toString() + ').'), backgroundColor: Colors.orange));
        return;
      }"""

# Remove o 'const' do SnackBar e do Text para permitir string dinâmica
replacement = """      if (chaveRef.length != 44) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ A Chave de Acesso Referenciada deve ter exatamente 44 dígitos (atual: ${chaveRef.length}).'), backgroundColor: Colors.orange));
        return;
      }"""

if target in content:
    content = content.replace(target, replacement)
    print("CONST_SNACKBAR_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CONST_SNACKBAR_CORRIGIDO_NORMALIZADO")
    else:
        print("FALHA_AO_ENCONTRAR_CONST_SNACKBAR")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

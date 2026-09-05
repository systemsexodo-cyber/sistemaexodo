#!/usr/bin/env python3
"""
Correção: Salvar vendas imediatamente (sem debounce de 15s)
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 70)
print("Corrigindo addVendaBalcao - Salvar imediatamente")
print("=" * 70)

# Procurar o método addVendaBalcao e adicionar salvamento imediato
old_add_venda = """  Future<void> addVendaBalcao(VendaBalcao venda) async {
    _vendasBalcao.add(venda);
    print('✓ Venda ${venda.numero} (ID: ${venda.id}) salva em memória @ ${DateTime.now()}');"""

new_add_venda = """  Future<void> addVendaBalcao(VendaBalcao venda) async {
    _vendasBalcao.add(venda);
    print('✓ Venda ${venda.numero} (ID: ${venda.id}) salva em memória @ ${DateTime.now()}');
    
    // SALVAR IMEDIATAMENTE NO LOCALSTORAGE (crítico: vendas não podem esperar debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyVendasBalcao),
        _vendasBalcao,
      );
      print('>>> ✅ Venda ${venda.numero} salva no SQLite imediatamente');
    } catch (e) {
      print('>>> ⚠️ Erro ao salvar venda no SQLite: $e');
    }"""

if old_add_venda in content:
    content = content.replace(old_add_venda, new_add_venda)
    print("✅ Salvamento imediato adicionado ao addVendaBalcao")
else:
    print("⚠️ Padrão não encontrado")

# Também verificar se _getChaveComEmpresa existe
if "_getChaveComEmpresa" not in content:
    print("⚠️ _getChaveComEmpresa não encontrado - verificar método")
else:
    print("✅ _getChaveComEmpresa existe")

with open('lib/services/data_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Arquivo salvo!")
print("=" * 70)

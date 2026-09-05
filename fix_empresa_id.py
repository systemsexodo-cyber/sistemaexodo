#!/usr/bin/env python3
"""
Correção definitiva para empresa_id em _upsertNoSupabase
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Corrigindo _upsertNoSupabase")
print("=" * 60)

# Encontrar o método
start = content.find('Future<void> _upsertNoSupabase')
if start == -1:
    print("❌ Método não encontrado")
    exit()

end = content.find('  }', start)
if end == -1:
    end = content.find('}', start)

old_method = content[start:end+1]
print("Método atual:")
print(old_method)
print("-" * 40)

# Verificar se já foi corrigido
if "if (!map.containsKey('empresa_id'))" in old_method:
    print("⚠️ Método ainda tem verificação antiga, corrigindo...")
    
    # Substituir apenas a parte interna do método
    new_method = """Future<void> _upsertNoSupabase(String table, Map<String, dynamic> data) async {
    if (!SupabaseService.isAvailable || _empresaIdAtual == null) return;

    try {
      final map = Map<String, dynamic>.from(data);
      // SEMPRE definir empresa_id para garantir RLS funcione corretamente
      map['empresa_id'] = _empresaIdAtual;
      await _supabaseService.upsert(table, map);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro no upsert em $table: $e');
    }
  }"""
    
    content = content[:start] + new_method + content[end+1:]
    
    with open('lib/services/data_service.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✅ Método corrigido!")
else:
    print("✅ Método já está correto (ou formato diferente)")

print("=" * 60)

#!/usr/bin/env python3
"""
Correção para problema de RLS - empresa_id nulo ou vazio
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Corrigindo _upsertNoSupabase - empresa_id")
print("=" * 60)

# O problema é que toMap() pode retornar empresa_id: null
# E a verificação só checa containsKey, não se o valor é válido

old_upsert = """  Future<void> _upsertNoSupabase(String table, Map<String, dynamic> data) async {
    if (!SupabaseService.isAvailable || _empresaIdAtual == null) return;

    try {
      final map = Map<String, dynamic>.from(data);
      if (!map.containsKey('empresa_id')) {
        map['empresa_id'] = _empresaIdAtual;
      }
      await _supabaseService.upsert(table, map);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro no upsert em \$table: \$e');
    }
  }"""

new_upsert = """  Future<void> _upsertNoSupabase(String table, Map<String, dynamic> data) async {
    if (!SupabaseService.isAvailable || _empresaIdAtual == null) return;

    try {
      final map = Map<String, dynamic>.from(data);
      // SEMPRE definir empresa_id para garantir RLS
      // Sobrescreve mesmo se já existe (pode ser null ou valor incorreto do toMap())
      map['empresa_id'] = _empresaIdAtual;
      await _supabaseService.upsert(table, map);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro no upsert em \$table: \$e');
    }
  }"""

if old_upsert in content:
    content = content.replace(old_upsert, new_upsert)
    print("✅ _upsertNoSupabase corrigido")
else:
    print("⚠️ Padrão não encontrado")
    # Debug
    idx = content.find('_upsertNoSupabase')
    if idx != -1:
        print("Conteúdo encontrado:")
        print(content[idx:idx+400])

with open('lib/services/data_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Arquivo salvo!")
print("=" * 60)

#!/usr/bin/env python3
"""
Verificar se a correção foi aplicada
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Verificando correção _upsertNoSupabase")
print("=" * 60)

idx = content.find('_upsertNoSupabase')
if idx != -1:
    snippet = content[idx:idx+400]
    print(snippet)
    
    if "map['empresa_id'] = _empresaIdAtual;" in snippet:
        print("\n✅ Correção aplicada: empresa_id sempre definido")
    elif "containsKey('empresa_id')" in snippet:
        print("\n⚠️ Código antigo ainda presente: verificação containsKey")
    else:
        print("\n? Padrão não reconhecido")
else:
    print("❌ _upsertNoSupabase não encontrado")

print("\n" + "=" * 60)

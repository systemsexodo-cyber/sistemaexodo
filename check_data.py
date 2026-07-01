#!/usr/bin/env python3
with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=" * 60)
print("Procurando addProduto e empresa_id")
print("=" * 60)

in_add_produto = False
for i, line in enumerate(lines):
    if 'addProduto' in line and 'Future' in line:
        in_add_produto = True
        start = i
        print(f"\naddProduto encontrado na linha {i}")
    
    if in_add_produto:
        if i > start + 30:  # Limitar a 30 linhas
            break
        if 'empresa' in line.lower() or 'supabase' in line.lower() or 'toMap' in line.lower():
            print(f"  {i}: {line.rstrip()}")
        if line.strip().startswith('}') and i > start + 10:
            break

print("\n" + "=" * 60)
print("Procurando _upsertNoSupabase")
print("=" * 60)

for i, line in enumerate(lines):
    if '_upsertNoSupabase' in line and 'Future' in line:
        print(f"\n_upsertNoSupabase na linha {i}")
        for j in range(i, min(i+20, len(lines))):
            if 'empresa' in lines[j].lower() or 'supabase' in lines[j].lower():
                print(f"  {j}: {lines[j].rstrip()}")
        break

#!/usr/bin/env python3
"""
Verificar método addVendaBalcao completo e _carregarDadosSalvos
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=" * 60)
print("addVendaBalcao - método completo")
print("=" * 60)

start_idx = None
for i, line in enumerate(lines):
    if 'Future<void> addVendaBalcao' in line:
        start_idx = i
        break

if start_idx:
    # Encontrar o fim do método (próximo método ou linha vazia seguida de método)
    end_idx = start_idx
    brace_count = 0
    found_opening = False
    
    for i in range(start_idx, min(len(lines), start_idx + 200)):
        line = lines[i]
        if '{' in line:
            brace_count += line.count('{')
            found_opening = True
        if '}' in line:
            brace_count -= line.count('}')
        
        if found_opening and brace_count == 0:
            end_idx = i
            break
    
    print(f"Método das linhas {start_idx} a {end_idx}:")
    for i in range(start_idx, min(end_idx + 1, len(lines))):
        print(f"{i}: {lines[i].rstrip()}")
else:
    print("❌ Não encontrado")

print("\n" + "=" * 60)
print("_carregarDadosSalvos - buscando vendas")
print("=" * 60)

start_idx = None
for i, line in enumerate(lines):
    if '_carregarDadosSalvos' in line and 'Future' in line:
        start_idx = i
        break

if start_idx:
    # Procurar por vendasBalcao ou keyVendas no método
    print(f"_carregarDadosSalvos começa na linha {start_idx}")
    
    # Procurar por vendas nas próximas 200 linhas
    for i in range(start_idx, min(start_idx + 200, len(lines))):
        if 'vendas' in lines[i].lower() or 'venda' in lines[i].lower():
            print(f"  {i}: {lines[i].rstrip()}")
            # Contexto
            for j in range(max(start_idx, i-2), min(len(lines), i+4)):
                if j != i:
                    print(f"    {lines[j].rstrip()}")
            print("-" * 40)
else:
    print("❌ _carregarDadosSalvos não encontrado")

print("\n" + "=" * 60)
print("LocalStorageService.keyVendasBalcao")
print("=" * 60)

with open('lib/services/local_storage_service.dart', 'r', encoding='utf-8') as f:
    ls_content = f.read()
    if 'keyVendas' in ls_content:
        idx = ls_content.find('keyVendas')
        print(f"Encontrado: {ls_content[idx:idx+100]}")
    else:
        print("⚠️ keyVendas não encontrado no LocalStorageService")

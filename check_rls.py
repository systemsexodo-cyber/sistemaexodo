#!/usr/bin/env python3
"""
Verificar problema de RLS - empresa_id nos dados
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Verificando empresa_id em operações Supabase")
print("=" * 60)

# Procurar por _upsertNoSupabase chamadas
import re

# Encontrar todos os locais que chamam _upsertNoSupabase
matches = re.finditer(r'_upsertNoSupabase\(([^,]+),\s*([^)]+)\)', content)

print("\nChamadas _upsertNoSupabase:")
for i, match in enumerate(matches, 1):
    table = match.group(1)
    data = match.group(2)
    print(f"  {i}. Tabela: {table}, Dados: {data}")

# Verificar addProduto especificamente
print("\n" + "=" * 60)
print("Verificando addProduto (linha ~2230)")
print("=" * 60)

idx = content.find('Future<void> addProduto')
if idx != -1:
    snippet = content[idx:idx+800]
    lines = snippet.split('\n')
    for i, line in enumerate(lines[:40]):
        if 'supabase' in line.lower() or 'empresa' in line.lower() or 'tomap' in line.lower():
            print(f"  {i}: {line}")

# Verificar addPedido
print("\n" + "=" * 60)
print("Verificando addPedido")
print("=" * 60)

idx = content.find('Future<void> addPedido')
if idx != -1:
    snippet = content[idx:idx+800]
    lines = snippet.split('\n')
    for i, line in enumerate(lines[:40]):
        if 'supabase' in line.lower() or 'empresa' in line.lower() or 'tomap' in line.lower():
            print(f"  {i}: {line}")

# Verificar _salvarAutomaticamente
print("\n" + "=" * 60)
print("Verificando _salvarAutomaticamente")
print("=" * 60)

idx = content.find('void _salvarAutomaticamente')
if idx != -1:
    snippet = content[idx:idx+800]
    lines = snippet.split('\n')
    for i, line in enumerate(lines[:40]):
        if 'supabase' in line.lower() or 'empresa' in line.lower() or 'tomap' in line.lower():
            print(f"  {i}: {line}")

print("\n" + "=" * 60)

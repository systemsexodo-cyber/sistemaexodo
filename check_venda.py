#!/usr/bin/env python3
"""
Verificar como vendas são salvas e carregadas
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Método addVendaBalcao")
print("=" * 60)

idx = content.find('Future<void> addVendaBalcao')
if idx != -1:
    # Pegar o método completo
    snippet = content[idx:idx+1500]
    lines = snippet.split('\n')
    for i, line in enumerate(lines):
        if line.strip().startswith('}') and i > 10:
            snippet = '\n'.join(lines[:i+1])
            break
    print(snippet)
else:
    print("❌ addVendaBalcao não encontrado")

print("\n" + "=" * 60)
print("Método getVendasPorPeriodo")
print("=" * 60)

idx = content.find('getVendasPorPeriodo')
if idx != -1:
    snippet = content[idx:idx+800]
    lines = snippet.split('\n')
    for i, line in enumerate(lines):
        if line.strip().startswith('}') and i > 5:
            snippet = '\n'.join(lines[:i+1])
            break
    print(snippet)
else:
    print("❌ getVendasPorPeriodo não encontrado")

print("\n" + "=" * 60)
print("Verificando _carregarDadosSalvos - vendas")
print("=" * 60)

idx = content.find('_carregarDadosSalvos')
if idx != -1:
    # Procurar por vendas no método
    snippet = content[idx:idx+3000]
    if 'vendas' in snippet.lower():
        lines = snippet.split('\n')
        for i, line in enumerate(lines):
            if 'vendas' in line.lower():
                print(f"  {i}: {line}")
                # Mostrar contexto
                for j in range(max(0,i-2), min(len(lines), i+5)):
                    print(f"    {lines[j]}")
                print("-" * 40)
    else:
        print("⚠️ vendas não encontrado em _carregarDadosSalvos")
else:
    print("❌ _carregarDadosSalvos não encontrado")

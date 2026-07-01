#!/usr/bin/env python3
"""
Verificar addVendaBalcao completo - procurar salvamento
"""

with open('lib/services/data_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=" * 70)
print("ANÁLISE COMPLETA DO addVendaBalcao")
print("=" * 70)

start_idx = None
for i, line in enumerate(lines):
    if 'Future<void> addVendaBalcao' in line:
        start_idx = i
        break

if start_idx is None:
    print("❌ addVendaBalcao não encontrado")
    exit()

# Encontrar fim do método
end_idx = start_idx
brace_count = 0
found_opening = False

for i in range(start_idx, min(len(lines), start_idx + 300)):
    line = lines[i]
    if '{' in line:
        brace_count += line.count('{')
        found_opening = True
    if '}' in line:
        brace_count -= line.count('}')
    
    if found_opening and brace_count == 0:
        end_idx = i
        break

print(f"Método: linhas {start_idx} a {end_idx} ({end_idx - start_idx} linhas)")
print("\nConteúdo:")
print("-" * 70)

method_content = []
for i in range(start_idx, end_idx + 1):
    line = lines[i]
    method_content.append(line)
    # Destacar linhas importantes
    if any(keyword in line for keyword in ['_salvar', 'notifyListeners', '_vendasBalcao.add', 'supabase', 'upsert', '_marcarSujo']):
        print(f">>> {i}: {line.rstrip()}")
    else:
        print(f"    {i}: {line.rstrip()}")

print("-" * 70)

# Verificar se tem salvamento
method_text = ''.join(method_content)
print("\nVERIFICAÇÃO:")
print(f"  _salvarAutomaticamente(): {'✅' if '_salvarAutomaticamente' in method_text else '❌'}")
print(f"  _marcarSujo(): {'✅' if '_marcarSujo' in method_text else '❌'}")
print(f"  _upsertNoSupabase(): {'✅' if '_upsertNoSupabase' in method_text else '❌'}")
print(f"  supabase upsert direto: {'✅' if 'supabaseService.upsert' in method_text or '_supabaseService.upsert' in method_text else '❌'}")
print(f"  notifyListeners(): {'✅' if 'notifyListeners' in method_text else '❌'}")

# Verificar outros métodos de venda
print("\n" + "=" * 70)
print("OUTROS MÉTODOS DE VENDA")
print("=" * 70)

keywords = ['finalizarVenda', 'concluirVendaBalcao', 'addVenda']
for keyword in keywords:
    for i, line in enumerate(lines):
        if keyword in line and 'Future' in line:
            print(f"\n{keyword} na linha {i}:")
            print(f"  {line.rstrip()}")
            # Próximas 5 linhas
            for j in range(i+1, min(len(lines), i+6)):
                print(f"    {lines[j].rstrip()}")
            break

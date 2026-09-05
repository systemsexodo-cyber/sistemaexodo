#!/usr/bin/env python3
"""Listar todas as tabelas disponíveis no Supabase"""
import urllib.request
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

# Tabelas que vamos testar
tables_to_check = [
    'empresas', 'usuarios', 'clientes', 'produtos', 'servicos',
    'pedidos', 'ordens_servico', 'entregas', 'vendas_balcao',
    'nfces', 'romaneios', 'funcionarios'
]

print("Verificando disponibilidade de dados no Supabase:\n")

headers = {
    'Accept': 'application/json',
    'apikey': key,
    'Authorization': f'Bearer {key}'
}

tables_with_data = []

for table in tables_to_check:
    try:
        test_url = f"{url}/rest/v1/{table}?select=count&limit=1"
        req = urllib.request.Request(test_url, headers=headers)
        
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            if isinstance(data, list) and len(data) > 0:
                print(f"✅ {table}: {len(data)} registro(s)")
                tables_with_data.append(table)
            else:
                print(f"⚠️  {table}: vazio")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"❌ {table}: não existe ou sem acesso")
        else:
            print(f"❌ {table}: erro HTTP {e.code}")
    except Exception as e:
        print(f"❌ {table}: erro {type(e).__name__}")

print(f"\n{'='*50}")
print(f"Tabelas com dados: {tables_with_data}")

if not tables_with_data:
    print("\n⚠️  NENHUMA TABELA TEM DADOS!")
    print("\nPossíveis causas:")
    print("1. Supabase está completamente vazio")
    print("2. Row Level Security (RLS) está bloqueando dados")
    print("3. Chave de acesso não tem permissões suficientes")
    print("\nSolução: Usar SUPABASE_SERVICE_ROLE_KEY em vez de ANON_KEY")

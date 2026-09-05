#!/usr/bin/env python3
"""Teste de acesso ao Supabase"""
import urllib.request
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

print(f"Supabase URL: {url}")
print(f"Chave (primeiros 20 chars): {key[:20] if key else 'VAZIA'}...\n")

headers = {
    'Accept': 'application/json',
    'apikey': key,
    'Authorization': f'Bearer {key}'
}

# Testar endpoint empresas
test_url = f"{url}/rest/v1/empresas?select=*&limit=1"
req = urllib.request.Request(test_url, headers=headers)

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        print(f"✅ Conexão OK com Supabase")
        print(f"Registros encontrados: {len(data)}")
        if data:
            print(f"Colunas: {list(data[0].keys())}")
        else:
            print("⚠️  Nenhum registro retornado na tabela 'empresas'")
except Exception as e:
    print(f"❌ Erro: {type(e).__name__}: {e}")
    print("\nDicas de diagnóstico:")
    print("1. Verifique se SUPABASE_URL e SUPABASE_ANON_KEY estão corretos")
    print("2. Verifique se há dados realmente no Supabase")
    print("3. Verifique permissões RLS (Row Level Security)")
    print("4. Talvez precise da SUPABASE_SERVICE_ROLE_KEY em vez de ANON_KEY")

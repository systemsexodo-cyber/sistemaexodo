#!/usr/bin/env python3
"""Listar tabelas disponíveis na API REST do Supabase"""
import urllib.request
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

headers = {
    'Accept': 'application/json',
    'apikey': key,
}

# Endpoint que lista tabelas
schema_url = f"{url}/rest/v1/"

print("Tentando acessar informações de schema...\n")

# Método 1: Tentar acessar / para ver se há informação
print("1️⃣  GET /rest/v1/")
req = urllib.request.Request(f"{url}/rest/v1/", headers=headers)
try:
    with urllib.request.urlopen(req, timeout=5) as r:
        data = json.loads(r.read().decode())
        print(f"   Status: {r.status}")
        print(f"   Response: {json.dumps(data, indent=2)[:500]}")
except Exception as e:
    print(f"   Erro: {e}")

# Método 2: Usar OpenAPI schema
print("\n2️⃣  GET /rest/v1/?apiversion=1")
req2 = urllib.request.Request(f"{url}/rest/v1/?apiversion=1", headers=headers)
try:
    with urllib.request.urlopen(req2, timeout=5) as r:
        data = json.loads(r.read().decode())
        print(f"   Status: {r.status}")
        
        # Extrair informações de tabelas
        if 'paths' in data:
            tables = [p.lstrip('/') for p in data['paths'].keys() if p.startswith('/')]
            print(f"   Tabelas disponíveis ({len(tables)}):")
            for table in sorted(tables)[:20]:
                print(f"     - {table}")
except Exception as e:
    print(f"   Erro: {e}")

# Método 3: Tentar endpoint auth para verificar se há dados de autenticação
print("\n3️⃣  Status da autenticação:")
print(f"   Chave ANON: {key[:20] if key else 'vazia'}...")

# Método 4: GET direto para uma tabela conhecida
print("\n4️⃣  Teste direto GET /rest/v1/usuarios")
req3 = urllib.request.Request(f"{url}/rest/v1/usuarios", headers=headers)
try:
    with urllib.request.urlopen(req3, timeout=5) as r:
        raw = r.read().decode()
        print(f"   Status: {r.status}")
        print(f"   Content-Type: {r.headers.get('Content-Type')}")
        print(f"   Content-Length: {r.headers.get('Content-Length')}")
        print(f"   Response (primeiros 200 chars): {raw[:200]}")
except urllib.error.HTTPError as e:
    print(f"   HTTP Error {e.code}: {e.reason}")
    print(f"   Body: {e.read().decode()[:200]}")
except Exception as e:
    print(f"   Erro: {e}")

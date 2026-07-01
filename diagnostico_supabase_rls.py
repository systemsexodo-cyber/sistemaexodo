#!/usr/bin/env python3
"""Verificar problema com Row Level Security ou permissões"""
import urllib.request
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
anon_key = os.getenv('SUPABASE_ANON_KEY')
service_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')

print("TESTES DE ACESSO AO SUPABASE")
print("="*60)

# Teste 1: Com ANON_KEY
print("\n1️⃣  Teste com ANON_KEY:")
headers_anon = {
    'Accept': 'application/json',
    'apikey': anon_key,
    'Authorization': f'Bearer {anon_key}'
}

endpoints = [
    ('empresas (todas colunas)', '/rest/v1/empresas'),
    ('empresas limit 1', '/rest/v1/empresas?limit=1'),
    ('count', '/rest/v1/empresas?select=count()'),
]

for desc, endpoint in endpoints:
    print(f"\n  {desc}:")
    req = urllib.request.Request(f'{url}{endpoint}', headers=headers_anon)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read().decode())
            content_range = r.headers.get('Content-Range', 'N/A')
            print(f"    Resultado: {data}")
            print(f"    Content-Range: {content_range}")
    except Exception as e:
        print(f"    Erro: {type(e).__name__}: {e}")

# Teste 2: Com SERVICE_ROLE_KEY se disponível
if service_key:
    print("\n\n2️⃣  Teste com SERVICE_ROLE_KEY:")
    headers_service = {
        'Accept': 'application/json',
        'apikey': service_key,
        'Authorization': f'Bearer {service_key}'
    }
    
    for desc, endpoint in endpoints:
        print(f"\n  {desc}:")
        req = urllib.request.Request(f'{url}{endpoint}', headers=headers_service)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.loads(r.read().decode())
                print(f"    Resultado: {data}")
        except Exception as e:
            print(f"    Erro: {type(e).__name__}: {e}")
else:
    print("\n⚠️  SERVICE_ROLE_KEY não configurada")

print("\n" + "="*60)
print("DIAGNÓSTICO:")
print("- Se ambas retornam [], pode ser RLS (Row Level Security)")
print("- Se SERVICE_ROLE_KEY retorna dados e ANON_KEY não, é RLS")
print("- Se nenhuma retorna dados, o Supabase pode estar vazio")

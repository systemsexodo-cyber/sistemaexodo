#!/usr/bin/env python3
"""Debug: Verificar formato de dados retornado pela API"""
import urllib.request
import urllib.parse
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

table = 'empresas'
table_escaped = urllib.parse.quote(table, safe='')
api_url = f"{url.rstrip('/')}/rest/v1/{table_escaped}"

params = urllib.parse.urlencode({
    'select': '*',
    'order': 'id.asc',
    'limit': 5,
    'offset': 0,
})

headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'apikey': key,
    'Authorization': f'Bearer {key}'
}

full_url = f"{api_url}?{params}"
print(f"URL: {full_url}\n")

request = urllib.request.Request(full_url, headers=headers)

try:
    with urllib.request.urlopen(request, timeout=10) as response:
        raw_data = response.read().decode('utf-8')
        
        print("Raw Data Type:", type(raw_data))
        print(f"Raw Data (primeiros 500 chars):\n{raw_data[:500]}\n")
        
        parsed = json.loads(raw_data)
        print(f"Parsed Type: {type(parsed)}")
        print(f"Parsed Value: {parsed}\n")
        
        if isinstance(parsed, list):
            print(f"Lista com {len(parsed)} elementos")
            if parsed:
                print(f"Primeiro elemento: {parsed[0]}")
        else:
            print(f"Não é lista, é: {type(parsed)}")
            
except Exception as e:
    print(f"Erro: {e}")

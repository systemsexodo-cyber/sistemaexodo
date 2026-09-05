import os
import json
import urllib.request
import urllib.parse
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

if not supabase_url or not api_key:
    print("Erro: SUPABASE_URL ou chaves não configuradas no .env")
    exit(1)

url = f"{supabase_url.rstrip('/')}/rest/v1/usuarios?limit=1"
headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read().decode('utf-8'))
        print("Sucesso!")
        if data:
            print("Colunas do Supabase na tabela 'usuarios':")
            for k in data[0].keys():
                print(f"  • {k}")
        else:
            print("Tabela 'usuarios' está vazia no Supabase.")
except Exception as e:
    print(f"Erro ao consultar Supabase: {e}")
    if hasattr(e, 'read'):
        print(e.read().decode('utf-8'))

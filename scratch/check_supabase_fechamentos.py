import os
import json
import urllib.request
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

url = f"{supabase_url.rstrip('/')}/rest/v1/fechamentos_caixa?select=id,abertura_caixa_id,data_fechamento,created_at&order=data_fechamento.desc&limit=15"
headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read().decode('utf-8'))
        print("Fechamentos no Supabase:")
        for r in data:
            print(f"  • ID: {r.get('id')} | Abertura: {r.get('abertura_caixa_id')} | Data: {r.get('data_fechamento')} | Criado: {r.get('created_at')}")
except Exception as e:
    print(f"Erro: {e}")

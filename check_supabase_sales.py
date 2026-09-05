import os
import json
import urllib.request
import urllib.parse
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

url = f"{supabase_url.rstrip('/')}/rest/v1/vendas_balcao?select=id,numero,data_venda,valor_total&order=data_venda.desc&limit=15"
headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read().decode('utf-8'))
        print("Vendas no Supabase:")
        for r in data:
            print(f"  • ID: {r['id']} | Número: {r['numero']} | Data: {r['data_venda']} | Total: {r['valor_total']}")
except Exception as e:
    print(f"Erro: {e}")

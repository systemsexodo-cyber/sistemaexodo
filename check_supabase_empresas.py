import os
import json
import urllib.request
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

url = f"{supabase_url.rstrip('/')}/rest/v1/vendas_balcao?select=empresa_id"
headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read().decode('utf-8'))
        counts = {}
        for r in data:
            emp = r.get('empresa_id')
            counts[emp] = counts.get(emp, 0) + 1
        print("Sales per empresa_id in Supabase:")
        for emp, count in counts.items():
            print(f"  • {emp}: {count} sales")
except Exception as e:
    print(f"Erro: {e}")

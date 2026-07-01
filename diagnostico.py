import os, urllib.request, urllib.parse, json
from dotenv import load_dotenv

load_dotenv()
url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
headers = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}

# Pega 2 registros de produto_historico para ver os tipos de dados
req = urllib.request.Request(
    f"{url}/rest/v1/produto_historico?select=*&limit=2",
    headers=headers
)
with urllib.request.urlopen(req, timeout=15) as r:
    rows = json.loads(r.read())

for row in rows:
    for k, v in row.items():
        print(f"{k}: [{type(v).__name__}] {repr(v)[:80]}")
    print("---")

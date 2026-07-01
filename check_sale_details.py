import os
import json
import urllib.request
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

ids = ['c3296f8b-d8ae-4e5a-997a-ba346389b2de', 'd6e0dc98-e989-4f2f-a89f-89d304fc18fe']
for val_id in ids:
    url = f"{supabase_url.rstrip('/')}/rest/v1/vendas_balcao?id=eq.{val_id}"
    headers = {
        'Accept': 'application/json',
        'apikey': api_key,
        'Authorization': f'Bearer {api_key}',
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read().decode('utf-8'))
            if data:
                print(f"\nDetalhes da venda {data[0].get('numero')}:")
                for k, v in data[0].items():
                    print(f"  • {k}: {v}")
            else:
                print(f"Venda {val_id} não encontrada no Supabase.")
    except Exception as e:
        print(f"Erro ao consultar {val_id}: {e}")

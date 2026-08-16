import os
import requests
import re
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL') or os.getenv('NEXT_PUBLIC_SUPABASE_URL')
supabase_key = os.getenv('SUPABASE_ANON_KEY') or os.getenv('NEXT_PUBLIC_SUPABASE_ANON_KEY')

if not supabase_url or not supabase_key:
    with open('lib/supabase_config.dart', 'r') as f:
        content = f.read()
        url_match = re.search(r"url = '([^']+)'", content)
        key_match = re.search(r"anonKey = '([^']+)'", content)
        if url_match:
            supabase_url = url_match.group(1)
        if key_match:
            supabase_key = key_match.group(1)

if supabase_url and supabase_key:
    try:
        url = f"{supabase_url}/rest/v1/vendas_balcao?select=id,numero,cancelado,created_at,updated_at&order=updated_at.desc&limit=100"
        headers = {
            "apikey": supabase_key,
            "Authorization": f"Bearer {supabase_key}"
        }
        res = requests.get(url, headers=headers)
        res.raise_for_status()
        vendas = res.json()
        print("Checking recent sales on Supabase:")
        for v in vendas:
            created_at = v.get('created_at')
            updated_at = v.get('updated_at')
            print(f"  * ID: {v.get('id')} | Num: {v.get('numero')} | Cancelado: {v.get('cancelado')} | Created: {created_at} | Updated: {updated_at}")
            if created_at is None:
                print("    WARNING: created_at is NULL!")
            if updated_at is None:
                print("    WARNING: updated_at is NULL!")
    except Exception as e:
        print(f"Error: {e}")
else:
    print("Supabase config not found.")

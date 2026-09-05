import os
import requests
import re
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL') or os.getenv('NEXT_PUBLIC_SUPABASE_URL')
supabase_key = os.getenv('SUPABASE_ANON_KEY') or os.getenv('NEXT_PUBLIC_SUPABASE_ANON_KEY')

if not supabase_url or not supabase_key:
    # Try finding in .env or other config
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
        url = f"{supabase_url}/rest/v1/"
        headers = {
            "apikey": supabase_key,
            "Authorization": f"Bearer {supabase_key}"
        }
        res = requests.get(url, headers=headers)
        schema = res.json()
        
        # Look for vendas_balcao definition
        definitions = schema.get('definitions', {})
        vendas_def = definitions.get('vendas_balcao', {})
        properties = vendas_def.get('properties', {})
        
        print("Supabase 'vendas_balcao' table columns and types:")
        for col, details in properties.items():
            print(f"  {col}: {details.get('type')} ({details.get('format')})")
            
    except Exception as e:
        print(f"Error: {e}")
else:
    print("Supabase config not found.")

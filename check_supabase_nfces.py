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
        # Extract URL and Key
        url_match = re.search(r"url = '([^']+)'", content)
        key_match = re.search(r"anonKey = '([^']+)'", content)
        if url_match:
            supabase_url = url_match.group(1)
        if key_match:
            supabase_key = key_match.group(1)

print(f"Supabase URL: {supabase_url}")
if supabase_url and supabase_key:
    try:
        url = f"{supabase_url}/rest/v1/nfces"
        headers = {
            "apikey": supabase_key,
            "Authorization": f"Bearer {supabase_key}",
            "Range-Unit": "items",
            "Prefer": "count=exact"
        }
        res = requests.get(url, headers=headers, params={"limit": 0})
        print(f"Status Code: {res.status_code}")
        print(f"Headers: {res.headers}")
        print(f"Supabase nfces row count: {res.headers.get('Content-Range')}")
    except Exception as e:
        print(f"Error querying Supabase: {e}")
else:
    print("Supabase config not found.")

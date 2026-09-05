import os
import requests

env_vars = {}
if os.path.exists(".env"):
    with open(".env", "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                env_vars[key.strip()] = val.strip().strip('"').strip("'")

supabase_url = env_vars.get("SUPABASE_URL")
supabase_key = env_vars.get("SUPABASE_ANON_KEY")

if not supabase_url or not supabase_key:
    print("Erro: chaves do Supabase não encontradas!")
    exit(1)

url = f"{supabase_url}/rest/v1/bridge_status"
headers = {
    "Authorization": f"Bearer {supabase_key}",
    "apikey": supabase_key
}

r = requests.get(url, headers=headers)
print("Status Code:", r.status_code)
if r.status_code == 200:
    import json
    print(json.dumps(r.json(), indent=2))
else:
    print("Erro:", r.text)

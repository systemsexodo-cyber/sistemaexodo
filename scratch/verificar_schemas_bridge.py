import os
import requests
import json

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

# Consulta o schema OpenAPI
url = f"{supabase_url}/rest/v1/"
headers = {
    "Authorization": f"Bearer {supabase_key}",
    "apikey": supabase_key
}

r = requests.get(url, headers=headers)
if r.status_code == 200:
    data = r.json()
    definitions = data.get("definitions", {})
    
    for table in ["bridge_commands", "bridge_status"]:
        if table in definitions:
            print(f"\n=== TABELA: {table} ===")
            properties = definitions[table].get("properties", {})
            for col, prop in properties.items():
                print(f"  • {col}: {prop.get('type')} ({prop.get('description', '')})")
        else:
            print(f"\nTabela '{table}' não encontrada no OpenAPI.")
else:
    print("Erro:", r.text)

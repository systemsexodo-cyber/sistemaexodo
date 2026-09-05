import os, urllib.request, urllib.parse, json
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

# 1. Tentar buscar tabela publica usuarios
print("=== Tabela publica: usuarios ===")
url = f"{supabase_url}/rest/v1/usuarios?select=*&limit=5"
try:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(r.read())
        print(f"Registros: {len(data)}")
        if data:
            print("Primeiro registro (chaves):", list(data[0].keys()))
        else:
            print("VAZIA")
except Exception as e:
    print(f"Erro: {e}")

# 2. Tentar buscar auth.users via admin endpoint
print("\n=== Auth Users (Supabase Auth) ===")
url2 = f"{supabase_url}/auth/v1/admin/users"
try:
    req2 = urllib.request.Request(url2, headers=headers)
    with urllib.request.urlopen(req2, timeout=15) as r:
        data2 = json.loads(r.read())
        users = data2.get('users', data2) if isinstance(data2, dict) else data2
        print(f"Usuarios encontrados: {len(users)}")
        if users:
            for u in users[:5]:
                print(f"  - {u.get('email', u.get('id', '?'))}")
except Exception as e:
    print(f"Erro: {e}")

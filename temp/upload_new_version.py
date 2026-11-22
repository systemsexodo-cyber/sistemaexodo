import requests
import json
import os

# Load env from project root
env = {}
with open('.env', 'r', encoding='utf-8', errors='replace') as f:
    for linha in f:
        linha = linha.strip()
        if not linha or linha.startswith('#') or '=' not in linha:
            continue
        chave, valor = linha.split('=', 1)
        env[chave.strip()] = valor.strip().strip('"').strip("'")

url = env.get('SUPABASE_URL', '').rstrip('/')
chave = env.get('SUPABASE_SERVICE_ROLE_KEY') or env.get('SUPABASE_ANON_KEY', '')

headers = {'apikey': chave, 'Authorization': f'Bearer {chave}'}

# Paths relative to project root
zip_path = os.path.join(os.getcwd(), 'sistema_exodo_novo_1.0.88.zip')
file_name = 'sistema_exodo_novo_1.0.88.zip'

if not os.path.exists(zip_path):
    print(f' Zip file not found: {zip_path}')
    exit(1)

with open(zip_path, 'rb') as f:
    file_data = f.read()

print(f'Uploading {file_name} ({len(file_data)} bytes)...')

r = requests.post(
    f'{url}/storage/v1/object/atualizacoes/upload',
    headers={**headers, 'Content-Type': 'application/octet-stream'},
    data=file_data,
    params={'path': file_name, 'upsert': 'true'},
    timeout=120
)

print(f'Upload status: {r.status_code}')
print(r.text[:300] if r.text else '')

# After upload, verify the bucket now has the new version
print('')
print('--- Verifying bucket contents ---')
r2 = requests.post(
    f'{url}/storage/v1/object/list/atualizacoes',
    headers={**headers, 'Content-Type': 'application/json'},
    data=json.dumps({'prefix': '', 'limit': 200, 'sortBy': {'column': 'name', 'order': 'asc'}}),
    timeout=20
)
if r2.status_code == 200:
    data = r2.json()
    names = [item.get('name', '') for item in data]
    if 'sistema_exodo_novo_1.0.88.zip' in names:
        print(' New version 1.0.88.zip now exists in bucket!')
    else:
        print(' 1.0.88.zip not found in bucket list - checking what 1.0.88 files are there...')
        for item in data:
            if '1.0.88' in item.get('name', ''):
                print(f'   Found: {item.get("name")}')
    # Show last few entries
    print(' Last 5 entries in bucket:')
    for item in data[-5:]:
        print(f'   {item.get("name")}')
else:
    print(f'  Failed to list bucket: HTTP {r2.status_code}')
    print(r2.text[:200] if r2.text else '')
import os
import json
import urllib.request
import psycopg2
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

def fetch_supabase(table):
    url = f"{supabase_url.rstrip('/')}/rest/v1/{table}?select=*"
    headers = {
        'Accept': 'application/json',
        'apikey': api_key,
        'Authorization': f'Bearer {api_key}',
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode('utf-8'))

print("Baixando dados corretos do Supabase...")
try:
    fechamentos = fetch_supabase("fechamentos_caixa")
    aberturas = fetch_supabase("aberturas_caixa")
    print(f"Baixados {len(fechamentos)} fechamentos e {len(aberturas)} aberturas.")
except Exception as e:
    print(f"Erro ao baixar do Supabase: {e}")
    exit(1)

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

# Desativa temporariamente os triggers de sincronização
cur.execute("SET LOCAL exodo.sync_mode = 'on';")

reparados_fechamentos = 0
for f in fechamentos:
    fid = f.get('id')
    data_fech = f.get('data_fechamento')
    created = f.get('created_at')
    updated = f.get('updated_at')
    
    cur.execute("""
        UPDATE fechamentos_caixa 
        SET data_fechamento = %s, created_at = %s, updated_at = %s, 
            "dataFechamento" = NULL, "createdAt" = NULL, "updatedAt" = NULL
        WHERE id = %s;
    """, (data_ech if (data_ech := data_fech) else None, created, updated, fid))
    if cur.rowcount > 0:
        reparados_fechamentos += 1

reparados_aberturas = 0
for a in aberturas:
    aid = a.get('id')
    data_aber = a.get('data_abertura')
    created = a.get('created_at')
    updated = a.get('updated_at')
    
    cur.execute("""
        UPDATE aberturas_caixa 
        SET data_abertura = %s, created_at = %s, updated_at = %s,
            "dataAbertura" = NULL, "createdAt" = NULL, "updatedAt" = NULL
        WHERE id = %s;
    """, (data_aber, created, updated, aid))
    if cur.rowcount > 0:
        reparados_aberturas += 1

conn.commit()
print(f"Reparação concluída! {reparados_fechamentos} fechamentos e {reparados_aberturas} aberturas reparadas localmente.")

cur.close()
conn.close()

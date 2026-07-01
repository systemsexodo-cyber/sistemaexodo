import os
import sqlite3
import psycopg2
import json
import urllib.request
from dotenv import load_dotenv

load_dotenv()

# 1. SQLite
db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

conn_sqlite = sqlite3.connect(db_path)
cur_sqlite = conn_sqlite.cursor()
cur_sqlite.execute("SELECT numero FROM vendas_local")
sqlite_sales = {r[0] for r in cur_sqlite.fetchall() if r[0]}
conn_sqlite.close()

# 2. PostgreSQL
conn_pg = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur_pg = conn_pg.cursor()
cur_pg.execute("SELECT numero FROM vendas_balcao")
pg_sales = {r[0] for r in cur_pg.fetchall() if r[0]}
conn_pg.close()

# 3. Supabase
supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
url = f"{supabase_url.rstrip('/')}/rest/v1/vendas_balcao?select=numero"
headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read().decode('utf-8'))
        supabase_sales = {r['numero'] for r in data if r.get('numero')}
except Exception as e:
    print(f"Erro no Supabase: {e}")
    supabase_sales = set()

print(f"Total valid sales in SQLite: {len(sqlite_sales)}")
print(f"Total valid sales in PostgreSQL: {len(pg_sales)}")
print(f"Total valid sales in Supabase: {len(supabase_sales)}")

print("\nSales in Supabase but not in PostgreSQL:")
print(supabase_sales - pg_sales)

print("\nSales in PostgreSQL but not in Supabase:")
print(pg_sales - supabase_sales)

print("\nSales in Supabase but not in SQLite:")
print(supabase_sales - sqlite_sales)

print("\nSales in SQLite but not in Supabase:")
print(sqlite_sales - supabase_sales)

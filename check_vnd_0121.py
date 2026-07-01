import sqlite3
import os

db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

print(f"Checking database for VND-0121: {db_path}")
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Search in vendas_local
cur.execute("SELECT * FROM vendas_local WHERE numero = 'VND-0121'")
row = cur.fetchone()
if row:
    print(f"Found VND-0121 in vendas_local: {row}")
else:
    print("VND-0121 NOT found in vendas_local!")

# Search in cache_dados
cur.execute("SELECT * FROM cache_dados WHERE chave LIKE '%vendas%'")
cache_rows = cur.fetchall()
print(f"Found {len(cache_rows)} cache_dados rows matching '%vendas%'")
for r in cache_rows:
    print(f"  • {r[0]}: {r[1][:200]}...")
    if 'VND-0121' in r[1]:
        print("    *** FOUND VND-0121 inside this JSON! ***")

conn.close()

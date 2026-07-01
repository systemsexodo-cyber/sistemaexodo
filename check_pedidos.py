import os
import sqlite3
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# SQLite pedidos
db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

conn_sqlite = sqlite3.connect(db_path)
cur_sqlite = conn_sqlite.cursor()
cur_sqlite.execute("SELECT id, numero, valor_total, status, data_emissao FROM pedidos_local ORDER BY rowid DESC LIMIT 10")
sqlite_pedidos = cur_sqlite.fetchall()
conn_sqlite.close()

print("Latest 10 orders in SQLite (pedidos_local):")
for p in sqlite_pedidos:
    print(p)

# PostgreSQL pedidos
conn_pg = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur_pg = conn_pg.cursor()
cur_pg.execute("SELECT id, numero, valor_total, status, created_at FROM pedidos ORDER BY created_at DESC LIMIT 10")
pg_pedidos = cur_pg.fetchall()
conn_pg.close()

print("\nLatest 10 orders in PostgreSQL (pedidos):")
for p in pg_pedidos:
    print(p)

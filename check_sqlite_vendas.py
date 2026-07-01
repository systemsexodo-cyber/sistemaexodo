import sqlite3
import os
from pathlib import Path

db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

print(f"Checking database: {db_path}")
if not os.path.exists(db_path):
    print("Database file does not exist!")
else:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = cur.fetchall()
    print("Tables:", [t[0] for t in tables])
    if ('vendas_local',) in tables:
        cur.execute("SELECT COUNT(*) FROM vendas_local")
        print("vendas_local count:", cur.fetchone()[0])
        cur.execute("SELECT id, numero, valor_total, data_venda, status FROM vendas_local ORDER BY rowid DESC LIMIT 5")
        rows = cur.fetchall()
        print("Last 5 sales in SQLite:")
        for r in rows:
            print(r)
    else:
        print("vendas_local table does NOT exist in sqlite!")
    conn.close()

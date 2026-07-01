import sqlite3
import os

db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT rowid, id, numero FROM vendas_local")
rows = cur.fetchall()
print("All sales in SQLite with rowid:")
for r in rows:
    print(r)
conn.close()

import sqlite3
import os

db_path = os.path.expanduser('~/Documents/exodo_local.db')
if not os.path.exists(db_path):
    db_path = 'exodo_local.db'

print(f"Checking database: {db_path}")
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT id, empresa_id, numero, valor_total, data_venda, status FROM vendas_local")
rows = cur.fetchall()
print(f"Total sales in SQLite: {len(rows)}")
empresa_counts = {}
for r in rows:
    emp_id = r[1]
    empresa_counts[emp_id] = empresa_counts.get(emp_id, 0) + 1

print("Sales per empresa_id:")
for emp, count in empresa_counts.items():
    print(f"  • {emp}: {count} sales")

print("\nLast 10 sales:")
cur.execute("SELECT id, empresa_id, numero, valor_total, data_venda, status FROM vendas_local ORDER BY rowid DESC LIMIT 10")
for r in cur.fetchall():
    print(r)

conn.close()

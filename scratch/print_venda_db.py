import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

cur.execute("""
    SELECT id, numero, data_venda, created_at
    FROM vendas_balcao
    ORDER BY created_at DESC
    LIMIT 5;
""")
rows = cur.fetchall()
print("=== RAW POSTGRES VALUES ===")
for r in rows:
    print(f"ID: {r[0]} | Numero: {r[1]} | data_venda: {r[2]} ({type(r[2])}) | created_at: {r[3]}")

cur.close()
conn.close()

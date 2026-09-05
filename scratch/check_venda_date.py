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
    ORDER BY numero DESC
    LIMIT 5;
""")
rows = cur.fetchall()

print("Recent sales in local PostgreSQL:")
for row in rows:
    print(f"Número: {row[1]} | ID: {row[0]}")
    print(f"  data_venda: {row[2]} (type: {type(row[2])})")
    print(f"  created_at: {row[3]} (type: {type(row[3])})")

cur.close()
conn.close()

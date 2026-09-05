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

# Get recent 20 sales from local postgres
cur.execute("SELECT id, numero, data_venda, valor_total, cancelado, updated_at FROM vendas_balcao ORDER BY data_venda DESC LIMIT 20;")
print('Recent 20 sales in local postgres:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Número: {row[1]} | Data: {row[2]} | Total: {row[3]} | Cancelado: {row[4]} | Updated: {row[5]}")

cur.close()
conn.close()

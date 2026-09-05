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

# Get recent sales
cur.execute('SELECT id, data_venda, valor_total, operador, sync FROM vendas_balcao ORDER BY data_venda DESC LIMIT 5;')
print('Recent 5 sales:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Data: {row[1]} | Valor: {row[2]} | Operador: {row[3]} | Sync: {row[4]}")

cur.close()
conn.close()

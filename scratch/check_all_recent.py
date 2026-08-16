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

# Get recent sales from July 10th
cur.execute("SELECT id, numero, data_venda, valor_total FROM vendas_balcao WHERE data_venda >= '2026-07-10' ORDER BY data_venda DESC;")
print('Sales from July 10th onwards:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Número: {row[1]} | Data: {row[2]} | Total: {row[3]}")

# Get recent pedidos from July 10th
cur.execute("SELECT id, numero, data_pedido, valor_total FROM pedidos WHERE data_pedido >= '2026-07-10' ORDER BY data_pedido DESC;")
print('\nPedidos from July 10th onwards:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Número: {row[1]} | Data: {row[2]} | Total: {row[3]}")

# Get recent sangrias from July 10th
cur.execute("SELECT id, valor, data_operacao FROM sangrias_caixa WHERE data_operacao >= '2026-07-10' ORDER BY data_operacao DESC;")
print('\nSangrias from July 10th onwards:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Valor: {row[1]} | Data: {row[2]}")

cur.close()
conn.close()

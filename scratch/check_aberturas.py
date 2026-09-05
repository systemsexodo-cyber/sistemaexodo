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

# Get recent aberturas
cur.execute("SELECT id, operador, data_abertura, created_at, empresa_id FROM aberturas_caixa ORDER BY data_abertura DESC LIMIT 20;")
print('Recent 20 aberturas:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Operador: {row[1]} | Abertura: {row[2]} | Criado: {row[3]} | Empresa: {row[4]}")

cur.close()
conn.close()

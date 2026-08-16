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

# Get recent fechamentos
cur.execute("SELECT id, abertura_caixa_id, operador, data_fechamento, created_at, empresa_id FROM fechamentos_caixa ORDER BY data_fechamento DESC LIMIT 20;")
print('Recent 20 fechamentos:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Abertura: {row[1]} | Operador: {row[2]} | Data: {row[3]} | Criado: {row[4]} | Empresa: {row[5]}")

cur.close()
conn.close()

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

# Get recent sangrias
try:
    cur.execute("SELECT id, valor, data_operacao, abertura_caixa_id, empresa_id FROM sangrias_caixa ORDER BY data_operacao DESC LIMIT 10;")
    print('Recent 10 sangrias in local postgres:')
    for row in cur.fetchall():
        print(f"  • ID: {row[0]} | Valor: {row[1]} | Data: {row[2]} | Caixa ID: {row[3]} | Empresa: {row[4]}")
except Exception as e:
    print(f"Error querying sangrias: {e}")

# Get recent suprimentos
try:
    cur.execute("SELECT id, valor, data_operacao, abertura_caixa_id, empresa_id FROM suprimentos_caixa ORDER BY data_operacao DESC LIMIT 10;")
    print('\nRecent 10 suprimentos in local postgres:')
    for row in cur.fetchall():
        print(f"  • ID: {row[0]} | Valor: {row[1]} | Data: {row[2]} | Caixa ID: {row[3]} | Empresa: {row[4]}")
except Exception as e:
    print(f"Error querying suprimentos: {e}")

cur.close()
conn.close()

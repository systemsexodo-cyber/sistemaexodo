import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

db_host = os.getenv('DB_HOST', 'localhost')
db_port = os.getenv('DB_PORT', '5432')
db_name = os.getenv('DB_NAME')
db_user = os.getenv('DB_USER')
db_password = os.getenv('DB_PASSWORD')

try:
    conn = psycopg2.connect(
        host=db_host, port=db_port, dbname=db_name, user=db_user, password=db_password
    )
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM vendas_balcao")
    count = cur.fetchone()[0]
    print(f"Total de vendas no Postgres local: {count}")
    
    cur.execute("SELECT id, numero, data_venda, valor_total FROM vendas_balcao ORDER BY data_venda DESC LIMIT 10")
    rows = cur.fetchall()
    print("\nÚltimas 10 vendas no Postgres local:")
    for r in rows:
        print(f"  • ID: {r[0]} | Número: {r[1]} | Data: {r[2]} | Total: {r[3]}")
        
    conn.close()
except Exception as e:
    print(f"Erro: {e}")

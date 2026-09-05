import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT id, numero, data_venda, valor_total, created_at FROM vendas_balcao WHERE empresa_id = '66a880c8-51c7-496f-826b-d2ff9ab8ed2d'")
rows = cur.fetchall()
print("Sales for company 66a880c8-51c7-496f-826b-d2ff9ab8ed2d:")
for r in rows:
    print(r)
conn.close()

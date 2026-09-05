import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT empresa_id, COUNT(*) FROM vendas_balcao GROUP BY empresa_id")
rows = cur.fetchall()
print("Sales per empresa_id in PostgreSQL:")
for r in rows:
    print(f"  • {r[0]}: {r[1]} sales")
conn.close()

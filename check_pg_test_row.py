import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT id, numero, created_at FROM vendas_balcao WHERE id = 'sync-test-999'")
row = cur.fetchone()
if row:
    print(f"Found sync-test-999 in PostgreSQL: {row}")
else:
    print("sync-test-999 NOT found in PostgreSQL!")
conn.close()

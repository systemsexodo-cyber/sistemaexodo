import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name='produto_historico'")
rows = cur.fetchall()
print("Columns in PostgreSQL 'produto_historico':")
for r in rows:
    print(r)
conn.close()

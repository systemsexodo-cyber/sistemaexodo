import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT chave, valor FROM _sync_controle")
rows = cur.fetchall()
print("Contents of _sync_controle:")
for r in rows:
    print(f"  • {r[0]}: {r[1]}")
conn.close()

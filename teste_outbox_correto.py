import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute("INSERT INTO vendas_balcao (id) VALUES ('sync-test-999')")
    print("Venda de teste inserida localmente.")
except Exception as e:
    print(f"Erro no insert: {e}")

# Checar se caiu no log
cur.execute("SELECT * FROM _exodo_sync_log WHERE record_id = 'sync-test-999'")
rows = cur.fetchall()
if rows:
    print(f"✅ Venda capturada na fila de sync: {rows}")
else:
    print("❌ Venda NÃO foi capturada na fila.")

cur.execute("DELETE FROM vendas_balcao WHERE id='sync-test-999'")
conn.close()

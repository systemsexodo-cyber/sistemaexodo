import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

# Simular inserção como o app Delphi faz
try:
    cur.execute("INSERT INTO vendas_balcao (id, total) VALUES ('sync-test-999', 99.90)")
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

conn.close()

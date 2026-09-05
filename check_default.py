import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
cur.execute("SELECT column_name, column_default FROM information_schema.columns WHERE table_name='vendas_balcao' AND column_name='_sincronizado_nuvem'")
print("Default value of _sincronizado_nuvem:", cur.fetchone())
conn.close()

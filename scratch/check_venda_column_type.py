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

cur.execute("""
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_name = 'vendas_balcao' AND column_name = 'data_venda';
""")
row = cur.fetchone()
print(f"data_venda column type: {row}")

cur.execute("""
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_name = 'fechamentos_caixa' AND column_name = 'data_fechamento';
""")
row = cur.fetchone()
print(f"data_fechamento column type: {row}")

cur.close()
conn.close()

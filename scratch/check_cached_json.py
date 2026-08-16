import os
import psycopg2
import json
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

# Find the cache key for vendas_balcao
cur.execute("SELECT chave, valor_json FROM cache_dados WHERE chave LIKE '%vendas_balcao%';")
rows = cur.fetchall()
print(f"Found cache keys: {[r[0] for r in rows]}")
for row in rows:
    try:
        data = json.loads(row[1])
        print(f"Key: {row[0]} | Number of items: {len(data)}")
        if len(data) > 0:
            item = data[0]
            print("First item date keys:")
            print(f"  data_venda: {item.get('data_venda')} ({type(item.get('data_venda'))})")
            print(f"  dataVenda: {item.get('dataVenda')} ({type(item.get('dataVenda'))})")
    except Exception as e:
        print(f"Error parsing key {row[0]}: {e}")

cur.close()
conn.close()

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

# Get recent fechamentos
cur.execute('SELECT id, data_fechamento, "dataFechamento", created_at, "createdAt" FROM fechamentos_caixa ORDER BY created_at DESC LIMIT 10;')
print('Fechamento dates:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]}")
    print(f"    data_fechamento:  {row[1]}")
    print(f"    dataFechamento:   {row[2]}")
    print(f"    created_at:       {row[3]}")
    print(f"    createdAt:        {row[4]}")
    print("-" * 50)

cur.close()
conn.close()

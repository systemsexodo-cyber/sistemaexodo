import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

# Remover trigger de vendas_balcao
cur.execute('DROP TRIGGER IF EXISTS trg_sincronizado_false_vendas_balcao ON vendas_balcao')

# Remover a coluna _sincronizado_nuvem
cur.execute('ALTER TABLE vendas_balcao DROP COLUMN IF EXISTS _sincronizado_nuvem')

print('Coluna e trigger removidos da tabela vendas_balcao.')
conn.close()

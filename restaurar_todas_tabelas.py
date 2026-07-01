import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

cur.execute("""
    SELECT DISTINCT table_name FROM information_schema.columns
    WHERE column_name='_sincronizado_nuvem' AND table_schema='public'
""")
tabelas = [r[0] for r in cur.fetchall()]

for t in tabelas:
    try:
        cur.execute(f'DROP TRIGGER IF EXISTS trg_sincronizado_false_{t} ON "{t}"')
        cur.execute(f'ALTER TABLE "{t}" DROP COLUMN IF EXISTS _sincronizado_nuvem')
        print(f'Coluna removida de {t}')
    except Exception as e:
        print(f'Erro ao remover de {t}: {e}')

conn.close()

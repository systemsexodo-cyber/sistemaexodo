import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

# Buscar todas as tabelas com _sincronizado_nuvem
cur.execute("""
    SELECT DISTINCT table_name FROM information_schema.columns
    WHERE column_name='_sincronizado_nuvem' AND table_schema='public'
    ORDER BY table_name
""")
tabelas = [r[0] for r in cur.fetchall() if not r[0].startswith('_')]

for t in tabelas:
    cur.execute(f"""
        DROP TRIGGER IF EXISTS trg_sincronizado_false_{t} ON "{t}";
        CREATE TRIGGER trg_sincronizado_false_{t}
        BEFORE UPDATE ON "{t}"
        FOR EACH ROW
        WHEN (NEW._sincronizado_nuvem IS NOT DISTINCT FROM OLD._sincronizado_nuvem)
        EXECUTE FUNCTION set_sincronizado_false();
    """)
    print(f"Trigger revertido para UPDATE apenas: {t}")

conn.close()

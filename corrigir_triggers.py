import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
conn.autocommit = True
cur = conn.cursor()

# Recriar funcao de trigger: marca FALSE tanto no INSERT quanto no UPDATE
cur.execute("""
    CREATE OR REPLACE FUNCTION set_sincronizado_false()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW._sincronizado_nuvem = FALSE;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
""")
print("Funcao de trigger recriada.")

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
        BEFORE INSERT OR UPDATE ON "{t}"
        FOR EACH ROW
        WHEN (NEW._sincronizado_nuvem IS DISTINCT FROM FALSE)
        EXECUTE FUNCTION set_sincronizado_false();
    """)
    print(f"  Trigger atualizado: {t} (INSERT + UPDATE)")

# Marcar a venda recente como nao sincronizada para ela subir agora
cur.execute("""
    UPDATE vendas_balcao SET _sincronizado_nuvem = FALSE
    WHERE created_at >= NOW() - INTERVAL '1 hour'
""")
print(f"\nVendas da ultima hora marcadas para upload: {cur.rowcount}")

conn.close()
print("\nConcluido! Pode abrir o sincronizador agora.")

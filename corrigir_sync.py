import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

# 1. Marcar TODOS os registros já existentes como sincronizados para parar o loop de download
print("Marcando todos os registros como sincronizados...")
cur.execute("""
    SELECT table_name FROM information_schema.columns
    WHERE column_name='_sincronizado_nuvem' AND table_schema='public'
""")
tabelas = [r[0] for r in cur.fetchall()]
for t in tabelas:
    cur.execute(f'UPDATE "{t}" SET _sincronizado_nuvem=TRUE WHERE _sincronizado_nuvem=FALSE')
    rows = cur.rowcount
    if rows > 0:
        print(f"  {t}: {rows} registros marcados")
conn.commit()

# 2. Corrigir a tabela usuarios - renomear colunas locais para bater com o Supabase
print("\nVerificando colunas da tabela usuarios...")
cur.execute("""
    SELECT column_name FROM information_schema.columns
    WHERE table_name='usuarios' AND table_schema='public'
    ORDER BY ordinal_position
""")
colunas = [r[0] for r in cur.fetchall()]
print("Colunas atuais:", colunas)

# Adicionar colunas que existem no Supabase mas nao na tabela local
colunas_supabase = ['created_at', 'updated_at', 'last_sign_in_at', 'email_confirmed_at']
for col in colunas_supabase:
    if col not in colunas:
        try:
            cur.execute(f'ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS "{col}" TEXT')
            print(f"  Coluna adicionada: {col}")
        except Exception as e:
            conn.rollback()
            print(f"  Erro ao adicionar {col}: {e}")

conn.commit()
conn.close()
print("\nConcluido!")

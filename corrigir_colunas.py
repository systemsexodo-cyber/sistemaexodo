import os, psycopg2
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'),
    port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

# Verificar colunas JSONB que deveriam ser TEXT em produto_historico
print("Colunas JSONB em produto_historico:")
cur.execute("""
    SELECT column_name, data_type 
    FROM information_schema.columns
    WHERE table_name='produto_historico' AND table_schema='public'
    ORDER BY ordinal_position
""")
for row in cur.fetchall():
    print(f"  {row[0]}: {row[1]}")

print("\nCorrigindo colunas com tipo errado...")

# produto_id, usuario_id devem ser TEXT, nao JSONB
correcoes = [
    ('produto_historico', 'produto_id'),
    ('produto_historico', 'usuario_id'),
    ('produto_historico', 'campos_alterados'),
    ('produto_historico', 'resumo_mudancas'),
    ('produto_historico', 'produto_nome'),
    ('produto_historico', 'produto_codigo'),
    ('produto_historico', 'usuario_nome'),
    ('produto_historico', 'usuario_email'),
    ('produto_historico', 'tipo_operacao'),
]

for tabela, coluna in correcoes:
    try:
        cur.execute(f"""
            SELECT data_type FROM information_schema.columns
            WHERE table_name=%s AND column_name=%s AND table_schema='public'
        """, (tabela, coluna))
        row = cur.fetchone()
        if row and row[0] == 'jsonb':
            cur.execute(f"""
                ALTER TABLE "{tabela}" 
                ALTER COLUMN "{coluna}" TYPE TEXT 
                USING "{coluna}"::text
            """)
            conn.commit()
            print(f"  Corrigido: {tabela}.{coluna} JSONB -> TEXT")
        else:
            print(f"  OK: {tabela}.{coluna} ja e {row[0] if row else 'nao existe'}")
    except Exception as e:
        conn.rollback()
        print(f"  Erro em {tabela}.{coluna}: {e}")

conn.close()
print("\nConcluido!")

import os, psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor(cursor_factory=RealDictCursor)

print("=== Registros NAO sincronizados (pendentes de upload) ===\n")

cur.execute("""
    SELECT table_name FROM information_schema.columns
    WHERE column_name='_sincronizado_nuvem' AND table_schema='public'
    ORDER BY table_name
""")
tabelas = [r['table_name'] for r in cur.fetchall()]

total = 0
for t in tabelas:
    cur.execute(f'SELECT COUNT(*) as qtd FROM "{t}" WHERE _sincronizado_nuvem = FALSE')
    qtd = cur.fetchone()['qtd']
    if qtd > 0:
        print(f"  {t}: {qtd} pendente(s)")
        total += qtd

if total == 0:
    print("  Nenhum registro pendente encontrado.")
    print("\n  Isso significa que a venda pode ter sido salva com _sincronizado_nuvem=TRUE")
    print("  ou o trigger nao esta ativo na tabela de vendas.")

print(f"\nTotal pendente: {total}")

# Verificar trigger na tabela vendas_balcao
print("\n=== Triggers na tabela vendas_balcao ===")
cur.execute("""
    SELECT trigger_name, event_manipulation, action_timing
    FROM information_schema.triggers
    WHERE event_object_table = 'vendas_balcao'
""")
triggers = cur.fetchall()
if triggers:
    for t in triggers:
        print(f"  {t['trigger_name']} ({t['action_timing']} {t['event_manipulation']})")
else:
    print("  NENHUM TRIGGER encontrado! O trigger nao esta configurado.")

# Verificar ultimo registro de vendas
print("\n=== Ultimas 3 vendas ===")
cur.execute("""
    SELECT id, _sincronizado_nuvem, created_at
    FROM vendas_balcao
    ORDER BY created_at DESC NULLS LAST
    LIMIT 3
""")
for v in cur.fetchall():
    print(f"  ID: {v['id'][:20]}... | sync: {v['_sincronizado_nuvem']} | data: {v['created_at']}")

conn.close()

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

# Get conflicts for fechamentos_caixa
cur.execute("""
    SELECT id, registro_id, dados_locais, dados_nuvem, resolvido, criado_em 
    FROM exodo_sync_conflitos 
    WHERE tabela = 'fechamentos_caixa' 
    ORDER BY criado_em DESC;
""")
print('Conflicts for fechamentos_caixa:')
for row in cur.fetchall():
    print(f"  • ID: {row[0]} | Registro ID: {row[1]} | Resolvido: {row[4]} | Criado em: {row[5]}")
    print(f"    Locais: {str(row[2])[:150]}")
    print(f"    Nuvem:  {str(row[3])[:150]}")
    print("-" * 50)

cur.close()
conn.close()

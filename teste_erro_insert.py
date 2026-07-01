import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
try:
    # Testando o insert normal
    cur.execute("INSERT INTO vendas_balcao (total) VALUES (50.0) RETURNING id")
    new_id = cur.fetchone()[0]
    conn.commit()
    print(f"Insert OK, ID = {new_id}")
    cur.execute(f"DELETE FROM vendas_balcao WHERE id='{new_id}'")
    conn.commit()
except Exception as e:
    print(f"Erro no insert normal: {e}")

try:
    # Testando sem nome de colunas (caso a aplicacao faca isso)
    cur.execute("SELECT count(*) FROM information_schema.columns WHERE table_name='vendas_balcao'")
    count = cur.fetchone()[0]
    print(f"Total de colunas na tabela: {count}")
except Exception as e:
    pass

conn.close()

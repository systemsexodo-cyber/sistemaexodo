import os, psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(
    host=os.getenv('DB_HOST','localhost'), port=os.getenv('DB_PORT','5432'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'), password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()
try:
    # Simula um insert na tabela vendas_balcao que o app faria
    cur.execute("INSERT INTO vendas_balcao (id) VALUES ('teste-insert-123')")
    conn.commit()
    print("Insert simulado com sucesso!")
except Exception as e:
    print(f"Erro ao inserir na tabela: {e}")
finally:
    cur.execute("DELETE FROM vendas_balcao WHERE id = 'teste-insert-123'")
    conn.commit()
    conn.close()

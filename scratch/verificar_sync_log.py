import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "exodo_db")
DB_USER = os.getenv("DB_USER", "exodo_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "ex@#$")

try:
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name, count(*) 
            FROM _exodo_sync_log 
            GROUP BY table_name 
            ORDER BY count(*) DESC
        """)
        rows = cur.fetchall()
        print("\n=== REGISTROS PENDENTES NO _exodo_sync_log ===")
        if not rows:
            print("Nenhum registro pendente.")
        for row in rows:
            print(f"  Tabela: {row[0]} | Quantidade: {row[1]}")
    conn.close()
except Exception as e:
    print(f"Erro ao conectar ou consultar: {e}")

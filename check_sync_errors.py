import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

db_host = os.getenv('DB_HOST', 'localhost')
db_port = os.getenv('DB_PORT', '5432')
db_name = os.getenv('DB_NAME')
db_user = os.getenv('DB_USER')
db_password = os.getenv('DB_PASSWORD')

try:
    conn = psycopg2.connect(
        host=db_host,
        port=int(db_port),
        database=db_name,
        user=db_user,
        password=db_password
    )
    cursor = conn.cursor()
    
    # Check conflicts
    cursor.execute("""
        SELECT tabela, COUNT(*) 
        FROM exodo_sync_conflitos 
        GROUP BY tabela;
    """)
    print("Conflicts by table:")
    for row in cursor.fetchall():
        print(f"  {row[0]}: {row[1]}")
        
    # Get last 10 conflicts for 'nfces' if any
    cursor.execute("""
        SELECT registro_id, dados_locais, dados_nuvem, resolvido, erro_mensagem 
        FROM exodo_sync_conflitos 
        WHERE tabela = 'nfces' 
        LIMIT 5;
    """)
    rows = cursor.fetchall()
    if rows:
        print("\nNFCes conflicts:")
        for r in rows:
            print(f"  ID: {r[0]} | Resolvido: {r[3]} | Erro: {r[4]}")
    else:
        print("\nNo conflicts for NFCes.")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

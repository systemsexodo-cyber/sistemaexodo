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
    
    # Query latest nfces
    cursor.execute("""
        SELECT id, numero, status, created_at
        FROM nfces 
        ORDER BY created_at DESC 
        LIMIT 10;
    """)
    rows = cursor.fetchall()
    print("\nLatest 10 rows:")
    for row in rows:
        print(f"  {row}")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

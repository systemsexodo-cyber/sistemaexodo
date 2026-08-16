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
    
    # Check if table exists
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'nfces'
        );
    """)
    exists = cursor.fetchone()[0]
    
    if exists:
        print("Altering 'nfces' column types to jsonb...")
        cursor.execute('ALTER TABLE nfces ALTER COLUMN itens TYPE jsonb USING itens::jsonb;')
        cursor.execute('ALTER TABLE nfces ALTER COLUMN pagamentos TYPE jsonb USING pagamentos::jsonb;')
        conn.commit()
        print("Successfully altered column types to jsonb!")
    else:
        print("Table 'nfces' does not exist.")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

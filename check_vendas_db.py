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
            AND table_name = 'vendas_balcao'
        );
    """)
    exists = cursor.fetchone()[0]
    print(f"Table 'vendas_balcao' exists: {exists}")
    
    if exists:
        # Get column details
        cursor.execute("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'vendas_balcao'
            ORDER BY ordinal_position;
        """)
        cols = cursor.fetchall()
        print("\nColumns in 'vendas_balcao':")
        for col in cols:
            print(f"  {col[0]}: {col[1]}")
            
        # Count rows
        cursor.execute("SELECT COUNT(*) FROM vendas_balcao;")
        count = cursor.fetchone()[0]
        print(f"\nRow count in 'vendas_balcao': {count}")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

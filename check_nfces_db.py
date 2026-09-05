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
    print(f"Table 'nfces' exists: {exists}")
    
    if exists:
        # Get column details
        cursor.execute("""
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'nfces'
            ORDER BY ordinal_position;
        """)
        cols = cursor.fetchall()
        print("\nColumns in 'nfces':")
        for col in cols:
            print(f"  {col[0]}: {col[1]}")
            
        # Count rows
        cursor.execute("SELECT COUNT(*) FROM nfces;")
        count = cursor.fetchone()[0]
        print(f"\nRow count in 'nfces': {count}")
        
        # Select first 5 rows
        cursor.execute("SELECT id, numero, status, created_at FROM nfces LIMIT 5;")
        rows = cursor.fetchall()
        print("\nFirst 5 rows:")
        for row in rows:
            print(f"  {row}")
            
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

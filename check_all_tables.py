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
    
    # Get all tables
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        ORDER BY table_name;
    """)
    tables = [t[0] for t in cursor.fetchall()]
    
    for table in tables:
        # Count rows
        cursor.execute(f'SELECT COUNT(*) FROM "{table}";')
        count = cursor.fetchone()[0]
        print(f"Table '{table}': {count} rows")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Error: {e}")

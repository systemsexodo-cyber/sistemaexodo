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
    
    # Query _exodo_sync_log columns
    cursor.execute("""
        SELECT COUNT(*) 
        FROM _exodo_sync_log 
        WHERE table_name = 'nfces';
    """)
    count = cursor.fetchone()[0]
    print(f"Sync log count for 'nfces': {count}")
    
    if count > 0:
        cursor.execute("""
            SELECT id, operation, record_id, created_at, processed, tries, last_error
            FROM _exodo_sync_log 
            WHERE table_name = 'nfces' 
            LIMIT 10;
        """)
        rows = cursor.fetchall()
        for r in rows:
            print(f"  Log: ID={r[0]} | Op={r[1]} | RegID={r[2]} | Proc={r[4]} | Err={r[6]}")
            
    # Also check if there are general errors in the sync log
    cursor.execute("""
        SELECT table_name, count(*), count(case when processed = false then 1 end), max(last_error)
        FROM _exodo_sync_log 
        WHERE processed = false OR last_error IS NOT NULL
        GROUP BY table_name;
    """)
    errors = cursor.fetchall()
    if errors:
        print("\nSync log errors by table:")
        for err in errors:
            print(f"  Table: {err[0]} | Total: {err[1]} | Pending: {err[2]} | Last Error: {err[3]}")
            
    cursor.close()
    conn.close()
except Exception as e:
    # If columns don't match, print columns first
    print(f"Error: {e}")
    try:
        cursor.execute("SELECT column_name FROM information_schema.columns WHERE table_name = '_exodo_sync_log';")
        cols = [r[0] for r in cursor.fetchall()]
        print(f"Columns in '_exodo_sync_log': {cols}")
        cursor.close()
        conn.close()
    except Exception as e2:
        print(f"Failed to describe: {e2}")

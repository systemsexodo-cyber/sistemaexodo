import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

cur.execute("""
    SELECT prosrc 
    FROM pg_proc 
    WHERE proname = 'log_sync_event';
""")

print("Source of log_sync_event:")
row = cur.fetchone()
if row:
    print(row[0])
else:
    print("Function not found.")

cur.close()
conn.close()

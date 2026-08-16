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

# Get count of sync log
cur.execute("SELECT COUNT(*) FROM _exodo_sync_log;")
print('Total rows in _exodo_sync_log:', cur.fetchone()[0])

# Get count grouped by table_name and operation
cur.execute("SELECT table_name, operation, COUNT(*) FROM _exodo_sync_log GROUP BY table_name, operation;")
print('\nSync logs by table and operation:')
for row in cur.fetchall():
    print(row)

# Get some recent entries
cur.execute("SELECT * FROM _exodo_sync_log ORDER BY created_at DESC LIMIT 10;")
print('\nRecent 10 entries in _exodo_sync_log:')
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()

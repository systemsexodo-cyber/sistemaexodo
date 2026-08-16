import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

try:
    conn = psycopg2.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', '5432')),
        database=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD')
    )
    cur = conn.cursor()
    cur.execute("SET session_replication_role = 'replica';")
    print("Successfully set session_replication_role to replica!")
    cur.execute("SET session_replication_role = 'origin';")
    print("Successfully set session_replication_role to origin!")
    cur.close()
    conn.close()
except Exception as e:
    print("Failed to set session_replication_role:", e)

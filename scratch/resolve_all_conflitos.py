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

# Update resolved status
cur.execute("UPDATE exodo_sync_conflitos SET resolvido = TRUE WHERE resolvido = FALSE;")
print(f"Conflicts resolved successfully: {cur.rowcount} row(s) updated.")
conn.commit()

cur.close()
conn.close()

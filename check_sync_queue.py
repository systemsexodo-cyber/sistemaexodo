import sqlite3
import os

db_path = os.path.expanduser('~/Documents/exodo_sync.db')
if not os.path.exists(db_path):
    db_path = 'exodo_sync.db'

print(f"Checking sync queue database: {db_path}")
if not os.path.exists(db_path):
    print("Sync database file does not exist!")
else:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = cur.fetchall()
    print("Tables:", [t[0] for t in tables])
    if ('sync_queue',) in tables:
        cur.execute("SELECT COUNT(*) FROM sync_queue")
        count = cur.fetchone()[0]
        print(f"Pending operations count: {count}")
        if count > 0:
            cur.execute("SELECT * FROM sync_queue ORDER BY rowid LIMIT 10")
            for r in cur.fetchall():
                print(r)
    else:
        print("sync_queue table does not exist!")
    conn.close()

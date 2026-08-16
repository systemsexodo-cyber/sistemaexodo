import psycopg
try:
    conn = psycopg.connect(host='127.0.0.1', port=5432, dbname='exodo_db', user='exodo_user', password='senha123')
    with conn.cursor() as cur:
        cur.execute("select current_database(), current_user")
        print(cur.fetchone())
        cur.execute("SET LOCAL exodo.sync_mode = 'off'")
        print('SET ok')
        cur.execute("SELECT * FROM information_schema.columns WHERE table_schema='public' AND table_name='produtos' LIMIT 1")
        print(cur.fetchone())
    conn.close()
except Exception:
    import traceback
    traceback.print_exc()

import psycopg2
try:
    conn = psycopg2.connect(
        host="db.febffvlpvxtiihvnfuts.supabase.co",
        port=5432,
        dbname="postgres",
        user="postgres",
        password="hmrzbdKJB6Bc4Vcr"
    )
    print("Conectado ao Supabase!")
    cur = conn.cursor()
    cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
    tables = [r[0] for r in cur.fetchall()]
    print("Tabelas:", tables)
    conn.close()
except Exception as e:
    print("Erro:", e)

#!/usr/bin/env python3
import psycopg2
from dotenv import load_dotenv
import os

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
        password=db_password,
        connect_timeout=10
    )
    print('✅ Conectado ao PostgreSQL local com sucesso!')
    
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")
    count = cursor.fetchone()[0]
    print(f'📊 Tabelas existentes: {count}')
    
    cursor.close()
    conn.close()
except Exception as e:
    print(f'❌ Erro: {e}')
    exit(1)

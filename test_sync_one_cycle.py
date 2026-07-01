#!/usr/bin/env python3
import os
import psycopg2
from dotenv import load_dotenv
from datetime import datetime, timezone
import sincronizar_local_supabase

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key      = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
db_host      = os.getenv('DB_HOST', 'localhost')
db_port      = os.getenv('DB_PORT', '5432')
db_name      = os.getenv('DB_NAME')
db_user      = os.getenv('DB_USER')
db_password  = os.getenv('DB_PASSWORD')

try:
    conn = psycopg2.connect(
        host=db_host, port=db_port,
        dbname=db_name, user=db_user, password=db_password,
        connect_timeout=10
    )
    print("Conectado localmente. Rodando um ciclo de teste...")
    
    sincronizar_local_supabase.garantir_tabela_controle(conn)
    
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema='public'
              AND table_type='BASE TABLE'
              AND LEFT(table_name, 1) <> '_'
              AND LEFT(table_name, 3) <> 'vw_'
              AND LEFT(table_name, 5) <> 'view_'
            ORDER BY table_name
        """)
        tabelas = [r[0] for r in cur.fetchall()]

    total_enviados  = 0
    total_recebidos = 0

    for tabela in tabelas:
        # Pular tabelas não-essenciais para teste rápido de vendas
        if tabela != 'vendas_balcao':
            continue
            
        ultima_sync_tabela = sincronizar_local_supabase.get_ultima_sync_tabela(conn, tabela)
        agora_iso = datetime.now(timezone.utc).isoformat()

        print(f"Sincronizando {tabela} desde {ultima_sync_tabela}...")
        
        # 1. DOWNLOAD
        recebidos, sucesso = sincronizar_local_supabase.download_tabela(conn, tabela, supabase_url, api_key, ultima_sync_tabela)
        if sucesso:
            sincronizar_local_supabase.salvar_ultima_sync_tabela(conn, tabela, agora_iso)
            total_recebidos += recebidos
            print(f"  -> Download {tabela}: {recebidos} recebidos, sucesso=True")
        else:
            print(f"  -> Download {tabela}: FALHA")

        # 2. UPLOAD
        enviados = sincronizar_local_supabase.upload_tabela(conn, tabela, supabase_url, api_key)
        total_enviados += enviados
        if enviados > 0:
            print(f"  -> Upload {tabela}: {enviados} enviados")

    conn.close()
    print(f"✅ Ciclo de teste concluído com sucesso: {total_enviados} enviados, {total_recebidos} recebidos")
except Exception as e:
    print(f"❌ Erro durante o ciclo de teste: {e}")
    import traceback
    traceback.print_exc()

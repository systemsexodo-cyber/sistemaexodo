import psycopg2
import os
from dotenv import load_dotenv

def main():
    load_dotenv()
    
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')

    if not all([db_name, db_user, db_password]):
        print("[-] Variaveis PostgreSQL nao configuradas no .env!")
        return

    print("[*] Conectando ao PostgreSQL local...")
    conn = psycopg2.connect(
        host=db_host, port=db_port, dbname=db_name, user=db_user, password=db_password
    )
    conn.autocommit = True
    cursor = conn.cursor()

    print("[*] Criando tabela de log (_exodo_sync_log)...")
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS _exodo_sync_log (
            id SERIAL PRIMARY KEY,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE (table_name, record_id)
        );
    """)

    print("[*] Criando tabela de conflitos (exodo_sync_conflitos)...")
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS exodo_sync_conflitos (
            id TEXT PRIMARY KEY,
            tabela TEXT NOT NULL,
            registro_id TEXT NOT NULL,
            dados_locais JSONB,
            dados_nuvem JSONB,
            resolvido BOOLEAN DEFAULT FALSE,
            empresa_id TEXT NOT NULL DEFAULT '',
            criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    print("[*] Criando funcao de trigger log_sync_event()...")
    cursor.execute("""
        CREATE OR REPLACE FUNCTION log_sync_event()
        RETURNS TRIGGER AS $$
        BEGIN
            -- Se o sincronizador estiver fazendo o insert/update, ignoramos (evita loop infinito)
            IF current_setting('exodo.sync_mode', true) = 'on' THEN
                IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
            END IF;

            -- Se for um UPDATE e nada mudou, ignora o log e notificação (evita loop de re-save do Flutter)
            IF TG_OP = 'UPDATE' AND (NEW IS NOT DISTINCT FROM OLD) THEN
                RETURN NEW;
            END IF;

            IF TG_OP = 'DELETE' THEN
                INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                VALUES (TG_TABLE_NAME, OLD.id::text, TG_OP)
                ON CONFLICT (table_name, record_id) 
                DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                
                PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                RETURN OLD;
            ELSE
                INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                VALUES (TG_TABLE_NAME, NEW.id::text, TG_OP)
                ON CONFLICT (table_name, record_id) 
                DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                
                PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                RETURN NEW;
            END IF;
        END;
        $$ LANGUAGE plpgsql;
    """)

    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_type = 'BASE TABLE'
        AND LEFT(table_name, 1) <> '_'
        AND LEFT(table_name, 3) <> 'vw_'
        AND LEFT(table_name, 5) <> 'view_'
        AND table_name NOT IN ('cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos')
    """)
    tabelas = [row[0] for row in cursor.fetchall()]

    print(f"[*] Encontradas {len(tabelas)} tabelas. Configurando triggers isolados...")

    # Remover explicitamente triggers obsoletos em tabelas e views que foram excluidas
    tabelas_excluidas = ['cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos', 'vw_historico_recente']
    for tabela_excl in tabelas_excluidas:
        cursor.execute(f'DROP TRIGGER IF EXISTS "trg_exodo_sync_log_{tabela_excl}" ON "{tabela_excl}";')

    for tabela in tabelas:
        # Pula a propria tabela de log e controle
        if tabela.startswith('_'):
            continue
            
        print(f"  -> Configurando trigger em: {tabela}")
        cursor.execute(f"""
            DROP TRIGGER IF EXISTS trg_exodo_sync_log_{tabela} ON "{tabela}";
            CREATE TRIGGER trg_exodo_sync_log_{tabela}
            AFTER INSERT OR UPDATE OR DELETE ON "{tabela}"
            FOR EACH ROW
            EXECUTE FUNCTION log_sync_event();
        """)

    print("[+] Configuracao concluida! O banco local esta com a fila de sincronizacao ativa.")

    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()

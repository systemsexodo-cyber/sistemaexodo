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

    print("[*] Criando tabela de apagados (_exodo_deletados)...")
    # Tombstones: guardam QUEM foi apagado e QUANDO. Sem eles a sincronizacao
    # entre os PCs da rede local nao enxerga o DELETE (a linha simplesmente
    # nao esta mais na tabela do par) e o outro PC reenviaria a linha antiga.
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS _exodo_deletados (
            id BIGSERIAL PRIMARY KEY,
            tabela TEXT NOT NULL,
            registro_id TEXT NOT NULL,
            empresa_id TEXT DEFAULT '',
            deletado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE (tabela, registro_id)
        );
    """)
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_exodo_deletados_busca
            ON _exodo_deletados (tabela, deletado_em);
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
        DECLARE
            rec_id text;
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
                rec_id := COALESCE(to_jsonb(OLD)->>'id', to_jsonb(OLD)->>'chave', to_jsonb(OLD)->>'key', to_jsonb(OLD)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id) 
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                    
                    -- Registra o apagado para a sincronizacao LAN. A checagem
                    -- de existencia protege instalacoes antigas (sem a tabela,
                    -- o DELETE continuaria funcionando normalmente).
                    IF to_regclass('public._exodo_deletados') IS NOT NULL THEN
                        INSERT INTO _exodo_deletados (tabela, registro_id, empresa_id, deletado_em)
                        VALUES (TG_TABLE_NAME, rec_id, COALESCE(to_jsonb(OLD)->>'empresa_id', ''), NOW())
                        ON CONFLICT (tabela, registro_id)
                        DO UPDATE SET deletado_em = NOW();
                    END IF;

                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN OLD;
            ELSE
                rec_id := COALESCE(to_jsonb(NEW)->>'id', to_jsonb(NEW)->>'chave', to_jsonb(NEW)->>'key', to_jsonb(NEW)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id) 
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                    
                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN NEW;
            END IF;
        END;
        $$ LANGUAGE plpgsql;
    """)

    print("[*] Criando funcao de trigger set_updated_at()...")
    # A sincronizacao entre os PCs (LAN) descobre o que mudou pela coluna de
    # data da tabela (updated_at). Varios models do app gravam sem tocar em
    # updated_at, entao a alteracao nunca era vista pelo outro PC e o dado so
    # chegava pela nuvem. Este trigger carimba updated_at em toda alteracao do
    # USUARIO, mantendo a LAN confiavel.
    #
    # NAO carimba quando o sincronizador esta aplicando replica
    # (exodo.sync_mode='on'): se carimbasse, a linha voltaria a parecer nova no
    # outro PC e as duas maquinas ficariam puxando a mesma linha eternamente.
    cursor.execute("""
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            IF current_setting('exodo.sync_mode', true) IS DISTINCT FROM 'on' THEN
                NEW.updated_at := NOW();
            END IF;
            RETURN NEW;
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
        AND table_name NOT IN ('cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos', 'exodo_config', 'sync_status', 'configuracoes_locais', 'sync_logs')
    """)
    tabelas = [row[0] for row in cursor.fetchall()]

    # Só as tabelas que TÊM a coluna updated_at recebem o trigger de carimbo.
    cursor.execute("""
        SELECT table_name FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name = 'updated_at'
    """)
    tabelas_com_updated_at = {row[0] for row in cursor.fetchall()}

    print(f"[*] Encontradas {len(tabelas)} tabelas. Configurando triggers isolados...")

    # Remover explicitamente triggers obsoletos em tabelas e views que foram excluidas
    tabelas_excluidas = ['cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos', 'vw_historico_recente', 'exodo_config', 'sync_status', 'configuracoes_locais', 'sync_logs']
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

        # Carimbo de updated_at (usado pela LAN para detectar mudancas).
        if tabela in tabelas_com_updated_at:
            cursor.execute(f"""
                DROP TRIGGER IF EXISTS trg_exodo_set_updated_at_{tabela} ON "{tabela}";
                CREATE TRIGGER trg_exodo_set_updated_at_{tabela}
                BEFORE UPDATE ON "{tabela}"
                FOR EACH ROW
                EXECUTE FUNCTION set_updated_at();
            """)

    print("[+] Configuracao concluida! O banco local esta com a fila de sincronizacao ativa.")

    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()

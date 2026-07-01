import psycopg2

def main():
    conn_str = "postgresql://postgres:hmrzbdKJB6Bc4Vcr@db.febffvlpvxtiihvnfuts.supabase.co:5432/postgres"
    print("Conectando ao banco de dados PostgreSQL do Supabase...")
    try:
        conn = psycopg2.connect(conn_str)
        with conn.cursor() as cur:
            # Criar a tabela se não existir
            print("Criando tabela bridge_config...")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS public.bridge_config (
                    id TEXT PRIMARY KEY,
                    version TEXT NOT NULL,
                    download_url TEXT NOT NULL,
                    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                );
            """)
            
            # Garantir permissão de leitura para todos e escrita/leitura pelo service role (PostgREST)
            cur.execute("ALTER TABLE public.bridge_config OWNER TO postgres;")
            cur.execute("GRANT ALL ON public.bridge_config TO authenticated;")
            cur.execute("GRANT ALL ON public.bridge_config TO anon;")
            cur.execute("GRANT ALL ON public.bridge_config TO service_role;")
            
            # Inserir registros iniciais se não existirem
            print("Inserindo registros iniciais...")
            cur.execute("""
                INSERT INTO public.bridge_config (id, version, download_url)
                VALUES ('app_latest', '1.0.8', '')
                ON CONFLICT (id) DO NOTHING;
            """)
            cur.execute("""
                INSERT INTO public.bridge_config (id, version, download_url)
                VALUES ('latest', '1.0.0', '')
                ON CONFLICT (id) DO NOTHING;
            """)
            cur.execute("""
                INSERT INTO public.bridge_config (id, version, download_url)
                VALUES ('sync_latest', '1.0.0', '')
                ON CONFLICT (id) DO NOTHING;
            """)
            
        conn.commit()
        conn.close()
        print("✅ Tabela bridge_config criada e configurada no Supabase com sucesso!")
    except Exception as e:
        print("❌ Erro ao conectar/configurar banco:", e)

if __name__ == "__main__":
    main()

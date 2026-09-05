-- ==========================================================================
-- SCRIPT DE CRIAÇÃO DA TABELA DE CONFIGURAÇÃO DE ATUALIZAÇÃO NO SUPABASE
-- ==========================================================================
-- Execute este script no SQL Editor do seu console do Supabase.
-- Ele cria a tabela bridge_config para gerenciar as versões e links de
-- download do Emissor (Bridge), do App Flutter e do Sincronizador.
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.bridge_config (
    id TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    download_url TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS (Row Level Security)
ALTER TABLE public.bridge_config ENABLE ROW LEVEL SECURITY;

-- Políticas de acesso
DROP POLICY IF EXISTS bridge_config_permitir_autenticado ON public.bridge_config;
CREATE POLICY bridge_config_permitir_autenticado ON public.bridge_config 
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS bridge_config_permitir_anon ON public.bridge_config;
CREATE POLICY bridge_config_permitir_anon ON public.bridge_config 
    FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS bridge_config_admin ON public.bridge_config;
CREATE POLICY bridge_config_admin ON public.bridge_config 
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Inserir dados padrão de controle de versão
INSERT INTO public.bridge_config (id, version, download_url)
VALUES 
    ('app_latest', '1.0.8', ''),
    ('latest', '1.0.0', ''),
    ('sync_latest', '1.0.0', '')
ON CONFLICT (id) DO NOTHING;

-- Dar privilégios explícitos ao PostgREST para o schema public
GRANT ALL ON TABLE public.bridge_config TO postgres;
GRANT ALL ON TABLE public.bridge_config TO anon;
GRANT ALL ON TABLE public.bridge_config TO authenticated;
GRANT ALL ON TABLE public.bridge_config TO service_role;

COMMENT ON TABLE public.bridge_config IS 'Tabela que armazena links de atualizações e versões do ecossistema Êxodo.';

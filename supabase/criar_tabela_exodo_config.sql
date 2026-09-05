-- TABELA: exodo_config
CREATE TABLE IF NOT EXISTS public.exodo_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id TEXT NOT NULL DEFAULT '',
    pc_name TEXT NOT NULL DEFAULT '',
    chave TEXT NOT NULL DEFAULT '',
    valor TEXT NOT NULL DEFAULT '',
    tipo TEXT DEFAULT 'texto',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_exodo_config_empresa_pc_chave UNIQUE (empresa_id, pc_name, chave)
);

CREATE INDEX IF NOT EXISTS idx_exodo_config_empresa_id ON public.exodo_config(empresa_id);
CREATE INDEX IF NOT EXISTS idx_exodo_config_pc_name ON public.exodo_config(pc_name);
CREATE INDEX IF NOT EXISTS idx_exodo_config_chave ON public.exodo_config(chave);

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION public.update_exodo_config_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_exodo_config_updated_at ON public.exodo_config;
CREATE TRIGGER trigger_exodo_config_updated_at
    BEFORE UPDATE ON public.exodo_config
    FOR EACH ROW
    EXECUTE FUNCTION public.update_exodo_config_updated_at();

-- RLS
ALTER TABLE public.exodo_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY exodo_config_anon_select ON public.exodo_config
    FOR SELECT TO anon USING (true);
CREATE POLICY exodo_config_anon_insert ON public.exodo_config
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY exodo_config_anon_update ON public.exodo_config
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY exodo_config_anon_delete ON public.exodo_config
    FOR DELETE TO anon USING (true);

CREATE POLICY exodo_config_auth_select ON public.exodo_config
    FOR SELECT TO authenticated USING (true);
CREATE POLICY exodo_config_auth_insert ON public.exodo_config
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY exodo_config_auth_update ON public.exodo_config
    FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

GRANT ALL ON public.exodo_config TO anon;
GRANT ALL ON public.exodo_config TO authenticated;
GRANT ALL ON public.exodo_config TO service_role;

-- TABELA: bridge_config (fallback)
CREATE TABLE IF NOT EXISTS public.bridge_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id TEXT NOT NULL DEFAULT '',
    pc_name TEXT NOT NULL DEFAULT '',
    config JSONB DEFAULT '{}'::jsonb,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bridge_config_empresa_id ON public.bridge_config(empresa_id);
CREATE INDEX IF NOT EXISTS idx_bridge_config_pc_name ON public.bridge_config(pc_name);

ALTER TABLE public.bridge_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY bridge_config_anon_select ON public.bridge_config
    FOR SELECT TO anon USING (true);
CREATE POLICY bridge_config_anon_insert ON public.bridge_config
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY bridge_config_anon_update ON public.bridge_config
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY bridge_config_anon_delete ON public.bridge_config
    FOR DELETE TO anon USING (true);

GRANT ALL ON public.bridge_config TO anon;
GRANT ALL ON public.bridge_config TO authenticated;
GRANT ALL ON public.bridge_config TO service_role;

-- Dados iniciais
INSERT INTO public.exodo_config (empresa_id, pc_name, chave, valor, tipo)
VALUES 
    ('22ae2c16-a730-43f3-a4f9-19f105eb0d13', 'LOCAL', 'versao_bridge', '1.0.0', 'texto'),
    ('22ae2c16-a730-43f3-a4f9-19f105eb0d13', 'LOCAL', 'ultima_sincronizacao', NOW()::text, 'texto'),
    ('22ae2c16-a730-43f3-a4f9-19f105eb0d13', 'LOCAL', 'ambiente', 'homologacao', 'texto')
ON CONFLICT (empresa_id, pc_name, chave)
DO UPDATE SET valor = EXCLUDED.valor, updated_at = NOW();

SELECT 'OK - Tabelas criadas' AS resultado;

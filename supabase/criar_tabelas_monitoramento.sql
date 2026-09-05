-- ============================================================
-- TABELAS DE MONITORAMENTO DE SINCRONIZACAO
-- ============================================================
-- sync_logs:     registro detalhado de eventos de sync
-- sync_status:   resumo do status atual por empresa
-- ============================================================

-- 1. sync_logs: Historico de eventos de sincronizacao
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id TEXT NOT NULL DEFAULT '',
    pc_name TEXT NOT NULL DEFAULT '',
    evento TEXT NOT NULL DEFAULT '',
    detalhes TEXT DEFAULT '',
    erro TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_empresa_id ON public.sync_logs(empresa_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_created_at ON public.sync_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_logs_evento ON public.sync_logs(evento);

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY sync_logs_anon_insert ON public.sync_logs
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY sync_logs_anon_select ON public.sync_logs
    FOR SELECT TO anon USING (true);
CREATE POLICY sync_logs_auth_select ON public.sync_logs
    FOR SELECT TO authenticated USING (true);
CREATE POLICY sync_logs_auth_insert ON public.sync_logs
    FOR INSERT TO authenticated WITH CHECK (true);

GRANT ALL ON public.sync_logs TO anon;
GRANT ALL ON public.sync_logs TO authenticated;
GRANT ALL ON public.sync_logs TO service_role;

-- 2. sync_status: Status atual da sincronizacao por empresa
CREATE TABLE IF NOT EXISTS public.sync_status (
    empresa_id TEXT PRIMARY KEY,
    pc_name TEXT NOT NULL DEFAULT '',
    ultima_sincronizacao TIMESTAMPTZ,
    ultimo_erro TEXT DEFAULT '',
    ultimo_erro_data TIMESTAMPTZ,
    fila_pendente INT DEFAULT 0,
    versao_app TEXT DEFAULT '',
    online BOOLEAN DEFAULT false,
    online_data TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_status_online ON public.sync_status(online);
CREATE INDEX IF NOT EXISTS idx_sync_status_updated ON public.sync_status(updated_at DESC);

ALTER TABLE public.sync_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY sync_status_anon_select ON public.sync_status
    FOR SELECT TO anon USING (true);
CREATE POLICY sync_status_anon_insert ON public.sync_status
    FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY sync_status_anon_update ON public.sync_status
    FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY sync_status_auth_select ON public.sync_status
    FOR SELECT TO authenticated USING (true);
CREATE POLICY sync_status_auth_insert ON public.sync_status
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY sync_status_auth_update ON public.sync_status
    FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

GRANT ALL ON public.sync_status TO anon;
GRANT ALL ON public.sync_status TO authenticated;
GRANT ALL ON public.sync_status TO service_role;

-- Trigger para atualizar updated_at
CREATE OR REPLACE FUNCTION public.update_sync_status_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_sync_status_updated_at ON public.sync_status;
CREATE TRIGGER trigger_sync_status_updated_at
    BEFORE UPDATE ON public.sync_status
    FOR EACH ROW
    EXECUTE FUNCTION public.update_sync_status_updated_at();

SELECT 'OK - Tabelas sync_logs e sync_status criadas' AS resultado;

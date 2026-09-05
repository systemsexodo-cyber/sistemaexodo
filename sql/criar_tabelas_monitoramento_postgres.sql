-- ============================================================
-- CRIAR TABELAS DE MONITORAMENTO NO POSTGRESQL LOCAL
-- ============================================================
-- Execute este script no PostgreSQL local (pgAdmin ou psql)
-- para criar as tabelas de monitoramento de sincronizacao.
-- ============================================================

-- Tabela de historico de eventos de sync
CREATE TABLE IF NOT EXISTS sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id TEXT NOT NULL DEFAULT '',
    pc_name TEXT NOT NULL DEFAULT '',
    evento TEXT NOT NULL DEFAULT '',
    detalhes TEXT DEFAULT '',
    erro TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_empresa_id ON sync_logs(empresa_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_created_at ON sync_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_logs_evento ON sync_logs(evento);

-- Tabela de status atual por empresa
CREATE TABLE IF NOT EXISTS sync_status (
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

CREATE INDEX IF NOT EXISTS idx_sync_status_online ON sync_status(online);
CREATE INDEX IF NOT EXISTS idx_sync_status_updated ON sync_status(updated_at DESC);

SELECT 'OK - Tabelas sync_logs e sync_status criadas no PostgreSQL local' AS resultado;

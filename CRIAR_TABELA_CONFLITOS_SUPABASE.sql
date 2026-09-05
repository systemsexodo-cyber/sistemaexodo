-- ==========================================================================
-- SCRIPT DE CRIAÇÃO DA TABELA DE CONFLITOS NO SUPABASE
-- ==========================================================================
-- Execute este script no SQL Editor do Supabase para criar a tabela
-- de logs e auditoria de conflitos de sincronização.
-- ==========================================================================

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

-- Habilitar RLS (Row Level Security)
ALTER TABLE exodo_sync_conflitos ENABLE ROW LEVEL SECURITY;

-- Criar políticas de acesso
DROP POLICY IF EXISTS exodo_sync_conflitos_permitir_autenticado ON exodo_sync_conflitos;
CREATE POLICY exodo_sync_conflitos_permitir_autenticado ON exodo_sync_conflitos FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS exodo_sync_conflitos_admin ON exodo_sync_conflitos;
CREATE POLICY exodo_sync_conflitos_admin ON exodo_sync_conflitos FOR ALL TO service_role USING (true) WITH CHECK (true);

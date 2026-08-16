-- ==========================================================================
-- BLINDAGEM DA TABELA usuarios - SISTEMA ÊXODO
-- ==========================================================================
-- Execute este script no SQL Editor do Supabase (Dashboard > SQL Editor).
-- Adiciona as colunas do perfil completo (incluindo senha) que o app envia.
-- Com isso, o perfil do usuário (nome, senha, permissões, série NFC-e etc.)
-- é gravado na nuvem de forma COMPLETA — mesmo que o app local seja perdido,
-- o usuário pode ser recuperado integralmente do Supabase.
-- ==========================================================================

ALTER TABLE usuarios
    ADD COLUMN IF NOT EXISTS senha TEXT,
    ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'operador',
    ADD COLUMN IF NOT EXISTS is_master BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS funcionario_id TEXT,
    ADD COLUMN IF NOT EXISTS serie_nfce INTEGER DEFAULT 1,
    ADD COLUMN IF NOT EXISTS telefone TEXT,
    ADD COLUMN IF NOT EXISTS foto_url TEXT,
    ADD COLUMN IF NOT EXISTS ultimo_acesso TEXT,
    ADD COLUMN IF NOT EXISTS permissoes_personalizadas JSONB,
    ADD COLUMN IF NOT EXISTS permissoes_negadas JSONB,
    ADD COLUMN IF NOT EXISTS telas_ocultas JSONB;

-- Garantir RLS aberta para o app (service_role + authenticated com política ampla)
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS usuarios_permitir_app ON usuarios;
CREATE POLICY usuarios_permitir_app ON usuarios
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS usuarios_permitir_service ON usuarios;
CREATE POLICY usuarios_permitir_service ON usuarios
    FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE usuarios IS 'Usuários do sistema (perfil completo). Conta de login fica no Supabase Auth.';

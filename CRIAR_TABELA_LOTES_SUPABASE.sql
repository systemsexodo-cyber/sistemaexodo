-- ==========================================================================
-- CRIAR TABELA lotes_produto NO SUPABASE (Sistema Êxodo)
-- ==========================================================================
-- Como usar: abra o SQL Editor do seu projeto no painel do Supabase
-- (https://supabase.com/dashboard/project/SEU_PROJETO/sql/new),
-- cole TODO este script e clique em "Run".
-- É seguro rodar mais de uma vez (usa IF NOT EXISTS).
-- ==========================================================================

-- Tabela de lotes por produto. A baixa de estoque nas vendas segue FEFO
-- (vence antes, sai antes). O lote fica atrelado ao fornecedor da entrada.
CREATE TABLE IF NOT EXISTS lotes_produto (
    id TEXT PRIMARY KEY,
    produto_id TEXT,
    numero_lote TEXT,
    fornecedor_id TEXT,
    fornecedor_nome TEXT,
    data_fabricacao TIMESTAMP WITH TIME ZONE,
    data_validade TIMESTAMP WITH TIME ZONE,
    quantidade NUMERIC DEFAULT 0,
    empresa_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para consulta rápida de validade/vencimento
CREATE INDEX IF NOT EXISTS idx_lotes_produto_produto_id ON lotes_produto(produto_id);
CREATE INDEX IF NOT EXISTS idx_lotes_produto_data_validade ON lotes_produto(data_validade);
CREATE INDEX IF NOT EXISTS idx_lotes_produto_empresa_id ON lotes_produto(empresa_id);

-- RLS: acesso via app autenticado e via service_role
ALTER TABLE lotes_produto ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lotes_produto_permitir_autenticado ON lotes_produto;
CREATE POLICY lotes_produto_permitir_autenticado ON lotes_produto
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS lotes_produto_admin ON lotes_produto;
CREATE POLICY lotes_produto_admin ON lotes_produto
    FOR ALL TO service_role USING (true) WITH CHECK (true);

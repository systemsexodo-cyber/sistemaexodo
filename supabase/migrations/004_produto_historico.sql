-- ============================================================
-- TABELA DE HISTÓRICO DE PRODUTOS (AUDITORIA)
-- ============================================================
-- Execute este SQL no Supabase SQL Editor

-- Criar tabela sem foreign keys complexas (compatível com seu schema)
CREATE TABLE IF NOT EXISTS produto_historico (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL,
    produto_id TEXT NOT NULL,
    produto_nome TEXT,
    produto_codigo TEXT,
    usuario_id TEXT,
    usuario_nome TEXT NOT NULL DEFAULT 'Sistema',
    usuario_email TEXT,
    tipo_operacao TEXT NOT NULL CHECK (tipo_operacao IN ('CREATE', 'UPDATE', 'DELETE')),
    campos_alterados TEXT,
    valores_anteriores JSONB,
    valores_novos JSONB,
    resumo_mudancas TEXT,
    data_alteracao TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Índices para consultas rápidas
CREATE INDEX IF NOT EXISTS idx_produto_historico_empresa ON produto_historico(empresa_id);
CREATE INDEX IF NOT EXISTS idx_produto_historico_produto ON produto_historico(produto_id);
CREATE INDEX IF NOT EXISTS idx_produto_historico_data ON produto_historico(data_alteracao DESC);
CREATE INDEX IF NOT EXISTS idx_produto_historico_usuario ON produto_historico(usuario_id);
CREATE INDEX IF NOT EXISTS idx_produto_historico_tipo ON produto_historico(tipo_operacao);

-- Trigger para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_produto_historico_updated_at ON produto_historico;
CREATE TRIGGER update_produto_historico_updated_at
    BEFORE UPDATE ON produto_historico
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Habilitar RLS
ALTER TABLE produto_historico ENABLE ROW LEVEL SECURITY;

-- Políticas básicas
DROP POLICY IF EXISTS "select_empresa" ON produto_historico;
CREATE POLICY "select_empresa"
ON produto_historico
FOR SELECT
TO authenticated
USING (empresa_id = current_setting('app.current_empresa_id', true)::TEXT);

DROP POLICY IF EXISTS "insert_empresa" ON produto_historico;
CREATE POLICY "insert_empresa"
ON produto_historico
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Função para limpar histórico antigo
CREATE OR REPLACE FUNCTION limpar_historico_antigo(dias INTEGER DEFAULT 365)
RETURNS INTEGER AS $$
DECLARE
    registros_removidos INTEGER;
BEGIN
    DELETE FROM produto_historico 
    WHERE data_alteracao < (now() - (dias || ' days')::INTERVAL);
    
    GET DIAGNOSTICS registros_removidos = ROW_COUNT;
    RETURN registros_removidos;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Views úteis
DROP VIEW IF EXISTS vw_historico_resumo_produto;
CREATE VIEW vw_historico_resumo_produto AS
SELECT 
    produto_id,
    produto_nome,
    empresa_id,
    COUNT(*) as total_alteracoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'CREATE') as total_criacoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'UPDATE') as total_atualizacoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'DELETE') as total_exclusoes,
    MAX(data_alteracao) as ultima_alteracao,
    MIN(data_alteracao) as primeira_alteracao
FROM produto_historico
GROUP BY produto_id, produto_nome, empresa_id;

DROP VIEW IF EXISTS vw_historico_recente;
CREATE VIEW vw_historico_recente AS
SELECT *
FROM produto_historico
WHERE data_alteracao >= (now() - interval '30 days')
ORDER BY data_alteracao DESC;

DROP VIEW IF EXISTS vw_historico_por_usuario;
CREATE VIEW vw_historico_por_usuario AS
SELECT 
    usuario_id,
    usuario_nome,
    empresa_id,
    COUNT(*) as total_acoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'CREATE') as criacoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'UPDATE') as atualizacoes,
    COUNT(*) FILTER (WHERE tipo_operacao = 'DELETE') as exclusoes,
    MAX(data_alteracao) as ultima_acao
FROM produto_historico
GROUP BY usuario_id, usuario_nome, empresa_id;

-- Permissões
GRANT ALL ON produto_historico TO service_role;
GRANT ALL ON vw_historico_resumo_produto TO service_role;
GRANT ALL ON vw_historico_recente TO service_role;
GRANT ALL ON vw_historico_por_usuario TO service_role;
GRANT SELECT ON vw_historico_resumo_produto TO authenticated;
GRANT SELECT ON vw_historico_recente TO authenticated;
GRANT SELECT ON vw_historico_por_usuario TO authenticated;

SELECT 'Tabela produto_historico criada com sucesso!' as status;

-- ==========================================================================
-- SCRIPT DE CRIAÇÃO DAS TABELAS MAIS RECENTES NO SUPABASE
-- ==========================================================================
-- Execute este script no SQL Editor do Supabase para criar as tabelas
-- referentes a Vendas, Histórico e Trocas/Devoluções.
-- ==========================================================================

-- 1. PRODUTO HISTÓRICO
CREATE TABLE IF NOT EXISTS produto_historico (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    produto_id TEXT NOT NULL,
    produto_nome TEXT,
    produto_codigo TEXT,
    usuario_id TEXT,
    usuario_nome TEXT,
    usuario_email TEXT,
    tipo_operacao TEXT NOT NULL, -- CREATE, UPDATE, DELETE
    campos_alterados TEXT, -- Separados por vírgula
    valores_anteriores JSONB,
    valores_novos JSONB,
    resumo_mudancas TEXT,
    data_alteracao TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS e criar políticas para produto_historico
ALTER TABLE produto_historico ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS produto_historico_permitir_autenticado ON produto_historico;
CREATE POLICY produto_historico_permitir_autenticado ON produto_historico FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS produto_historico_admin ON produto_historico;
CREATE POLICY produto_historico_admin ON produto_historico FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 2. ESTOQUE HISTÓRICO
CREATE TABLE IF NOT EXISTS estoque_historico (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    produto_id TEXT NOT NULL,
    data TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    quantidade NUMERIC NOT NULL,
    tipo TEXT,
    observacao TEXT,
    usuario TEXT,
    fornecedor_nome TEXT
);

-- Habilitar RLS e criar políticas para estoque_historico
ALTER TABLE estoque_historico ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS estoque_historico_permitir_autenticado ON estoque_historico;
CREATE POLICY estoque_historico_permitir_autenticado ON estoque_historico FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS estoque_historico_admin ON estoque_historico;
CREATE POLICY estoque_historico_admin ON estoque_historico FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 3. VENDAS BALCÃO
CREATE TABLE IF NOT EXISTS vendas_balcao (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT,
    data_venda TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    cliente_id TEXT,
    cliente_nome TEXT,
    cliente_telefone TEXT,
    cliente_cpf_cnpj TEXT,
    itens JSONB DEFAULT '[]'::jsonb,
    tipo_pagamento TEXT,
    valor_total NUMERIC DEFAULT 0,
    valor_recebido NUMERIC,
    troco NUMERIC,
    operador TEXT,
    vendedor_id TEXT,
    vendedor_nome TEXT,
    origem TEXT,
    observacoes TEXT,
    cancelado BOOLEAN DEFAULT FALSE,
    delivery_info JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS e criar políticas para vendas_balcao
ALTER TABLE vendas_balcao ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS vendas_balcao_permitir_autenticado ON vendas_balcao;
CREATE POLICY vendas_balcao_permitir_autenticado ON vendas_balcao FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS vendas_balcao_admin ON vendas_balcao;
CREATE POLICY vendas_balcao_admin ON vendas_balcao FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 4. TROCAS E DEVOLUÇÕES
CREATE TABLE IF NOT EXISTS trocas_devolucoes (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT,
    pedido_id TEXT,
    numero_pedido TEXT,
    tipo TEXT, -- 'troca' ou 'devolucao'
    cliente_id TEXT,
    cliente_nome TEXT,
    itens_devolvidos JSONB DEFAULT '[]'::jsonb,
    itens_novos JSONB,
    valor_devolvido NUMERIC DEFAULT 0,
    valor_novo NUMERIC DEFAULT 0,
    diferenca NUMERIC DEFAULT 0,
    status TEXT,
    motivo TEXT,
    data_operacao TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS e criar políticas para trocas_devolucoes
ALTER TABLE trocas_devolucoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS trocas_devolucoes_permitir_autenticado ON trocas_devolucoes;
CREATE POLICY trocas_devolucoes_permitir_autenticado ON trocas_devolucoes FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS trocas_devolucoes_admin ON trocas_devolucoes;
CREATE POLICY trocas_devolucoes_admin ON trocas_devolucoes FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 5. MOTORISTAS
CREATE TABLE IF NOT EXISTS motoristas (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT NOT NULL,
    telefone TEXT,
    placa_veiculo TEXT,
    tipo_veiculo TEXT,
    ativo BOOLEAN DEFAULT TRUE,
    taxa_padrao NUMERIC,
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS e criar políticas para motoristas
ALTER TABLE motoristas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS motoristas_permitir_autenticado ON motoristas;
CREATE POLICY motoristas_permitir_autenticado ON motoristas FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS motoristas_admin ON motoristas;
CREATE POLICY motoristas_admin ON motoristas FOR ALL TO service_role USING (true) WITH CHECK (true);


-- 6. TAXAS DE ENTREGA
CREATE TABLE IF NOT EXISTS taxas_entrega (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    bairro TEXT NOT NULL,
    cidade TEXT,
    valor NUMERIC NOT NULL DEFAULT 0,
    ativo BOOLEAN DEFAULT TRUE,
    prazo_estimado TEXT
);

-- Habilitar RLS e criar políticas para taxas_entrega
ALTER TABLE taxas_entrega ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS taxas_entrega_permitir_autenticado ON taxas_entrega;
CREATE POLICY taxas_entrega_permitir_autenticado ON taxas_entrega FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS taxas_entrega_admin ON taxas_entrega;
CREATE POLICY taxas_entrega_admin ON taxas_entrega FOR ALL TO service_role USING (true) WITH CHECK (true);


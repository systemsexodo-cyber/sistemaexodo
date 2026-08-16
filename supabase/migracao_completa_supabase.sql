-- ============================================================
-- MIGRACAO COMPLETA - SUPABASE
-- ============================================================
-- Cria TODAS as tabelas necessarias para o sistema Exodo no Supabase
-- Execute APENAS no Supabase SQL Editor
-- Use comparar_tabelas.sql primeiro para ver o que ja existe
-- ============================================================

-- 0. GARANTIR COLUNA empresa_id EM TABELAS EXISTENTES
DO $$
DECLARE
    tabela TEXT;
    tabelas TEXT[] := ARRAY[
        'produtos', 'clientes', 'vendas_balcao', 'pedidos',
        'produto_historico', 'estoque_historico', 'aberturas_caixa',
        'fechamentos_caixa', 'sangrias_caixa', 'suprimentos_caixa',
        'notas_entrada', 'ordens_servico', 'servicos', 'funcionarios',
        'contas_pagar', 'entregas', 'motoristas', 'taxas_entrega',
        'romaneios', 'mesas_comandas', 'agendamentos_servico',
        'trocas_devolucoes', 'comissoes_vendedores', 'links_vendedores',
        'nfces', 'usuarios'
    ];
BEGIN
    FOREACH tabela IN ARRAY tabelas
    LOOP
        BEGIN
            EXECUTE format($f$ALTER TABLE IF EXISTS %I ADD COLUMN IF NOT EXISTS empresa_id TEXT NOT NULL DEFAULT ''$f$, tabela);
            RAISE NOTICE 'Coluna empresa_id garantida em: %', tabela;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Aviso em %: %', tabela, SQLERRM;
        END;
    END LOOP;
END $$;

-- ============================================================
-- 1. EMPRESAS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.empresas (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    razao_social TEXT DEFAULT '',
    nome_fantasia TEXT DEFAULT '',
    cnpj TEXT DEFAULT '',
    crt TEXT DEFAULT '',
    email TEXT DEFAULT '',
    telefone TEXT DEFAULT '',
    celular TEXT DEFAULT '',
    site TEXT DEFAULT '',
    endereco TEXT DEFAULT '',
    numero TEXT DEFAULT '',
    complemento TEXT DEFAULT '',
    bairro TEXT DEFAULT '',
    cidade TEXT DEFAULT '',
    estado TEXT DEFAULT '',
    cep TEXT DEFAULT '',
    ativo BOOLEAN DEFAULT true,
    slug TEXT DEFAULT '',
    logo_url TEXT DEFAULT '',
    cor_primaria TEXT DEFAULT '#1E3A5F',
    cor_secundaria TEXT DEFAULT '#2E86C1',
    configuracoes JSONB DEFAULT '{}'::jsonb,
    perfis_de_preco JSONB DEFAULT '[]'::jsonb,
    telas_permitidas JSONB DEFAULT '[]'::jsonb,
    inscricao_estadual TEXT DEFAULT '',
    inscricao_municipal TEXT DEFAULT '',
    codigo_ibge TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. PRODUTOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.produtos (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT DEFAULT '',
    codigo TEXT DEFAULT '',
    descricao TEXT DEFAULT '',
    preco NUMERIC(15,2) DEFAULT 0,
    custo NUMERIC(15,2) DEFAULT 0,
    estoque NUMERIC(15,3) DEFAULT 0,
    unidade TEXT DEFAULT 'UN',
    ncm TEXT DEFAULT '',
    cest TEXT DEFAULT '',
    cfop TEXT DEFAULT '',
    csosn TEXT DEFAULT '',
    ativo BOOLEAN DEFAULT true,
    tipo TEXT DEFAULT 'produto',
    envia_balanca BOOLEAN DEFAULT false,
    perfil_tributario_id TEXT DEFAULT '',
    precos_por_perfil JSONB DEFAULT '[]'::jsonb,
    regras_quantidade JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON public.produtos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON public.produtos(codigo);
CREATE INDEX IF NOT EXISTS idx_produtos_nome ON public.produtos(nome);
ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. CLIENTES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.clientes (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT DEFAULT '',
    cpf_cnpj TEXT DEFAULT '',
    rg_ie TEXT DEFAULT '',
    email TEXT DEFAULT '',
    telefone TEXT DEFAULT '',
    celular TEXT DEFAULT '',
    endereco TEXT DEFAULT '',
    numero TEXT DEFAULT '',
    complemento TEXT DEFAULT '',
    bairro TEXT DEFAULT '',
    cidade TEXT DEFAULT '',
    estado TEXT DEFAULT '',
    cep TEXT DEFAULT '',
    perfil_preco TEXT DEFAULT '',
    observacoes TEXT DEFAULT '',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON public.clientes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_clientes_nome ON public.clientes(nome);
ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. VENDAS_BALCAO (PDV)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.vendas_balcao (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    cliente_id TEXT DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    vendedor_id TEXT DEFAULT '',
    vendedor_nome TEXT DEFAULT '',
    items JSONB DEFAULT '[]'::jsonb,
    subtotal NUMERIC(15,2) DEFAULT 0,
    desconto NUMERIC(15,2) DEFAULT 0,
    acrescimo NUMERIC(15,2) DEFAULT 0,
    total NUMERIC(15,2) DEFAULT 0,
    forma_pagamento TEXT DEFAULT '',
    status TEXT DEFAULT 'finalizada',
    senha TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa_id ON public.vendas_balcao(empresa_id);
ALTER TABLE public.vendas_balcao ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. PEDIDOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pedidos (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    cliente_id TEXT DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    vendedor_id TEXT DEFAULT '',
    vendedor_nome TEXT DEFAULT '',
    items JSONB DEFAULT '[]'::jsonb,
    subtotal NUMERIC(15,2) DEFAULT 0,
    desconto NUMERIC(15,2) DEFAULT 0,
    total NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'aberto',
    tipo TEXT DEFAULT 'mesa',
    senha TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_id ON public.pedidos(empresa_id);
ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. PRODUTO_HISTORICO
-- ============================================================
CREATE TABLE IF NOT EXISTS public.produto_historico (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    produto_id TEXT NOT NULL DEFAULT '',
    produto_nome TEXT DEFAULT '',
    produto_codigo TEXT DEFAULT '',
    usuario_id TEXT DEFAULT '',
    usuario_nome TEXT NOT NULL DEFAULT 'Sistema',
    usuario_email TEXT DEFAULT '',
    tipo_operacao TEXT NOT NULL DEFAULT 'UPDATE',
    campos_alterados TEXT DEFAULT '',
    valores_anteriores JSONB DEFAULT '{}'::jsonb,
    valores_novos JSONB DEFAULT '{}'::jsonb,
    resumo_mudancas TEXT DEFAULT '',
    data_alteracao TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_produto_historico_empresa ON public.produto_historico(empresa_id);
CREATE INDEX IF NOT EXISTS idx_produto_historico_produto ON public.produto_historico(produto_id);
CREATE INDEX IF NOT EXISTS idx_produto_historico_data ON public.produto_historico(data_alteracao DESC);
ALTER TABLE public.produto_historico ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 7. ESTOQUE_HISTORICO
-- ============================================================
CREATE TABLE IF NOT EXISTS public.estoque_historico (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    produto_id TEXT DEFAULT '',
    produto_nome TEXT DEFAULT '',
    tipo TEXT DEFAULT 'entrada',
    quantidade NUMERIC(15,3) DEFAULT 0,
    saldo_anterior NUMERIC(15,3) DEFAULT 0,
    saldo_posterior NUMERIC(15,3) DEFAULT 0,
    observacao TEXT DEFAULT '',
    usuario_nome TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa_id ON public.estoque_historico(empresa_id);
ALTER TABLE public.estoque_historico ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 8. ABERTURAS_CAIXA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.aberturas_caixa (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    usuario_nome TEXT DEFAULT '',
    valor_inicial NUMERIC(15,2) DEFAULT 0,
    data_abertura TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'aberto',
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.aberturas_caixa ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 9. FECHAMENTOS_CAIXA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.fechamentos_caixa (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    abertura_caixa_id TEXT DEFAULT '',
    usuario_nome TEXT DEFAULT '',
    valor_em_caixa NUMERIC(15,2) DEFAULT 0,
    valor_em_vendas NUMERIC(15,2) DEFAULT 0,
    valor_em_despesas NUMERIC(15,2) DEFAULT 0,
    diferenca NUMERIC(15,2) DEFAULT 0,
    numero TEXT DEFAULT '',
    data_fechamento TIMESTAMPTZ DEFAULT NOW(),
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.fechamentos_caixa ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 10. SANGRIIAS_CAIXA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.sangrias_caixa (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    abertura_caixa_id TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    motivo TEXT DEFAULT '',
    usuario_nome TEXT DEFAULT '',
    data_sangria TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sangrias_caixa ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 11. SUPRIMENTOS_CAIXA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.suprimentos_caixa (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    abertura_caixa_id TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    motivo TEXT DEFAULT '',
    usuario_nome TEXT DEFAULT '',
    data_suprimento TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.suprimentos_caixa ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 12. NOTAS_ENTRADA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.notas_entrada (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero_nf TEXT DEFAULT '',
    serie TEXT DEFAULT '',
    fornecedor_nome TEXT DEFAULT '',
    fornecedor_cnpj TEXT DEFAULT '',
    items JSONB DEFAULT '[]'::jsonb,
    valor_total NUMERIC(15,2) DEFAULT 0,
    valor_produtos NUMERIC(15,2) DEFAULT 0,
    data_emissao TIMESTAMPTZ,
    data_entrada TIMESTAMPTZ DEFAULT NOW(),
    chave_acesso TEXT DEFAULT '',
    status TEXT DEFAULT 'pendente',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notas_entrada ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 13. ORDENS_SERVICO
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ordens_servico (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    cliente_veiculo TEXT DEFAULT '',
    descricao TEXT DEFAULT '',
    servicos JSONB DEFAULT '[]'::jsonb,
    produtos JSONB DEFAULT '[]'::jsonb,
    valor_total NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'aberto',
    tecnico_nome TEXT DEFAULT '',
    observacoes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 14. SERVICOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.servicos (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT DEFAULT '',
    descricao TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    duracao_min INTEGER DEFAULT 0,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.servicos ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 15. FUNCIONARIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.funcionarios (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT DEFAULT '',
    cpf TEXT DEFAULT '',
    cargo TEXT DEFAULT '',
    email TEXT DEFAULT '',
    telefone TEXT DEFAULT '',
    comissao_padrao NUMERIC(5,2) DEFAULT 0,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.funcionarios ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 16. CONTAS_PAGAR
-- ============================================================
CREATE TABLE IF NOT EXISTS public.contas_pagar (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    fornecedor_nome TEXT DEFAULT '',
    descricao TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    data_vencimento TIMESTAMPTZ,
    data_pagamento TIMESTAMPTZ,
    status TEXT DEFAULT 'pendente',
    categoria TEXT DEFAULT '',
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.contas_pagar ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 17. ENTREGAS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.entregas (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    pedido_id TEXT DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    endereco_entrega TEXT DEFAULT '',
    motorista_nome TEXT DEFAULT '',
    status TEXT DEFAULT 'pendente',
    taxa_entrega NUMERIC(15,2) DEFAULT 0,
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 18. MOTORISTAS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.motoristas (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    nome TEXT DEFAULT '',
    cpf TEXT DEFAULT '',
    cnh TEXT DEFAULT '',
    telefone TEXT DEFAULT '',
    veiculo TEXT DEFAULT '',
    placa TEXT DEFAULT '',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 19. TAXAS_ENTREGA
-- ============================================================
CREATE TABLE IF NOT EXISTS public.taxas_entrega (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    bairro TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    prazo_min INTEGER DEFAULT 0,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.taxas_entrega ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 20. ROMANEIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.romaneios (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    motorista_nome TEXT DEFAULT '',
    entregas JSONB DEFAULT '[]'::jsonb,
    data_saida TIMESTAMPTZ,
    data_retorno TIMESTAMPTZ,
    status TEXT DEFAULT 'aberto',
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.romaneios ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 21. MESAS_COMANDAS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.mesas_comandas (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    itens JSONB DEFAULT '[]'::jsonb,
    valor_total NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'livre',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.mesas_comandas ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 22. AGENDAMENTOS_SERVICO
-- ============================================================
CREATE TABLE IF NOT EXISTS public.agendamentos_servico (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    cliente_telefone TEXT DEFAULT '',
    servico_nome TEXT DEFAULT '',
    pet_nome TEXT DEFAULT '',
    data_agendamento TIMESTAMPTZ,
    horario TEXT DEFAULT '',
    valor NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'agendado',
    observacao TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.agendamentos_servico ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 23. TROCAS_DEVOLUCOES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.trocas_devolucoes (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    venda_id TEXT DEFAULT '',
    cliente_nome TEXT DEFAULT '',
    items JSONB DEFAULT '[]'::jsonb,
    motivo TEXT DEFAULT '',
    tipo TEXT DEFAULT 'troca',
    valor_total NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'pendente',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.trocas_devolucoes ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 24. COMISSOES_VENDEDORES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.comissoes_vendedores (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    vendedor_nome TEXT DEFAULT '',
    venda_id TEXT DEFAULT '',
    valor_venda NUMERIC(15,2) DEFAULT 0,
    percentual NUMERIC(5,2) DEFAULT 0,
    valor_comissao NUMERIC(15,2) DEFAULT 0,
    status TEXT DEFAULT 'pendente',
    periodo TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.comissoes_vendedores ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 25. LINKS_VENDEDORES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.links_vendedores (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    vendedor_nome TEXT DEFAULT '',
    url TEXT DEFAULT '',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.links_vendedores ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 26. NFCES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.nfces (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    empresa_id TEXT NOT NULL DEFAULT '',
    venda_id TEXT DEFAULT '',
    numero INTEGER DEFAULT 0,
    serie TEXT DEFAULT '',
    chave_acesso TEXT DEFAULT '',
    xml TEXT DEFAULT '',
    status TEXT DEFAULT 'pendente',
    protocolo TEXT DEFAULT '',
    motivo_cancelamento TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.nfces ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 27. USUARIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.usuarios (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    nome TEXT DEFAULT '',
    email TEXT DEFAULT '',
    senha TEXT DEFAULT '',
    empresa_id TEXT DEFAULT '',
    tipo TEXT DEFAULT 'usuario',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 28. CACHE_DADOS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.cache_dados (
    chave TEXT PRIMARY KEY,
    valor_json TEXT DEFAULT '',
    ultima_atualizacao TEXT DEFAULT ''
);

ALTER TABLE public.cache_dados ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 29. EXODO_CONFIG
-- ============================================================
CREATE TABLE IF NOT EXISTS public.exodo_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id TEXT NOT NULL DEFAULT '',
    pc_name TEXT NOT NULL DEFAULT '',
    chave TEXT NOT NULL DEFAULT '',
    valor TEXT NOT NULL DEFAULT '',
    tipo TEXT DEFAULT 'texto',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exodo_config_empresa_id ON public.exodo_config(empresa_id);
ALTER TABLE public.exodo_config ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 30. BRIDGE_CONFIG
-- ============================================================
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
ALTER TABLE public.bridge_config ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 31. SYNC_LOGS
-- ============================================================
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
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 32. SYNC_STATUS
-- ============================================================
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
ALTER TABLE public.sync_status ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- POLITICAS RLS PERMISSIVAS (para o desktop bridge)
-- ============================================================
DO $$
DECLARE
    tabela TEXT;
    tabelas TEXT[] := ARRAY[
        'empresas', 'produtos', 'clientes', 'vendas_balcao', 'pedidos',
        'produto_historico', 'estoque_historico', 'aberturas_caixa',
        'fechamentos_caixa', 'sangrias_caixa', 'suprimentos_caixa',
        'notas_entrada', 'ordens_servico', 'servicos', 'funcionarios',
        'contas_pagar', 'entregas', 'motoristas', 'taxas_entrega',
        'romaneios', 'mesas_comandas', 'agendamentos_servico',
        'trocas_devolucoes', 'comissoes_vendedores', 'links_vendedores',
        'nfces', 'usuarios', 'cache_dados', 'exodo_config',
        'bridge_config', 'sync_logs', 'sync_status'
    ];
BEGIN
    FOREACH tabela IN ARRAY tabelas
    LOOP
        EXECUTE format($f$GRANT ALL ON %I TO anon;$f$, tabela);
        EXECUTE format($f$GRANT ALL ON %I TO authenticated;$f$, tabela);
        EXECUTE format($f$GRANT ALL ON %I TO service_role;$f$, tabela);

        BEGIN
            EXECUTE format($f$DROP POLICY IF EXISTS anon_all_%I ON %I;$f$, tabela, tabela);
            EXECUTE format($f$CREATE POLICY anon_all_%I ON %I FOR ALL TO anon USING (true) WITH CHECK (true);$f$, tabela, tabela);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Erro policy anon em %: %', tabela, SQLERRM;
        END;

        BEGIN
            EXECUTE format($f$DROP POLICY IF EXISTS auth_all_%I ON %I;$f$, tabela, tabela);
            EXECUTE format($f$CREATE POLICY auth_all_%I ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true);$f$, tabela, tabela);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Erro policy auth em %: %', tabela, SQLERRM;
        END;
    END LOOP;
END $$;

-- ============================================================
-- RESUMO FINAL
-- ============================================================
SELECT
    COUNT(*)::TEXT || ' tabelas criadas/verificadas no Supabase' as resultado
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name NOT LIKE 'pg_%';

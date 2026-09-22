-- ============================================================
-- CRIAR/ATUALIZAR TODAS AS TABELAS NO SUPABASE
-- Execute este script NO SUPABASE SQL Editor
-- ============================================================
-- Este script cria tabelas que não existem E adiciona colunas
-- faltantes em tabelas que já existem. 100% seguro para rodar
-- várias vezes (tudo usa IF NOT EXISTS).
-- ============================================================

-- ============================================================
-- 0. FUNÇÃO AUXILIAR: Criar tabela + adicionar colunas faltantes
-- ============================================================
CREATE OR REPLACE FUNCTION criar_ou_atualizar_tabela(
  nome_tabela TEXT,
  colunas_def TEXT
) RETURNS VOID AS $$
DECLARE
  coluna RECORD;
  partes TEXT[];
  parte TEXT;
  nome_col TEXT;
  tipo_col TEXT;
  default_col TEXT;
  is_pk BOOLEAN;
BEGIN
  -- 1. Criar tabela se não existir
  EXECUTE format('CREATE TABLE IF NOT EXISTS public.%I (%s)', nome_tabela, colunas_def);

  -- 2. Habilitar RLS
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', nome_tabela);

  -- 3. Policies service_role (%I no nome inteiro: evita 42710 ao reexecutar)
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'service_role_all_' || nome_tabela, nome_tabela);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL USING (auth.role() = ''service_role'')', 'service_role_all_' || nome_tabela, nome_tabela);

  -- 4. Policies authenticated
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'auth_all_' || nome_tabela, nome_tabela);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL USING (auth.role() = ''authenticated'')', 'auth_all_' || nome_tabela, nome_tabela);

  -- 5. Adicionar colunas faltantes (para tabelas que já existem)
  -- Dividir a string de colunas por vírgula
  partes := string_to_array(colunas_def, ',');

  FOREACH parte IN ARRAY partes LOOP
    parte := trim(parte);
    IF parte = '' OR parte ILIKE 'PRIMARY KEY%' OR parte ILIKE 'UNIQUE%' OR parte ILIKE 'CHECK%' THEN
      CONTINUE;
    END IF;

    -- Extrair nome da coluna (primeira palavra)
    nome_col := trim(split_part(parte, ' ', 1));
    -- Remover aspas se houver
    nome_col := replace(nome_col, '"', '');

    -- Pular se for constraint ou coisa que não é coluna
    IF nome_col IN ('id', 'PRIMARY', 'CONSTRAINT', 'UNIQUE', 'CHECK', 'FOREIGN', 'INDEX') THEN
      CONTINUE;
    END IF;

    -- Montar SQL da coluna completa (tipo + default)
    tipo_col := parte;

    -- Tentar adicionar a coluna
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS %s', nome_tabela, tipo_col);
    EXCEPTION WHEN OTHERS THEN
      -- Ignorar erro (coluna pode ter tipo incompatível)
      RAISE NOTICE '⚠️ Coluna %/%: %', nome_tabela, nome_col, SQLERRM;
    END;
  END LOOP;

  -- PostgREST só expõe tabelas com GRANT para as roles da API
  EXECUTE format('GRANT ALL ON TABLE public.%I TO anon, authenticated, service_role', nome_tabela);

  RAISE NOTICE '✅ Tabela % verificada/atualizada', nome_tabela;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '⚠️ Erro na tabela %: %', nome_tabela, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 1. EMPRESAS
-- ============================================================
SELECT criar_ou_atualizar_tabela('empresas',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   razao_social TEXT DEFAULT '''',
   nome_fantasia TEXT DEFAULT '''',
   nome_exibicao TEXT DEFAULT '''',
   cnpj TEXT DEFAULT '''',
   crt TEXT DEFAULT '''',
   email TEXT DEFAULT '''',
   telefone TEXT DEFAULT '''',
   celular TEXT DEFAULT '''',
   site TEXT DEFAULT '''',
   endereco TEXT DEFAULT '''',
   numero TEXT DEFAULT '''',
   complemento TEXT DEFAULT '''',
   bairro TEXT DEFAULT '''',
   cidade TEXT DEFAULT '''',
   estado TEXT DEFAULT '''',
   cep TEXT DEFAULT '''',
   ativo BOOLEAN DEFAULT true,
   slug TEXT DEFAULT '''',
   logo_url TEXT DEFAULT '''',
   cor_primaria TEXT DEFAULT ''#1E3A5F'',
   cor_secundaria TEXT DEFAULT ''#2E86C1'',
   configuracoes JSONB DEFAULT ''{}''::jsonb,
   perfis_de_preco JSONB DEFAULT ''[]''::jsonb,
   telas_permitidas JSONB DEFAULT ''[]''::jsonb,
   observacao TEXT DEFAULT '''',
   inscricao_estadual TEXT DEFAULT '''',
   inscricao_municipal TEXT DEFAULT '''',
   codigo_ibge TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);

-- ============================================================
-- 2. PRODUTOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('produtos',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   codigo TEXT DEFAULT '''',
   codigo_barras TEXT DEFAULT '''',
   descricao TEXT DEFAULT '''',
   preco NUMERIC(15,2) DEFAULT 0,
   preco_custo NUMERIC(15,2) DEFAULT 0,
   custo NUMERIC(15,2) DEFAULT 0,
   estoque NUMERIC(15,3) DEFAULT 0,
   estoque_minimo NUMERIC(15,3) DEFAULT 0,
   unidade TEXT DEFAULT ''UN'',
   ncm TEXT DEFAULT '''',
   cest TEXT DEFAULT '''',
   cfop TEXT DEFAULT '''',
   csosn TEXT DEFAULT '''',
   cst TEXT DEFAULT '''',
   origem TEXT DEFAULT '''',
   ibpt TEXT DEFAULT '''',
   tipo TEXT DEFAULT ''produto'',
   ativo BOOLEAN DEFAULT true,
   envia_balanca BOOLEAN DEFAULT false,
   codigo_balanca TEXT DEFAULT '''',
   perfil_tributario_id TEXT DEFAULT '''',
   precos_por_perfil JSONB DEFAULT ''[]''::jsonb,
   regras_quantidade JSONB DEFAULT ''[]''::jsonb,
   departamentos_adicionais JSONB DEFAULT ''[]''::jsonb,
   foto_url TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON public.produtos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON public.produtos(codigo);

-- ============================================================
-- 3. CLIENTES
-- ============================================================
SELECT criar_ou_atualizar_tabela('clientes',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   cpf_cnpj TEXT DEFAULT '''',
   tipo_pessoa TEXT DEFAULT ''F'',
   email TEXT DEFAULT '''',
   telefone TEXT DEFAULT '''',
   celular TEXT DEFAULT '''',
   endereco TEXT DEFAULT '''',
   numero TEXT DEFAULT '''',
   complemento TEXT DEFAULT '''',
   bairro TEXT DEFAULT '''',
   cidade TEXT DEFAULT '''',
   estado TEXT DEFAULT '''',
   cep TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   ativo BOOLEAN DEFAULT true,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON public.clientes(empresa_id);

-- ============================================================
-- 4. SERVIÇOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('servicos',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   descricao TEXT DEFAULT '''',
   preco NUMERIC(15,2) DEFAULT 0,
   duracao_minutos INTEGER DEFAULT 30,
   ativo BOOLEAN DEFAULT true,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_servicos_empresa_id ON public.servicos(empresa_id);

-- ============================================================
-- 5. PEDIDOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('pedidos',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   numero_pedido INTEGER DEFAULT 0,
   cliente_id TEXT DEFAULT '''',
   cliente_nome TEXT DEFAULT '''',
   mesa_comanda_id TEXT DEFAULT '''',
   itens JSONB DEFAULT ''[]''::jsonb,
   subtotal NUMERIC(15,2) DEFAULT 0,
   desconto NUMERIC(15,2) DEFAULT 0,
   acrescimo NUMERIC(15,2) DEFAULT 0,
   total NUMERIC(15,2) DEFAULT 0,
   valor_recebido NUMERIC(15,2) DEFAULT 0,
   troco NUMERIC(15,2) DEFAULT 0,
   forma_pagamento TEXT DEFAULT '''',
   status TEXT DEFAULT ''aberto'',
   tipo TEXT DEFAULT ''balcao'',
   observacao TEXT DEFAULT '''',
   vendedor TEXT DEFAULT '''',
   operador TEXT DEFAULT '''',
   data_pedido TIMESTAMPTZ DEFAULT NOW(),
   data_recebimento TIMESTAMPTZ,
   data_cancelamento TIMESTAMPTZ,
   motivo_cancelamento TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_pedidos_empresa ON public.pedidos(empresa_id);

-- ============================================================
-- 6. VENDAS_BALCAO
-- ============================================================
SELECT criar_ou_atualizar_tabela('vendas_balcao',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   numero_venda INTEGER DEFAULT 0,
   cliente_id TEXT DEFAULT '''',
   cliente_nome TEXT DEFAULT '''',
   itens JSONB DEFAULT ''[]''::jsonb,
   subtotal NUMERIC(15,2) DEFAULT 0,
   desconto NUMERIC(15,2) DEFAULT 0,
   acrescimo NUMERIC(15,2) DEFAULT 0,
   total NUMERIC(15,2) DEFAULT 0,
   valor_recebido NUMERIC(15,2) DEFAULT 0,
   troco NUMERIC(15,2) DEFAULT 0,
   forma_pagamento TEXT DEFAULT '''',
   status TEXT DEFAULT ''finalizada'',
   tipo TEXT DEFAULT ''balcao'',
   observacao TEXT DEFAULT '''',
   vendedor TEXT DEFAULT '''',
   operador TEXT DEFAULT '''',
   data_venda TIMESTAMPTZ DEFAULT NOW(),
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa ON public.vendas_balcao(empresa_id);

-- ============================================================
-- 7. MESAS_COMANDAS
-- ============================================================
SELECT criar_ou_atualizar_tabela('mesas_comandas',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   numero TEXT DEFAULT '''',
   nome TEXT DEFAULT '''',
   capacidade INTEGER DEFAULT 4,
   status TEXT DEFAULT ''livre'',
   tipo TEXT DEFAULT ''mesa'',
   pedido_id TEXT DEFAULT '''',
   comanda_numero INTEGER DEFAULT 0,
   garcom TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_mesas_empresa ON public.mesas_comandas(empresa_id);

-- ============================================================
-- 8. CAIXA
-- ============================================================
SELECT criar_ou_atualizar_tabela('caixa',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   data_abertura TIMESTAMPTZ DEFAULT NOW(),
   data_fechamento TIMESTAMPTZ,
   saldo_inicial NUMERIC(15,2) DEFAULT 0,
   saldo_final NUMERIC(15,2) DEFAULT 0,
   status TEXT DEFAULT ''aberto'',
   operador TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_caixa_empresa ON public.caixa(empresa_id);

-- ============================================================
-- 9. MOVIMENTOS_CAIXA
-- ============================================================
SELECT criar_ou_atualizar_tabela('movimentos_caixa',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   caixa_id TEXT DEFAULT '''',
   tipo TEXT DEFAULT '''',
   descricao TEXT DEFAULT '''',
   valor NUMERIC(15,2) DEFAULT 0,
   forma_pagamento TEXT DEFAULT '''',
   operador TEXT DEFAULT '''',
   data_movimento TIMESTAMPTZ DEFAULT NOW(),
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_movimentos_caixa_empresa ON public.movimentos_caixa(empresa_id);

-- ============================================================
-- 10. FORNECEDORES
-- ============================================================
SELECT criar_ou_atualizar_tabela('fornecedores',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   cpf_cnpj TEXT DEFAULT '''',
   telefone TEXT DEFAULT '''',
   email TEXT DEFAULT '''',
   endereco TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   ativo BOOLEAN DEFAULT true,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_fornecedores_empresa ON public.fornecedores(empresa_id);

-- ============================================================
-- 11. COMPRAS
-- ============================================================
SELECT criar_ou_atualizar_tabela('compras',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   fornecedor_id TEXT DEFAULT '''',
   fornecedor_nome TEXT DEFAULT '''',
   numero_nota TEXT DEFAULT '''',
   itens JSONB DEFAULT ''[]''::jsonb,
   total NUMERIC(15,2) DEFAULT 0,
   status TEXT DEFAULT ''aberta'',
   data_compra TIMESTAMPTZ DEFAULT NOW(),
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_compras_empresa ON public.compras(empresa_id);

-- ============================================================
-- 12. ENTREGAS
-- ============================================================
SELECT criar_ou_atualizar_tabela('entregas',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   venda_id TEXT DEFAULT '''',
   cliente_id TEXT DEFAULT '''',
   cliente_nome TEXT DEFAULT '''',
   endereco TEXT DEFAULT '''',
   telefone TEXT DEFAULT '''',
   status TEXT DEFAULT ''pendente'',
   motorista_id TEXT DEFAULT '''',
   motorista_nome TEXT DEFAULT '''',
   valor_total NUMERIC(15,2) DEFAULT 0,
   taxa_entrega NUMERIC(15,2) DEFAULT 0,
   observacao TEXT DEFAULT '''',
   data_pedido TIMESTAMPTZ DEFAULT NOW(),
   data_entrega TIMESTAMPTZ,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_entregas_empresa ON public.entregas(empresa_id);

-- ============================================================
-- 13. USUARIOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('usuarios',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   email TEXT DEFAULT '''',
   senha TEXT DEFAULT '''',
   perfil TEXT DEFAULT ''operador'',
   ativo BOOLEAN DEFAULT true,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_usuarios_empresa ON public.usuarios(empresa_id);

-- ============================================================
-- 14. FINANCEIRO
-- ============================================================
SELECT criar_ou_atualizar_tabela('financeiro',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   tipo TEXT DEFAULT '''',
   descricao TEXT DEFAULT '''',
   valor NUMERIC(15,2) DEFAULT 0,
   data_vencimento TIMESTAMPTZ,
   data_pagamento TIMESTAMPTZ,
   status TEXT DEFAULT ''pendente'',
   categoria TEXT DEFAULT '''',
   observacao TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_financeiro_empresa ON public.financeiro(empresa_id);

-- ============================================================
-- 15. PRECOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('precos',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   produto_id TEXT DEFAULT '''',
   perfil TEXT DEFAULT '''',
   preco NUMERIC(15,2) DEFAULT 0,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_precos_empresa ON public.precos(empresa_id);

-- ============================================================
-- 16. ESTOQUE_HISTORICO
-- ============================================================
SELECT criar_ou_atualizar_tabela('estoque_historico',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   produto_id TEXT DEFAULT '''',
   tipo TEXT DEFAULT '''',
   quantidade NUMERIC(15,3) DEFAULT 0,
   estoque_anterior NUMERIC(15,3) DEFAULT 0,
   estoque_novo NUMERIC(15,3) DEFAULT 0,
   observacao TEXT DEFAULT '''',
   data_movimento TIMESTAMPTZ DEFAULT NOW(),
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa ON public.estoque_historico(empresa_id);

-- ============================================================
-- 17. LOTES_PRODUTO
-- ============================================================
SELECT criar_ou_atualizar_tabela('lotes_produto',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   produto_id TEXT DEFAULT '''',
   numero_lote TEXT DEFAULT '''',
   quantidade NUMERIC(15,3) DEFAULT 0,
   data_fabricacao TIMESTAMPTZ,
   data_validade TIMESTAMPTZ,
   fornecedor_id TEXT DEFAULT '''',
   fornecedor_nome TEXT DEFAULT '''',
   custo_unitario NUMERIC(15,2) DEFAULT 0,
   status TEXT DEFAULT ''ativo'',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_lotes_empresa ON public.lotes_produto(empresa_id);

-- ============================================================
-- 18. PRODUTO_HISTORICO
-- ============================================================
SELECT criar_ou_atualizar_tabela('produto_historico',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   produto_id TEXT DEFAULT '''',
   tipo TEXT DEFAULT '''',
   dados_anteriores JSONB DEFAULT ''{}''::jsonb,
   dados_novos JSONB DEFAULT ''{}''::jsonb,
   usuario TEXT DEFAULT '''',
   data_alteracao TIMESTAMPTZ DEFAULT NOW(),
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_produto_historico_empresa ON public.produto_historico(empresa_id);

-- ============================================================
-- 19. PERFIS_TRIBUTARIOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('perfis_tributarios',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   cfop TEXT DEFAULT '''',
   icms_cst TEXT DEFAULT '''',
   csosn TEXT DEFAULT '''',
   aliquota_icms NUMERIC(5,2) DEFAULT 0,
   pis_cst TEXT DEFAULT '''',
   cofins_cst TEXT DEFAULT '''',
   ipi_cst TEXT DEFAULT '''',
   mva NUMERIC(5,2) DEFAULT 0,
   fcp NUMERIC(5,2) DEFAULT 0,
   ncm TEXT DEFAULT '''',
   is_default BOOLEAN DEFAULT false,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_perfis_tributarios_empresa ON public.perfis_tributarios(empresa_id);

-- ============================================================
-- 20. DEPARTAMENTOS
-- ============================================================
SELECT criar_ou_atualizar_tabela('departamentos',
  'id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
   empresa_id TEXT NOT NULL DEFAULT '''',
   nome TEXT DEFAULT '''',
   cor TEXT DEFAULT '''',
   icone TEXT DEFAULT '''',
   impressora_producao TEXT DEFAULT '''',
   impressora_producao_extra TEXT DEFAULT '''',
   ordem INTEGER DEFAULT 0,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_departamentos_empresa ON public.departamentos(empresa_id);

-- ============================================================
-- 21. ORÇAMENTOS (série ORC-) — o sync local baixa esta tabela
-- ============================================================
SELECT criar_ou_atualizar_tabela('orcamentos',
  'id TEXT PRIMARY KEY,
   empresa_id TEXT NOT NULL DEFAULT '''',
   numero TEXT DEFAULT '''',
   cliente_id TEXT DEFAULT '''',
   cliente_nome TEXT DEFAULT '''',
   cliente_telefone TEXT DEFAULT '''',
   cliente_endereco TEXT DEFAULT '''',
   cliente_cpf_cnpj TEXT DEFAULT '''',
   operador TEXT DEFAULT '''',
   data_orcamento TIMESTAMPTZ DEFAULT NOW(),
   validade_orcamento TIMESTAMPTZ,
   status TEXT DEFAULT ''Orçamento'',
   total NUMERIC(15,2) DEFAULT 0,
   desconto_total NUMERIC(15,2) DEFAULT 0,
   acrescimo_total NUMERIC(15,2) DEFAULT 0,
   observacoes TEXT DEFAULT '''',
   itens JSONB DEFAULT ''[]''::jsonb,
   servicos JSONB DEFAULT ''[]''::jsonb,
   delivery_info JSONB,
   pedido_gerado_id TEXT DEFAULT '''',
   pedido_gerado_numero TEXT DEFAULT '''',
   data_aprovacao TIMESTAMPTZ,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_orcamentos_empresa ON public.orcamentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_orcamentos_status ON public.orcamentos(status);
CREATE INDEX IF NOT EXISTS idx_orcamentos_updated ON public.orcamentos(updated_at DESC);

-- ============================================================
-- 22. SERVIÇOS REALIZADOS (série SRV-) — entidade própria, não é pedido
-- ============================================================
SELECT criar_ou_atualizar_tabela('servicos_realizados',
  'id TEXT PRIMARY KEY,
   empresa_id TEXT NOT NULL DEFAULT '''',
   numero TEXT DEFAULT '''',
   cliente_id TEXT DEFAULT '''',
   cliente_nome TEXT DEFAULT '''',
   cliente_telefone TEXT DEFAULT '''',
   cliente_endereco TEXT DEFAULT '''',
   pet_id TEXT DEFAULT '''',
   pet_nome TEXT DEFAULT '''',
   operador TEXT DEFAULT '''',
   data_servico TIMESTAMPTZ DEFAULT NOW(),
   data_conclusao TIMESTAMPTZ,
   data_orcamento TIMESTAMPTZ,
   validade_orcamento TIMESTAMPTZ,
   status TEXT DEFAULT ''Em Aberto'',
   total NUMERIC(15,2) DEFAULT 0,
   desconto_total NUMERIC(15,2) DEFAULT 0,
   acrescimo_total NUMERIC(15,2) DEFAULT 0,
   observacoes TEXT DEFAULT '''',
   servicos JSONB DEFAULT ''[]''::jsonb,
   pagamentos JSONB DEFAULT ''[]''::jsonb,
   materiais_consumidos JSONB DEFAULT ''[]''::jsonb,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);
CREATE INDEX IF NOT EXISTS idx_servicos_realizados_empresa ON public.servicos_realizados(empresa_id);
CREATE INDEX IF NOT EXISTS idx_servicos_realizados_status ON public.servicos_realizados(status);
CREATE INDEX IF NOT EXISTS idx_servicos_realizados_updated ON public.servicos_realizados(updated_at DESC);

-- ============================================================
-- 23. exodo_config — o sincronizador antigo ainda consulta esta tabela
-- ============================================================
SELECT criar_ou_atualizar_tabela('exodo_config',
  'chave TEXT PRIMARY KEY,
   valor TEXT DEFAULT '''',
   empresa_id TEXT DEFAULT '''',
   created_at TIMESTAMPTZ DEFAULT NOW(),
   updated_at TIMESTAMPTZ DEFAULT NOW()'
);

-- Recarrega o schema cache do PostgREST (sem isso o REST continua 404/PGRST205)
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- PRONTO! Todas as tabelas foram criadas ou atualizadas.
-- ============================================================

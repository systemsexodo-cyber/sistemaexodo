-- ============================================================
-- CRIAR TABELAS QUE EXISTEM LOCAIS MAS NÃO NO SUPABASE
-- Execute este script no SQL Editor do Supabase Dashboard
-- ============================================================

-- 1. perfis_tributarios (impostos/perfis fiscais)
CREATE TABLE IF NOT EXISTS public.perfis_tributarios (
  id TEXT PRIMARY KEY,
  empresa_id TEXT NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  descricao TEXT,
  icms DECIMAL(10,2) DEFAULT 0,
  pis DECIMAL(10,2) DEFAULT 0,
  cofins DECIMAL(10,2) DEFAULT 0,
  ipi DECIMAL(10,2) DEFAULT 0,
  iss DECIMAL(10,2) DEFAULT 0,
  irpj DECIMAL(10,2) DEFAULT 0,
  csll DECIMAL(10,2) DEFAULT 0,
  substituicao_tributaria BOOLEAN DEFAULT false,
  aliquota_st DECIMAL(10,2) DEFAULT 0,
  observacoes TEXT,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. departamentos (cozinha, bar, etc.)
CREATE TABLE IF NOT EXISTS public.departamentos (
  id TEXT PRIMARY KEY,
  empresa_id TEXT NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  descricao TEXT,
  cor TEXT,
  icone TEXT,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Dar permissões
ALTER TABLE public.perfis_tributarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departamentos ENABLE ROW LEVEL SECURITY;

-- Políticas de acesso (DROP IF EXISTS: o script pode ser rodado de novo)
DROP POLICY IF EXISTS "service_role_all_perfis_tributarios" ON public.perfis_tributarios;
CREATE POLICY "service_role_all_perfis_tributarios" ON public.perfis_tributarios FOR ALL
  USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_all_departamentos" ON public.departamentos;
CREATE POLICY "service_role_all_departamentos" ON public.departamentos FOR ALL
  USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "authenticated_select_perfis_tributarios" ON public.perfis_tributarios;
CREATE POLICY "authenticated_select_perfis_tributarios" ON public.perfis_tributarios FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_insert_perfis_tributarios" ON public.perfis_tributarios;
CREATE POLICY "authenticated_insert_perfis_tributarios" ON public.perfis_tributarios FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_update_perfis_tributarios" ON public.perfis_tributarios;
CREATE POLICY "authenticated_update_perfis_tributarios" ON public.perfis_tributarios FOR UPDATE
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_delete_perfis_tributarios" ON public.perfis_tributarios;
CREATE POLICY "authenticated_delete_perfis_tributarios" ON public.perfis_tributarios FOR DELETE
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_select_departamentos" ON public.departamentos;
CREATE POLICY "authenticated_select_departamentos" ON public.departamentos FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_insert_departamentos" ON public.departamentos;
CREATE POLICY "authenticated_insert_departamentos" ON public.departamentos FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_update_departamentos" ON public.departamentos;
CREATE POLICY "authenticated_update_departamentos" ON public.departamentos FOR UPDATE
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "authenticated_delete_departamentos" ON public.departamentos;
CREATE POLICY "authenticated_delete_departamentos" ON public.departamentos FOR DELETE
  USING (auth.role() = 'authenticated');

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_perfis_tributarios_empresa ON public.perfis_tributarios(empresa_id);
CREATE INDEX IF NOT EXISTS idx_departamentos_empresa ON public.departamentos(empresa_id);

-- Mensagem de conclusão
DO $$ BEGIN
  RAISE NOTICE '✅ Tabelas perfis_tributarios e departamentos criadas com sucesso!';
END $$;

-- ============================================================================
-- SERVIÇOS REALIZADOS (entidade própria, separada de `pedidos`)
--
-- Série própria SRV-0001 e status 'Orçamento' (proposta), 'Em Aberto',
-- 'Recebido' e 'Cancelado'. Rode este trecho no SQL Editor do Supabase ANTES
-- de usar a tela de Serviços em mais de uma máquina.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.servicos_realizados (
  id TEXT PRIMARY KEY,
  empresa_id TEXT NOT NULL DEFAULT '',
  numero TEXT DEFAULT '',
  cliente_id TEXT DEFAULT '',
  cliente_nome TEXT DEFAULT '',
  cliente_telefone TEXT DEFAULT '',
  cliente_endereco TEXT DEFAULT '',
  pet_id TEXT DEFAULT '',
  pet_nome TEXT DEFAULT '',
  operador TEXT DEFAULT '',
  data_servico TIMESTAMPTZ DEFAULT NOW(),
  data_conclusao TIMESTAMPTZ,
  data_orcamento TIMESTAMPTZ,
  validade_orcamento TIMESTAMPTZ,
  status TEXT DEFAULT 'Em Aberto',
  total NUMERIC(15,2) DEFAULT 0,
  desconto_total NUMERIC(15,2) DEFAULT 0,
  acrescimo_total NUMERIC(15,2) DEFAULT 0,
  observacoes TEXT DEFAULT '',
  servicos JSONB DEFAULT '[]'::jsonb,
  pagamentos JSONB DEFAULT '[]'::jsonb,
  materiais_consumidos JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_servicos_realizados_empresa ON public.servicos_realizados(empresa_id);
CREATE INDEX IF NOT EXISTS idx_servicos_realizados_status ON public.servicos_realizados(status);
CREATE INDEX IF NOT EXISTS idx_servicos_realizados_updated ON public.servicos_realizados(updated_at DESC);

ALTER TABLE public.servicos_realizados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_role_servicos_realizados ON public.servicos_realizados;
DROP POLICY IF EXISTS "authenticated_all_servicos_realizados" ON public.servicos_realizados;
CREATE POLICY service_role_servicos_realizados ON public.servicos_realizados FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "authenticated_all_servicos_realizados" ON public.servicos_realizados FOR ALL
  USING (auth.role() = 'authenticated');
GRANT ALL ON TABLE public.servicos_realizados TO anon, authenticated, service_role;

DO $$ BEGIN
  RAISE NOTICE '✅ Tabela servicos_realizados criada com sucesso!';
END $$;

-- ============================================================================
-- ORÇAMENTOS (série ORC-) — propostas feitas na tela de Pedidos central
--
-- Não são pedidos: ficam fora do PDV, dos recebíveis e dos relatórios de venda.
-- Aprovado, o orçamento gera um Pedido (PED-) e guarda o vínculo em
-- pedido_gerado_id / pedido_gerado_numero. Rode no SQL Editor do Supabase.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.orcamentos (
  id TEXT PRIMARY KEY,
  empresa_id TEXT NOT NULL DEFAULT '',
  numero TEXT DEFAULT '',
  cliente_id TEXT DEFAULT '',
  cliente_nome TEXT DEFAULT '',
  cliente_telefone TEXT DEFAULT '',
  cliente_endereco TEXT DEFAULT '',
  cliente_cpf_cnpj TEXT DEFAULT '',
  operador TEXT DEFAULT '',
  data_orcamento TIMESTAMPTZ DEFAULT NOW(),
  validade_orcamento TIMESTAMPTZ,
  status TEXT DEFAULT 'Orçamento',
  total NUMERIC(15,2) DEFAULT 0,
  desconto_total NUMERIC(15,2) DEFAULT 0,
  acrescimo_total NUMERIC(15,2) DEFAULT 0,
  observacoes TEXT DEFAULT '',
  itens JSONB DEFAULT '[]'::jsonb,
  servicos JSONB DEFAULT '[]'::jsonb,
  delivery_info JSONB,
  pedido_gerado_id TEXT DEFAULT '',
  pedido_gerado_numero TEXT DEFAULT '',
  data_aprovacao TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orcamentos_empresa ON public.orcamentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_orcamentos_status ON public.orcamentos(status);
CREATE INDEX IF NOT EXISTS idx_orcamentos_updated ON public.orcamentos(updated_at DESC);

ALTER TABLE public.orcamentos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_role_orcamentos ON public.orcamentos;
DROP POLICY IF EXISTS "authenticated_all_orcamentos" ON public.orcamentos;
CREATE POLICY service_role_orcamentos ON public.orcamentos FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "authenticated_all_orcamentos" ON public.orcamentos FOR ALL
  USING (auth.role() = 'authenticated');
GRANT ALL ON TABLE public.orcamentos TO anon, authenticated, service_role;

DO $$ BEGIN
  RAISE NOTICE '✅ Tabela orcamentos criada com sucesso!';
END $$;

-- ============================================================================
-- exodo_config — tabela que o sincronizador usa e que precisa existir no
-- Supabase para que o loop de download não trave.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.exodo_config (
  chave TEXT PRIMARY KEY,
  valor TEXT DEFAULT '',
  empresa_id TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.exodo_config ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.exodo_config ADD COLUMN IF NOT EXISTS empresa_id TEXT DEFAULT '';
ALTER TABLE public.exodo_config ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE public.exodo_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS service_role_exodo_config ON public.exodo_config;
DROP POLICY IF EXISTS "authenticated_all_exodo_config" ON public.exodo_config;
CREATE POLICY service_role_exodo_config ON public.exodo_config FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "authenticated_all_exodo_config" ON public.exodo_config FOR ALL
  USING (auth.role() = 'authenticated');
GRANT ALL ON TABLE public.exodo_config TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ Tabela exodo_config criada com sucesso!';
END $$;

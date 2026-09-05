-- ==========================================================================
-- ADICIONAR COLUNAS DE CONFIGURAÇÃO NA TABELA EMPRESAS E CLIENTES
-- Execute este script no Supabase SQL Editor
-- ==========================================================================

-- ===== TABELA EMPRESAS =====

-- 1. Garantir que a tabela empresas existe
CREATE TABLE IF NOT EXISTS empresas (
  id TEXT PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Adicionar colunas básicas se não existirem
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS empresa_id TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS razao_social TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS nome_fantasia TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS cnpj TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT TRUE;

-- 3. COLUNA PRINCIPAL: configuracoes (armazena perfis_preco, bridge, NFC-e, etc.)
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS configuracoes JSONB;

-- 4. Coluna auxiliar de backup para perfis de preço
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS perfis_de_preco JSONB;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS "perfisDePreco" JSONB;

-- 5. Habilitar RLS
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;

-- 6. Criar políticas de acesso
DROP POLICY IF EXISTS empresas_permitir_autenticado ON empresas;
CREATE POLICY empresas_permitir_autenticado ON empresas
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS empresas_admin ON empresas;
CREATE POLICY empresas_admin ON empresas
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ===== TABELA CLIENTES =====

-- Adicionar coluna perfil_preco para vincular cliente à tabela de preço
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS perfil_preco TEXT;

-- Também aceitar formato camelCase caso o app envie assim
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS "perfilPreco" TEXT;


-- ===== TABELA PRODUTOS =====

-- Preços por perfil (ex: {"atacado": 15.90, "revenda": 12.50})
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS precos_por_perfil JSONB;

-- Regras de quantidade (atacarejo)
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS regras_quantidade JSONB;


-- ===== VERIFICAR RESULTADO =====
SELECT 
  table_name,
  column_name, 
  data_type 
FROM information_schema.columns 
WHERE table_name IN ('empresas', 'clientes', 'produtos')
  AND column_name IN ('configuracoes', 'perfis_de_preco', 'perfil_preco', 'perfilPreco', 'precos_por_perfil', 'regras_quantidade')
  AND table_schema = 'public'
ORDER BY table_name, column_name;

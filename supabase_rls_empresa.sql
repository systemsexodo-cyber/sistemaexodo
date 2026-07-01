-- Script SQL para configurar Row Level Security (RLS) no Supabase
-- para isolamento de dados por empresa

-- ============================================
-- 1. Adicionar coluna empresa_id nas tabelas
-- ============================================

-- Produtos
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_produtos_empresa ON produtos(empresa_id);

-- Clientes
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_clientes_empresa ON clientes(empresa_id);

-- Pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_pedidos_empresa ON pedidos(empresa_id);

-- Vendas Balcão
ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa ON vendas_balcao(empresa_id);

-- Mesas/Comandas
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_mesas_comandas_empresa ON mesas_comandas(empresa_id);

-- Agendamentos
ALTER TABLE agendamentos_servico ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_agendamentos_empresa ON agendamentos_servico(empresa_id);

-- Serviços
ALTER TABLE servicos ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_servicos_empresa ON servicos(empresa_id);

-- Notas Entrada
ALTER TABLE notas_entrada ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_notas_entrada_empresa ON notas_entrada(empresa_id);

-- Ordens de Serviço
ALTER TABLE ordens_servico ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_ordens_servico_empresa ON ordens_servico(empresa_id);

-- Trocas/Devoluções
ALTER TABLE trocas_devolucoes ADD COLUMN IF NOT EXISTS empresa_id TEXT;
CREATE INDEX IF NOT EXISTS idx_trocas_devolucoes_empresa ON trocas_devolucoes(empresa_id);

-- ============================================
-- 2. Habilitar RLS nas tabelas
-- ============================================

ALTER TABLE produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendas_balcao ENABLE ROW LEVEL SECURITY;
ALTER TABLE mesas_comandas ENABLE ROW LEVEL SECURITY;
ALTER TABLE agendamentos_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE servicos ENABLE ROW LEVEL SECURITY;
ALTER TABLE notas_entrada ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordens_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE trocas_devolucoes ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 3. Criar políticas RLS para isolamento por empresa
-- ============================================

-- Produtos
DROP POLICY IF EXISTS "produtos_isolar_empresa" ON produtos;
CREATE POLICY "produtos_isolar_empresa" ON produtos
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Clientes
DROP POLICY IF EXISTS "clientes_isolar_empresa" ON clientes;
CREATE POLICY "clientes_isolar_empresa" ON clientes
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Pedidos
DROP POLICY IF EXISTS "pedidos_isolar_empresa" ON pedidos;
CREATE POLICY "pedidos_isolar_empresa" ON pedidos
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Vendas Balcão
DROP POLICY IF EXISTS "vendas_balcao_isolar_empresa" ON vendas_balcao;
CREATE POLICY "vendas_balcao_isolar_empresa" ON vendas_balcao
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Mesas/Comandas
DROP POLICY IF EXISTS "mesas_comandas_isolar_empresa" ON mesas_comandas;
CREATE POLICY "mesas_comandas_isolar_empresa" ON mesas_comandas
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Agendamentos
DROP POLICY IF EXISTS "agendamentos_isolar_empresa" ON agendamentos_servico;
CREATE POLICY "agendamentos_isolar_empresa" ON agendamentos_servico
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Serviços
DROP POLICY IF EXISTS "servicos_isolar_empresa" ON servicos;
CREATE POLICY "servicos_isolar_empresa" ON servicos
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Notas Entrada
DROP POLICY IF EXISTS "notas_entrada_isolar_empresa" ON notas_entrada;
CREATE POLICY "notas_entrada_isolar_empresa" ON notas_entrada
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Ordens de Serviço
DROP POLICY IF EXISTS "ordens_servico_isolar_empresa" ON ordens_servico;
CREATE POLICY "ordens_servico_isolar_empresa" ON ordens_servico
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- Trocas/Devoluções
DROP POLICY IF EXISTS "trocas_devolucoes_isolar_empresa" ON trocas_devolucoes;
CREATE POLICY "trocas_devolucoes_isolar_empresa" ON trocas_devolucoes
  FOR ALL
  USING (empresa_id = auth.jwt()->>'empresa_id'::TEXT)
  WITH CHECK (empresa_id = auth.jwt()->>'empresa_id'::TEXT);

-- ============================================
-- 4. Política para bypass RLS para service_role (admin)
-- ============================================

-- Permitir que service_role (admin) tenha acesso total
DROP POLICY IF EXISTS "service_role_full_access" ON produtos;
CREATE POLICY "service_role_full_access" ON produtos
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON clientes;
CREATE POLICY "service_role_full_access" ON clientes
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON pedidos;
CREATE POLICY "service_role_full_access" ON pedidos
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON vendas_balcao;
CREATE POLICY "service_role_full_access" ON vendas_balcao
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON mesas_comandas;
CREATE POLICY "service_role_full_access" ON mesas_comandas
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON agendamentos_servico;
CREATE POLICY "service_role_full_access" ON agendamentos_servico
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON servicos;
CREATE POLICY "service_role_full_access" ON servicos
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON notas_entrada;
CREATE POLICY "service_role_full_access" ON notas_entrada
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON ordens_servico;
CREATE POLICY "service_role_full_access" ON ordens_servico
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_full_access" ON trocas_devolucoes;
CREATE POLICY "service_role_full_access" ON trocas_devolucoes
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================
-- 5. Atualizar dados existentes (opcional)
-- ============================================

-- Se você já tem dados e quer atribuir a uma empresa padrão
-- Descomente e ajuste o ID da empresa conforme necessário:

-- UPDATE produtos SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE clientes SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE pedidos SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE vendas_balcao SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE mesas_comandas SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE agendamentos_servico SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE servicos SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE notas_entrada SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE ordens_servico SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;
-- UPDATE trocas_devolucoes SET empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13' WHERE empresa_id IS NULL;

-- ============================================
-- 6. Tornar empresa_id NOT NULL após migração (opcional)
-- ============================================

-- Após migrar os dados existentes, descomente para tornar obrigatório:
-- ALTER TABLE produtos ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE clientes ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE pedidos ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE vendas_balcao ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE mesas_comandas ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE agendamentos_servico ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE servicos ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE notas_entrada ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE ordens_servico ALTER COLUMN empresa_id SET NOT NULL;
-- ALTER TABLE trocas_devolucoes ALTER COLUMN empresa_id SET NOT NULL;

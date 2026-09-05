-- Script SQL para corrigir dados existentes e separar por empresa
-- Execute este script no Supabase SQL Editor

-- ============================================
-- 1. Primeiro, verifique quais empresas existem
-- ============================================
SELECT id, razao_social, nome_fantasia FROM empresas;

-- ============================================
-- 2. Substitua os IDs abaixo pelos IDs reais das suas empresas
-- ============================================

-- Script pronto para executar
-- Os dados existentes serão atribuídos à primeira empresa (66a880c8-51c7-496f-826b-d2ff9ab8ed2d)
-- A segunda empresa (22ae2c16-a730-43f3-a4f9-19f105eb0d13) começará com dados vazios

DO $$
DECLARE
  empresa_principal_id TEXT := '66a880c8-51c7-496f-826b-d2ff9ab8ed2d'; -- Empresa que ficará com os dados atuais
BEGIN
  -- Atualizar produtos
  UPDATE produtos 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar clientes
  UPDATE clientes 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar pedidos
  UPDATE pedidos 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar vendas_balcao
  UPDATE vendas_balcao 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar mesas_comandas
  UPDATE mesas_comandas 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar agendamentos_servico
  UPDATE agendamentos_servico 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar servicos
  UPDATE servicos 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar notas_entrada
  UPDATE notas_entrada 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar ordens_servico
  UPDATE ordens_servico 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  -- Atualizar trocas_devolucoes
  UPDATE trocas_devolucoes 
  SET empresa_id = empresa_principal_id 
  WHERE empresa_id IS NULL;
  
  RAISE NOTICE 'Dados atualizados para a empresa %', empresa_principal_id;
END $$;

-- ============================================
-- 3. Se você tem dados de DUAS empresas misturados,
--    precisa identificar quais dados pertencem a cada empresa
-- ============================================

-- Opção A: Se você tem uma forma de identificar (por exemplo, por data de criação)
-- UPDATE produtos SET empresa_id = 'ID_EMPRESA_1' WHERE created_at < 'DATA_LIMITE';
-- UPDATE produtos SET empresa_id = 'ID_EMPRESA_2' WHERE created_at >= 'DATA_LIMITE';

-- Opção B: Se não tem como diferenciar, você precisa:
-- 1. Decidir qual empresa fica com os dados atuais
-- 2. A outra empresa começará com dados vazios
-- 3. Depois, cada empresa terá seus próprios dados isolados

-- ============================================
-- 4. Verificar se os dados foram atualizados
-- ============================================
SELECT 
  (SELECT COUNT(*) FROM produtos WHERE empresa_id IS NULL) as produtos_sem_empresa,
  (SELECT COUNT(*) FROM clientes WHERE empresa_id IS NULL) as clientes_sem_empresa,
  (SELECT COUNT(*) FROM pedidos WHERE empresa_id IS NULL) as pedidos_sem_empresa;

-- ============================================
-- 5. Depois de atualizar, tornar empresa_id obrigatório
-- ============================================
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

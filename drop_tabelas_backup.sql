-- ============================================================
-- Remover tabelas de backup que causam 404 no sync com Supabase
-- Essas tabelas foram criadas por limpar_caixas_local.sql e
-- não existem no Supabase, causando erros repetidos no sync.
-- ============================================================

DROP TABLE IF EXISTS aberturas_caixa_bkp_20260815;
DROP TABLE IF EXISTS fechamentos_caixa_bkp_20260815;
DROP TABLE IF EXISTS sangrias_caixa_bkp_20260815;
DROP TABLE IF EXISTS suprimentos_caixa_bkp_20260815;
DROP TABLE IF EXISTS vendas_balcao_bkp_20260815;

-- Verificar se foram removidas
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND POSITION('_bkp_' IN table_name) > 0;

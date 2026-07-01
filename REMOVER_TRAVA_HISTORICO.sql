-- ==========================================================================
-- SCRIPT PARA DESTRAVAR A FILA DE SINCRONIZAÇÃO DO HISTÓRICO
-- ==========================================================================
-- Execute este comando no SQL Editor do Supabase para remover a restrição 
-- que está causando o erro 23514 ("violates check constraint").
-- ==========================================================================

-- 1. Tentar remover a restrição (caso o Supabase tenha criado automaticamente)
ALTER TABLE produto_historico DROP CONSTRAINT IF EXISTS produto_historico_tipo_operacao_check;

-- 2. Recriar a restrição permitindo o tipo 'VENDA' (para os itens que ficaram presos na fila)
ALTER TABLE produto_historico ADD CONSTRAINT produto_historico_tipo_operacao_check CHECK (tipo_operacao IN ('CREATE', 'UPDATE', 'DELETE', 'VENDA'));

-- Observação: Se o erro persistir dizendo que a restrição tem outro nome, 
-- você pode remover a verificação de tipo de operação inteiramente usando:
-- ALTER TABLE produto_historico DROP CONSTRAINT "NOME_DA_RESTRICAO_AQUI";

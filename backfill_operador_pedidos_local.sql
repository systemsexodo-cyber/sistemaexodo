-- ==========================================================================
-- BACKFILL: OPERADOR (RESPONSÁVEL) NOS PEDIDOS DE DELIVERY
-- --------------------------------------------------------------------------
-- Problema: o histórico de vendas não mostra o responsável nas vendas de
-- delivery porque o campo `operador` do pedido está vazio (o operador só
-- estava salvo na venda balcão correspondente).
--
-- Ação: copiar o `operador` da `vendas_balcao` para o `pedidos` com o
-- mesmo ID (as vendas de delivery criam os dois registros com o mesmo id).
-- Não sobrescreve pedidos que já têm operador.
--
-- EXECUTAR SOMENTE COM O APP FECHADO.
-- ==========================================================================

BEGIN;

UPDATE pedidos p
SET operador = v.operador,
    updated_at = NOW()
FROM vendas_balcao v
WHERE v.id = p.id
  AND (p.operador IS NULL OR p.operador = '')
  AND v.operador IS NOT NULL
  AND v.operador <> '';

-- Validação: pedidos com operador preenchido (deve aumentar)
SELECT COUNT(*) AS pedidos_com_operador
FROM pedidos
WHERE operador IS NOT NULL AND operador <> '';

COMMIT;

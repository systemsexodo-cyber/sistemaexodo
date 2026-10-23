-- ============================================================
-- 014 — TAXA DA ENTREGA GRAVADA NA ENTREGA (comissão do motoboy)
-- ============================================================
-- A comissão por entrega é calculada sobre a TAXA da entrega
-- (`entrega.taxaEntrega`, lida na tela de Comissões e no painel de motoboys).
-- Só que essa taxa nunca chegava ao banco: o app enviava a coluna
-- `taxaEntrega`, que NÃO existe na tabela `entregas` (as colunas numéricas
-- daqui são `valorFrete` e `valor_frete`) — e a gravação descarta colunas
-- inexistentes. Toda entrega ficava com taxa NULL, `Entrega.fromMap` devolvia
-- null e a comissão (% sobre a taxa, ou o valor da taxa) saía R$ 0,00.
--
-- O modelo passou a gravar também `valorFrete`/`valor_frete` (banco local) e
-- `taxa_entrega` (nuvem). Esta migração garante as colunas e preenche as
-- entregas ANTIGAS com a taxa do pedido (`delivery_info->>'taxaEntrega'`), que
-- é exatamente o valor que o painel de motoboys já usava como referência.
--
-- É idempotente: só toca linhas em que a taxa ainda está zerada/NULL.

ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS "valorFrete" NUMERIC(15,2);
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS valor_frete NUMERIC(15,2);

-- 1) Entregas ligadas ao pedido pelo id (formato atual do app).
UPDATE public.entregas e
SET "valorFrete" = COALESCE(NULLIF(e."valorFrete", 0), t.taxa, 0),
    valor_frete = COALESCE(NULLIF(e.valor_frete, 0), t.taxa, 0)
FROM (
  SELECT p.id AS pedido_id,
         MAX(
           CASE
             WHEN p.delivery_info->>'taxaEntrega' ~ '^-?[0-9]+(\.[0-9]+)?$'
               THEN (p.delivery_info->>'taxaEntrega')::numeric
           END
         ) AS taxa
  FROM public.pedidos p
  WHERE p.delivery_info->>'taxaEntrega' IS NOT NULL
  GROUP BY p.id
) t
WHERE t.taxa IS NOT NULL
  AND t.taxa > 0
  AND e."pedidoId" = t.pedido_id
  AND COALESCE(e."valorFrete", 0) = 0
  AND COALESCE(e.valor_frete, 0) = 0;

-- 2) Entregas antigas que só têm o NÚMERO do pedido (sem o id).
UPDATE public.entregas e
SET "valorFrete" = COALESCE(NULLIF(e."valorFrete", 0), t.taxa, 0),
    valor_frete = COALESCE(NULLIF(e.valor_frete, 0), t.taxa, 0)
FROM (
  SELECT p.numero AS pedido_numero,
         MAX(
           CASE
             WHEN p.delivery_info->>'taxaEntrega' ~ '^-?[0-9]+(\.[0-9]+)?$'
               THEN (p.delivery_info->>'taxaEntrega')::numeric
           END
         ) AS taxa
  FROM public.pedidos p
  WHERE p.delivery_info->>'taxaEntrega' IS NOT NULL
  GROUP BY p.numero
) t
WHERE t.taxa IS NOT NULL
  AND t.taxa > 0
  AND e."pedidoNumero" = t.pedido_numero
  AND COALESCE(e."valorFrete", 0) = 0
  AND COALESCE(e.valor_frete, 0) = 0;

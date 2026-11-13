-- ============================================================
-- 022 - CORRIGIR COLUNAS DE VALORES DOS PEDIDOS
-- Diagnostico da Data API confirmou que estas DUAS colunas faltam
-- na tabela public.pedidos do Supabase usado pela loja.
-- Seguro para executar mais de uma vez; nao apaga nem altera pedidos.
-- ============================================================

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS desconto_total NUMERIC(15,2) NOT NULL DEFAULT 0;

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS acrescimo_total NUMERIC(15,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.pedidos.desconto_total IS
  'Valor total de desconto aplicado ao pedido.';

COMMENT ON COLUMN public.pedidos.acrescimo_total IS
  'Valor total de acrescimo aplicado ao pedido.';

NOTIFY pgrst, 'reload schema';

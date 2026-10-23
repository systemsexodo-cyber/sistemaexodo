-- ============================================================
-- 015 — CAMPOS DE NFC-e EM `empresas` QUE O APP MANDA E O BANCO NÃO TINHA
-- ============================================================
-- O modelo `Empresa` envia no upsert duas colunas que NÃO existiam em nenhum
-- banco (nem no local, nem no Supabase local — e o Neon também não as tinha).
-- O PostgREST respondia
--
--   PGRST204: Could not find the 'incluirServicoGarcomNfce' column of
--             'empresas' in the schema cache
--
-- e a gravação da empresa caía (o app loga "não bloqueante", mas a empresa não
-- sobe para a nuvem). Ambos são `bool` com padrão `true`, que é o padrão do
-- modelo — as empresas existentes continuam emitindo igual.
--
--   incluirServicoGarcomNfce  -> serviço do garçom (10%) na NFC-e
--   incluirTaxaEntregaNfce    -> taxa de entrega no valor total da NFC-e
--
-- Apareceu com força quando o HOSTING passou a falar com o Supabase local:
-- ali a gravação é o caminho normal, não mais a do Neon bloqueado (402).
--
-- Idempotente (ADD COLUMN IF NOT EXISTS). Onde aplicar:
--   1. banco local do PC (exodo_db);
--   2. Supabase local (a nuvem do hosting, atrás do Tailscale Funnel);
--   3. Neon (assim que a cota voltar — SQL Editor ou esta migração).
-- Depois de aplicar num banco com PostgREST ligado, recarregue o schema:
--   NOTIFY pgrst, 'reload schema';

ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS "incluirServicoGarcomNfce" BOOLEAN DEFAULT true;

ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS "incluirTaxaEntregaNfce" BOOLEAN DEFAULT true;

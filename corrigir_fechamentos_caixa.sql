-- ==========================================================================
-- CORREÇÃO: CAIXA QUE "NUNCA FECHA" (vínculo fechamento→abertura corrompido)
-- ==========================================================================
-- Causa: uma migração antiga criou colunas duplicadas de TIPO ERRADO na tabela
-- fechamentos_caixa ("aberturaCaixaId" e "dataFechamento" como TIMESTAMP). O
-- sincronizador convertia o ID (13 dígitos) da abertura em timestamp ao gravar
-- essas colunas, e o carregamento do app sobrescrevia o id correto — o
-- fechamento deixava de apontar para a abertura e o caixa ficava SEMPRE ABERTO.
--
-- Este script é IDEMPOTENTE (pode rodar quantas vezes quiser):
--  1) Remove as colunas duplicadas de tipo errado (o dado real está nas
--     colunas snake: abertura_caixa_id TEXT / data_fechamento TEXT);
--  2) Repara registros cujo abertura_caixa_id foi gravado como DATA (timestamp
--     string) em vez do id, casando pela data de abertura;
--  3) (Opcional) Ajusta os mesmos dados na NUVEM quando o aplicativo volta a
--     sincronizar — o app já foi corrigido para enviar as duas chaves.
--
-- ⚠️ Rode no banco PostgreSQL LOCAL (o mesmo do app). Para a nuvem, os
--    fechamentos corrompidos são corrigidos automaticamente no próximo upload,
--    ou você pode corrigi-los manualmente pelo Dashboard do Supabase.
-- ==========================================================================

-- 1. Remover colunas duplicadas com tipo errado
ALTER TABLE fechamentos_caixa DROP COLUMN IF EXISTS "aberturaCaixaId";
ALTER TABLE fechamentos_caixa DROP COLUMN IF EXISTS "dataFechamento";

-- 2. Reparar fechamentos com abertura_caixa_id = data (em vez do id)
UPDATE fechamentos_caixa f
SET abertura_caixa_id = a.id
FROM aberturas_caixa a
WHERE NOT EXISTS (SELECT 1 FROM aberturas_caixa x WHERE x.id = f.abertura_caixa_id)
  AND replace(substr(f.abertura_caixa_id, 1, 19), ' ', 'T')
    = replace(substr(a.data_abertura::text, 1, 19), ' ', 'T');

-- 3. Conferência: aberturas que continuam SEM fechamento (caixas realmente
--    abertos — feche-os manualmente pelo app)
SELECT a.id, a.numero, a.responsavel, a.data_abertura
FROM aberturas_caixa a
WHERE NOT EXISTS (SELECT 1 FROM fechamentos_caixa f WHERE f.abertura_caixa_id = a.id)
ORDER BY a.data_abertura;

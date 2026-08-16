-- =============================================================================
-- LIMPEZA DE CAIXAS DUPLICADOS / FANTASMA - BANCO LOCAL (PostgreSQL)
-- Gerado em 2026-08-15 para a empresa "É O BICHO PETSHOP" (22ae2c16-a730-43f3-a4f9-19f105eb0d13)
-- =============================================================================
-- IMPORTANTE: executar com o APP FECHADO (sistema_exodo_novo.exe encerrado),
-- senão o app pode sobrescrever as alterações a partir da memória.
--
-- O que faz:
--   1. Cria backups das tabelas de caixa.
--   2. Exclui aberturas duplicadas/artefato (id = string de data) — 6 linhas.
--   3. Exclui caixas "fantasma" (0 vendas, abertos e fechados em segundos) — 2 linhas.
--   4. Repara 3 fechamentos cuja referência ao caixa foi corrompida.
--   5. Exclui fechamentos órfãos (sem referência válida de caixa) — 28 linhas.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. BACKUP (tabelas de segurança — não apagar até confirmar que está tudo certo)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS aberturas_caixa_bkp_20260815;
CREATE TABLE aberturas_caixa_bkp_20260815 AS SELECT * FROM aberturas_caixa;
DROP TABLE IF EXISTS fechamentos_caixa_bkp_20260815;
CREATE TABLE fechamentos_caixa_bkp_20260815 AS SELECT * FROM fechamentos_caixa;
DROP TABLE IF EXISTS sangrias_caixa_bkp_20260815;
CREATE TABLE sangrias_caixa_bkp_20260815 AS SELECT * FROM sangrias_caixa;
DROP TABLE IF EXISTS suprimentos_caixa_bkp_20260815;
CREATE TABLE suprimentos_caixa_bkp_20260815 AS SELECT * FROM suprimentos_caixa;
DROP TABLE IF EXISTS vendas_balcao_bkp_20260815;
CREATE TABLE vendas_balcao_bkp_20260815 AS SELECT * FROM vendas_balcao;
SELECT 'backup criado' AS status,
       (SELECT COUNT(*) FROM aberturas_caixa_bkp_20260815) AS aberturas,
       (SELECT COUNT(*) FROM fechamentos_caixa_bkp_20260815) AS fechamentos;

-- -----------------------------------------------------------------------------
-- 1. EXCLUIR aberturas duplicadas/artefato (id é uma string de data, não o id real)
--    Os caixas "reais" (id em milissegundos) permanecem com os mesmos dados.
-- -----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  DELETE FROM aberturas_caixa
  WHERE id IN (
    '2026-04-12T22:14:40.804000+00:00',
    '2026-04-12T23:33:51.921000+00:00',
    '2026-04-13T00:54:16.469000+00:00',
    '2026-04-13T02:19:33.345000+00:00',
    '2026-04-14T21:33:54.147000+00:00',
    '2026-04-28T23:43:54.917000+00:00'
  );
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '1. duplicados excluidos: %', n;
END $$;

-- -----------------------------------------------------------------------------
-- 2. EXCLUIR caixas "fantasma" (0 vendas na janela; abertos/fechados em segundos)
-- -----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  DELETE FROM fechamentos_caixa WHERE abertura_caixa_id IN ('1786758037420', '1786758116938');
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '2a. fechamentos fantasma excluidos: %', n;
  DELETE FROM aberturas_caixa WHERE id IN ('1786758037420', '1786758116938');
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '2b. caixas fantasma excluidos: %', n;
END $$;

-- -----------------------------------------------------------------------------
-- 3. REPARAR os 11 fechamentos válidos: restaura a referência ao caixa (o app
--    com memória antiga costuma gravar abertura_caixa_id vazio). As referências
--    corretas foram confirmadas na nuvem (que continua limpa).
-- -----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1777419834917' WHERE id = '1781564492546';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1783731257334' WHERE id = '1783734795052';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1783904986940' WHERE id = '1784080870744';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1784080880115' WHERE id = '1784336441372';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1784769781612' WHERE id = '1784859662204';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1784860044345' WHERE id = '1785293055402';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1784770155005' WHERE id = '1785462925171';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1785367004561' WHERE id = '1785598761181';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1785598832980' WHERE id = '1785777067105';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1786671765028' WHERE id = '1786758012668';
  UPDATE fechamentos_caixa SET abertura_caixa_id = '1786671232498' WHERE id = '1786758027678';
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '3. fechamentos reparados (ultimo update): %', n;
END $$;

-- -----------------------------------------------------------------------------
-- 4. EXCLUIR fechamentos órfãos (referência vazia/nula e sem caixa correspondente)
-- -----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  DELETE FROM fechamentos_caixa f
  WHERE (f.abertura_caixa_id IS NULL OR f.abertura_caixa_id = '')
     OR NOT EXISTS (SELECT 1 FROM aberturas_caixa a WHERE a.id = f.abertura_caixa_id);
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '4. orfaos excluidos: %', n;
END $$;

-- -----------------------------------------------------------------------------
-- 5. VALIDAÇÃO FINAL
-- -----------------------------------------------------------------------------
SELECT 'validacao' AS etapa,
       (SELECT COUNT(*) FROM aberturas_caixa) AS aberturas,
       (SELECT COUNT(*) FROM aberturas_caixa WHERE id LIKE '20%') AS aberturas_tsid_restantes,
       (SELECT COUNT(*) FROM fechamentos_caixa f
          LEFT JOIN aberturas_caixa a ON a.id = f.abertura_caixa_id
         WHERE a.id IS NULL) AS fechamentos_sem_caixa,
       (SELECT COUNT(*) FROM vendas_balcao) AS vendas;

COMMIT;

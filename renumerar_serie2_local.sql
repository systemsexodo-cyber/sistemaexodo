-- ==========================================================================
-- RENUMERAÇÃO SÉRIE 2 (NFC-e) — Banco LOCAL (PostgreSQL)
-- --------------------------------------------------------------------------
-- Problema: a série 2 do caixa do Carlos estava seguindo a numeração global
-- da série 1 (notas 243, 244, 245, 246), quando deveria começar em 1.
--
-- Ações:
--   1. Renumera as 4 notas de homologação da série 2:
--        243 -> 1, 244 -> 2, 245 -> 3, 246 -> 4
--      (recalculando chave de acesso e QR Code, pois o número vai embutido
--       na chave e o hash do QR depende da chave).
--   2. Corrige o contador global 'ultimo_numero_nfce' da empresa, que foi
--      inflado pelas notas 243-246 da série 2 — volta para 242 (máximo real
--      da série 1), para a série 1 continuar em 243 sem pular numeração.
--
-- EXECUTAR SOMENTE COM O APP FECHADO (sistema_exodo_novo.exe)
-- ==========================================================================

BEGIN;

-- ==========================================================================
-- 1. Renumerar as 4 notas de homologação da série 2
-- ==========================================================================
UPDATE nfces
SET numero = '1',
    chave_acesso = '35260804829400000165650020000000011956378402',
    qr_code = 'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000011956378402|2|2|1|06CADAA4C8D3BD824BC28794CCF4865E32BE52F7',
    updated_at = NOW()
WHERE id = '1786673172122' AND serie = '2';

UPDATE nfces
SET numero = '2',
    chave_acesso = '35260804829400000165650020000000021019291405',
    qr_code = 'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000021019291405|2|2|1|3CB4AECD612345A4E63A045DE4BD21FC6C321E46',
    updated_at = NOW()
WHERE id = '1786804969893' AND serie = '2';

UPDATE nfces
SET numero = '3',
    chave_acesso = '35260804829400000165650020000000031458439587',
    qr_code = 'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000031458439587|2|2|1|71DFDB82A5DCC4B3792F840A6ECD1861DD65B8D1',
    updated_at = NOW()
WHERE id = '1786808575633' AND serie = '2';

UPDATE nfces
SET numero = '4',
    chave_acesso = '35260804829400000165650020000000041841766908',
    qr_code = 'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000041841766908|2|2|1|E9F1141C960548B13A907C6DBC2EA12BBAB18CE4',
    updated_at = NOW()
WHERE id = '1786808646585' AND serie = '2';

-- ==========================================================================
-- 2. Corrigir o contador global da empresa (série 1 continua em 243)
-- ==========================================================================
UPDATE empresas
SET configuracoes = jsonb_set(
        COALESCE(configuracoes, '{}'::jsonb),
        '{ultimo_numero_nfce}',
        '"242"'
    ),
    updated_at = NOW()
WHERE id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

-- ==========================================================================
-- Validação (deve mostrar série 2 = números 1, 2, 3, 4)
-- ==========================================================================
SELECT numero, serie, status, chave_acesso FROM nfces WHERE serie = '2' ORDER BY numero::int;

COMMIT;

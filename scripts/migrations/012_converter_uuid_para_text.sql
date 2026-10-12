-- ============================================================
-- 008 — CONVERTER COLUNAS uuid -> text (só banco LOCAL)
-- ============================================================
-- A nuvem usa ids TEXT ('1776036401244', '1', 'produto-diversos-9999'). Numa
-- migração antiga algumas colunas nasceram como UUID aqui e o download da
-- nuvem falhava. Esta migração converte o que ainda estiver como uuid.
--
-- Exceção: sync_logs.id permanece uuid no banco de referência.
--
-- Idempotente: se nada estiver como uuid, o loop não faz nada.

DO $$
DECLARE
    r record;
    qtd integer := 0;
BEGIN
    FOR r IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE data_type = 'uuid'
          AND table_schema = 'public'
          AND NOT (table_name = 'sync_logs' AND column_name = 'id')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP DEFAULT',
                       r.table_name, r.column_name);
        EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I TYPE text USING %I::text',
                       r.table_name, r.column_name, r.column_name);
        qtd := qtd + 1;
        RAISE NOTICE '[012] % . % -> text', r.table_name, r.column_name;
    END LOOP;
    RAISE NOTICE '[012] colunas uuid convertidas: %', qtd;
END $$;

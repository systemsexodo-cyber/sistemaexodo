-- ============================================================
-- 007 — REMOVER FOREIGN KEYS DO BANCO LOCAL
-- ============================================================
-- O banco de referência (e a nuvem) NÃO têm chaves estrangeiras. FKs que
-- sobraram de instalações antigas fazem o download falhar quando as linhas
-- chegam em ordem diferente da esperada.
--
-- Idempotente: se não houver FK, o loop não faz nada.

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT conrelid::regclass::text AS tabela, conname
        FROM pg_constraint
        WHERE contype = 'f' AND connamespace = 'public'::regnamespace
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.tabela, r.conname);
    END LOOP;
END $$;

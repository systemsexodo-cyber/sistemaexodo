-- ============================================================
-- 007 — PUBLICAR VERSÃO (bridge_config) — só NUVEM / Supabase
-- ============================================================
-- O segundo 403 da tela "Atualizar todos os clientes": depois do pacote subir,
-- gravar a versão na tabela bridge_config falhava porque o desktop fala com a
-- nuvem como papel `anon` e a tabela só liberava SELECT para anon.
--
-- Depende do papel anon (Supabase). Num banco LOCAL o bloco é pulado.
-- Idempotente. Espelhada de supabase/migrations/007.

DO $guard$
BEGIN
    IF to_regclass('public.bridge_config') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        RAISE NOTICE '[007] bridge_config/anon ausente (banco local) — pulando politica de publicacao.';
        RETURN;
    END IF;

    EXECUTE 'drop policy if exists bridge_config_anon_tudo on public.bridge_config';
    EXECUTE 'create policy bridge_config_anon_tudo on public.bridge_config for all to anon using (true) with check (true)';
END
$guard$;

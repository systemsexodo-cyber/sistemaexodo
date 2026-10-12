-- ============================================================
-- 006 — POLÍTICAS DE STORAGE QUE FALTAVAM (só NUVEM / Supabase)
-- ============================================================
-- Resolve o 403 "new row violates row-level security policy" ao publicar uma
-- atualização ("Atualizar todos os clientes") ou subir backup para a nuvem.
--
-- Depende do schema storage e dos papéis anon/authenticated, que só existem no
-- Supabase. Num banco LOCAL o bloco é pulado. Idempotente.
--
-- Espelhada de supabase/migrations/006. Ver scripts/migrations/README.md.

DO $guard$
BEGIN
    IF to_regclass('storage.objects') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[006] storage/anon/authenticated ausente (banco local) — pulando politicas de storage.';
        RETURN;
    END IF;

    -- atualizacoes (pacotes de versão e as notas .txt)
    EXECUTE 'drop policy if exists atualizacoes_anon_tudo on storage.objects';
    EXECUTE 'create policy atualizacoes_anon_tudo on storage.objects for all to anon using (bucket_id = ''atualizacoes'') with check (bucket_id = ''atualizacoes'')';
    EXECUTE 'drop policy if exists atualizacoes_authenticated_tudo on storage.objects';
    EXECUTE 'create policy atualizacoes_authenticated_tudo on storage.objects for all to authenticated using (bucket_id = ''atualizacoes'') with check (bucket_id = ''atualizacoes'')';

    -- backups (backup em nuvem do banco da empresa)
    EXECUTE 'drop policy if exists backups_anon_tudo on storage.objects';
    EXECUTE 'create policy backups_anon_tudo on storage.objects for all to anon using (bucket_id = ''backups'') with check (bucket_id = ''backups'')';
    EXECUTE 'drop policy if exists backups_authenticated_tudo on storage.objects';
    EXECUTE 'create policy backups_authenticated_tudo on storage.objects for all to authenticated using (bucket_id = ''backups'') with check (bucket_id = ''backups'')';

    -- dumps (dumps locais enviados para a nuvem)
    EXECUTE 'drop policy if exists dumps_anon_tudo on storage.objects';
    EXECUTE 'create policy dumps_anon_tudo on storage.objects for all to anon using (bucket_id = ''dumps'') with check (bucket_id = ''dumps'')';
    EXECUTE 'drop policy if exists dumps_authenticated_tudo on storage.objects';
    EXECUTE 'create policy dumps_authenticated_tudo on storage.objects for all to authenticated using (bucket_id = ''dumps'') with check (bucket_id = ''dumps'')';
END
$guard$;

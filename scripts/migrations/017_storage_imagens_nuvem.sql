-- ============================================================
-- 017 — STORAGE DA NUVEM: buckets públicos usados pelo app
-- ============================================================
-- Sintoma que originou esta migração (log do app):
--
--   Neon Storage: falha ao enviar "atualizacoes/logos/<empresa>/Logo_....png"
--   via Supabase (HTTP 400) {"statusCode":"403","error":"Unauthorized",
--   "message":"new row violates row-level security policy","code":"AccessDenied"}
--   Neon Storage: falha ao criar o bucket "imagens" (HTTP 400) ... AccessDenied
--   nenhum bucket alternativo aceitou a gravação
--
-- São duas causas somadas:
--   1. o bucket `imagens` (fotos de produto, logo, banners) não existe nessa
--      nuvem — a 016 o cria, mas ela não foi aplicada aqui;
--   2. os buckets que já existem (`atualizacoes`) estão sem política de
--      storage. O app fala com o Storage pela chave anônima (papel `anon`) e,
--      sem política, o RLS recusa o INSERT — é o 403 acima.
--
-- Esta migração faz a 006 + 016 de uma vez e cobre também os buckets que o app
-- usa como alternativa de gravação. É idempotente: pode rodar quantas vezes
-- quiser. Num banco local (sem storage/anon/authenticated) ela se auto-pula.
--
-- APLIQUE NO SQL EDITOR DA NUVEM (Supabase). Depois disso o upload de logo,
-- banner e foto de produto passa a funcionar de qualquer rede — a URL pública
-- fica em <storage>/storage/v1/object/public/imagens/....

DO $guard$
DECLARE
    bucket  text;
    -- `empresas` (pacote de atualizacao), `configuracoes` (bridge/exe) e
    -- `nfces` (PDF da NFC-e) tambem sao gravados pelo app com a chave anon.
    buckets text[] := ARRAY['imagens', 'atualizacoes', 'backups', 'dumps',
                            'xmls', 'empresas', 'configuracoes', 'nfces'];
BEGIN
    IF to_regclass('storage.buckets') IS NULL
       OR to_regclass('storage.objects') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[017] storage/anon/authenticated ausente (banco local) — pulando buckets de storage.';
        RETURN;
    END IF;

    -- 1. Buckets do app. ON CONFLICT conserta um bucket que exista privado:
    --    a URL pública responde 400 em bucket privado e a imagem não apareceria
    --    na loja. EXCEÇÃO: `dumps` guarda backup do banco — se já existe, mantém a
    --    privacidade (só é criado quando falta).
    FOREACH bucket IN ARRAY buckets LOOP
        IF bucket = 'dumps' THEN
            INSERT INTO storage.buckets (id, name, public)
            VALUES ('dumps', 'dumps', false)
            ON CONFLICT (id) DO NOTHING;
        ELSE
            INSERT INTO storage.buckets (id, name, public)
            VALUES (bucket, bucket, true)
            ON CONFLICT (id) DO UPDATE SET public = true;
        END IF;
    END LOOP;

    -- 2. Políticas de leitura/gravação para os papéis que o app usa.
    FOREACH bucket IN ARRAY buckets LOOP
        EXECUTE format('drop policy if exists %I on storage.objects', bucket || '_anon_tudo');
        EXECUTE format(
            'create policy %I on storage.objects for all to anon using (bucket_id = %L) with check (bucket_id = %L)',
            bucket || '_anon_tudo', bucket, bucket);

        EXECUTE format('drop policy if exists %I on storage.objects', bucket || '_authenticated_tudo');
        EXECUTE format(
            'create policy %I on storage.objects for all to authenticated using (bucket_id = %L) with check (bucket_id = %L)',
            bucket || '_authenticated_tudo', bucket, bucket);
    END LOOP;

    -- 3. service_role (dono do projeto) ignora RLS, mas a política explícita
    --    documenta a intenção e cobre papéis criados depois.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        FOREACH bucket IN ARRAY buckets LOOP
            EXECUTE format('drop policy if exists %I on storage.objects', bucket || '_service_role_tudo');
            EXECUTE format(
                'create policy %I on storage.objects for all to service_role using (bucket_id = %L) with check (bucket_id = %L)',
                bucket || '_service_role_tudo', bucket, bucket);
        END LOOP;
    END IF;

    RAISE NOTICE '[017] buckets públicos e políticas de storage garantidos.';
END
$guard$;

-- --------------------------------------------------------------------------
-- CONFERÊNCIA (opcional)
-- --------------------------------------------------------------------------
-- select id, public from storage.buckets order by id;
-- select bucket_id, count(*) from storage.objects group by bucket_id;

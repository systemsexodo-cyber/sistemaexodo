-- ============================================================
-- 016 — BUCKET `imagens` (fotos de produtos, logo, banners, galeria)
-- ============================================================
-- Sintoma que originou esta migração:
--
--   Neon Storage: falha ao enviar "imagens/logos/..." via Supabase
--   (HTTP 404) {"statusCode":"404","error":"Bucket not found",
--               "message":"Bucket not found","code":"NoSuchBucket"}
--
-- O app só faz upload no bucket `imagens`, mas ele nunca foi criado na nuvem
-- (nem na instalação padrão, nem em nenhuma migração). O app fala com o
-- Storage como `anon` e o papel `anon` NÃO pode criar bucket — por isso a
-- tentativa automática do próprio app falha e o lojista fica sem subir logo,
-- foto de produto e imagens da galeria.
--
-- O que este arquivo faz (idempotente):
--   1. cria o bucket `imagens` como PÚBLICO (a URL pública é a que a loja
--      online usa para exibir as fotos);
--   2. libera leitura/gravação para `anon` e `authenticated` no bucket,
--      seguindo o mesmo modelo da 006.
--
-- Só vale na nuvem. Num banco local o bloco se auto-pula, como manda o
-- README desta pasta. Aplique colando no SQL Editor do Supabase.

DO $guard$
BEGIN
    IF to_regclass('storage.buckets') IS NULL
       OR to_regclass('storage.objects') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[016] storage/anon/authenticated ausente (banco local) — pulando bucket imagens.';
        RETURN;
    END IF;

    -- 1. Bucket público (ON CONFLICT mantém idempotente e conserta um bucket
    --    que já exista privado).
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('imagens', 'imagens', true)
    ON CONFLICT (id) DO UPDATE SET public = true;

    -- 2. Políticas de acesso ao bucket.
    EXECUTE 'drop policy if exists imagens_anon_tudo on storage.objects';
    EXECUTE 'create policy imagens_anon_tudo on storage.objects for all to anon using (bucket_id = ''imagens'') with check (bucket_id = ''imagens'')';

    EXECUTE 'drop policy if exists imagens_authenticated_tudo on storage.objects';
    EXECUTE 'create policy imagens_authenticated_tudo on storage.objects for all to authenticated using (bucket_id = ''imagens'') with check (bucket_id = ''imagens'')';

    RAISE NOTICE '[016] bucket "imagens" criado/liberado com sucesso.';
END
$guard$;

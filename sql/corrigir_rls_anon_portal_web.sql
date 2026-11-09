-- ============================================================================
-- Corrige o acesso da chave pública (anon) usada pelo Portal Êxodo (web)
--
-- SINTOMA
--   Um navegador sem cache (guia anônima, outro PC, celular novo) abre o site
--   em servidorsupabase.tail9b4943.ts.net e não carrega nada: a lista de
--   empresas mostra só a empresa de demonstração ("Exodo Systems",
--   CNPJ 12.345.678/0001-90, "SEM SYNC") e, ao entrar, todas as telas ficam
--   vazias.
--
-- CAUSA
--   No Supabase da VM (`supabase-db`) o RLS está LIGADO em todas as tabelas e
--   não existe nenhuma policy em `public`. A chave que o site leva no bundle
--   (`NEON_DATA_API_KEY` em `build/web/assets/assets/app.env`) é a `anon`,
--   então a Data API responde `200 []` em toda leitura e 401 em toda escrita.
--   No PC de quem já usou o sistema isso passa despercebido porque o Flutter
--   Web guarda os dados no Hive/IndexedDB local; um navegador novo não tem
--   esse cache e mostra apenas o cadastro padrão do código.
--
-- CORREÇÃO
--   Cria as policies `anon_all_<tabela>` / `auth_all_<tabela>` em todas as
--   tabelas de `public`, que é o modelo já usado pelo restante do projeto
--   (ver `supabase/migracao_completa_supabase.sql`): a identidade do app é
--   validada na tabela `usuarios` e a Data API usa uma credencial de cliente
--   compartilhada.
--
--   ATENÇÃO: isso dá à chave pública acesso de leitura/escrita a essas
--   tabelas (inclusive `usuarios`, que guarda a senha em texto). É o mesmo
--   modelo que o projeto já adotava; trocar por algo mais restrito exige
--   tirar a chave do bundle e passar as operações por uma Function.
--
-- Idempotente: pode rodar quantas vezes quiser.
-- Como aplicar (na máquina que hospeda a VM):
--   ssh -i %USERPROFILE%\.ssh\id_ed25519_vm -p 2222 charles@127.0.0.1 \
--     "docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1" \
--     < sql/corrigir_rls_anon_portal_web.sql
-- ============================================================================

BEGIN;

DO $$
DECLARE
    tabela TEXT;
    papel TEXT;
    papeis TEXT[] := ARRAY['anon', 'authenticated', 'service_role'];
BEGIN
    FOR tabela IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
          AND c.relrowsecurity
        ORDER BY c.relname
    LOOP
        FOREACH papel IN ARRAY papeis LOOP
            EXECUTE format('GRANT ALL ON public.%I TO %I', tabela, papel);
            EXECUTE format(
                'DROP POLICY IF EXISTS %I ON public.%I',
                papel || '_all_' || tabela,
                tabela
            );
            EXECUTE format(
                'CREATE POLICY %I ON public.%I FOR ALL TO %I USING (true) WITH CHECK (true)',
                papel || '_all_' || tabela,
                tabela,
                papel
            );
        END LOOP;
    END LOOP;
END $$;

-- Conferência rápida do que ficou configurado.
SELECT tablename, policyname, roles::text, cmd
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

COMMIT;

-- ==========================================================================
-- BUCKET 'xmls' - XMLs DAS NOTAS PARA O PORTAL DO CONTADOR
-- ==========================================================================
-- Cria o bucket onde ficam os XMLs que o contador baixa pelo portal.
--
-- Estrutura dentro do bucket:
--   xmls/<empresa_id>/<chave_de_acesso>-nfe.xml
--
-- COMO USAR:
--   1. Supabase Dashboard -> SQL Editor -> New query
--   2. Cole TODO este script e clique em RUN
--   3. Pode executar quantas vezes quiser (é idempotente)
--
-- Depois, envie os XMLs que já existem em disco com:
--   .venv\Scripts\python.exe enviar_xmls_storage.py
-- ==========================================================================

-- --------------------------------------------------------------------------
-- 1. CRIAR O BUCKET
-- --------------------------------------------------------------------------
-- Privado: o download é feito pelo app/portal com a chave service_role
-- (que passa por cima do RLS). Nada fica exposto por URL pública.
insert into storage.buckets (id, name, public)
values ('xmls', 'xmls', false)
on conflict (id) do nothing;

-- --------------------------------------------------------------------------
-- 2. POLÍTICAS DE ACESSO
-- --------------------------------------------------------------------------
drop policy if exists "xmls_service_role_tudo" on storage.objects;
create policy "xmls_service_role_tudo"
  on storage.objects for all
  to service_role
  using (bucket_id = 'xmls')
  with check (bucket_id = 'xmls');

-- Usuários logados no sistema também podem ler/gravar (sincronização do app).
drop policy if exists "xmls_authenticated_tudo" on storage.objects;
create policy "xmls_authenticated_tudo"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'xmls')
  with check (bucket_id = 'xmls');

-- --------------------------------------------------------------------------
-- CONFERÊNCIA (opcional)
-- --------------------------------------------------------------------------
-- select count(*) as xmls_na_nuvem from storage.objects where bucket_id = 'xmls';
-- select name from storage.objects where bucket_id = 'xmls' order by name limit 10;

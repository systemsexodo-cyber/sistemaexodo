-- ============================================================
-- CRIAR_BUCKETS_STORAGE_SUPABASE.sql
-- Cria os buckets usados pelos backups do app e dá acesso aos
-- papéis authenticated e service_role.
--
-- COMO USAR:
--   1. Abra o Supabase Dashboard -> SQL Editor (do projeto
--      febffvlpvxtiihvnfuts.supabase.co)
--   2. Cole TODO este script e clique em RUN
--   3. Pode executar quantas vezes quiser (é idempotente)
-- ============================================================

-- Buckets usados:
--   'backups' -> backup JSON completo da empresa (Botão "Fazer Backup Agora")
--   'dumps'   -> dumps PostgreSQL .dump/.sql enviados de uma máquina
-- ============================================================

insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('dumps', 'dumps', false)
on conflict (id) do nothing;

-- Acesso total (SELECT/INSERT/UPDATE/DELETE) para usuários autenticados
-- e para a service_role dentro dos dois buckets.
drop policy if exists "backups_authenticated_tudo" on storage.objects;
create policy "backups_authenticated_tudo"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'backups')
  with check (bucket_id = 'backups');

drop policy if exists "dumps_authenticated_tudo" on storage.objects;
create policy "dumps_authenticated_tudo"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'dumps')
  with check (bucket_id = 'dumps');

drop policy if exists "backups_service_role_tudo" on storage.objects;
create policy "backups_service_role_tudo"
  on storage.objects for all
  to service_role
  using (bucket_id = 'backups')
  with check (bucket_id = 'backups');

drop policy if exists "dumps_service_role_tudo" on storage.objects;
create policy "dumps_service_role_tudo"
  on storage.objects for all
  to service_role
  using (bucket_id = 'dumps')
  with check (bucket_id = 'dumps');

-- Observação: o app Desktop envia os arquivos com a chave service_role
-- (a mesma que já usa para sincronizar as tabelas), então funciona mesmo
-- sem estas políticas. Elas servem de garantia/fallback e para outros usos.

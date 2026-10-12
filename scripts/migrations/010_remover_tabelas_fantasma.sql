-- ============================================================
-- 006 — REMOVER TABELAS FANTASMA (só banco LOCAL)
-- ============================================================
-- Tabelas que existem em instalações antigas mas NÃO existem na nuvem. Elas
-- causavam spam de HTTP 404 a cada ciclo de sincronização (o sincronizador
-- tentava subir/baixar tabelas que o Supabase não conhece).
--
-- Idempotente: DROP IF EXISTS não reclama se já não existir.

DROP TABLE IF EXISTS public.itens_pedido;
DROP TABLE IF EXISTS public.pagamentos;
DROP TABLE IF EXISTS public.app_update_config;

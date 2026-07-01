-- ============================================================
-- DIAGNÓSTICO DE RLS E PERMISSÕES NO SUPABASE
-- Verifica se as políticas permitem INSERT/UPDATE via anon key
-- ============================================================

-- Lista todas as tabelas com RLS habilitado
SELECT 
    schemaname || '.' || tablename as tabela,
    relrowsecurity as rls_habilitado,
    relforcerowsecurity as rls_forcado
FROM pg_class 
JOIN pg_tables ON pg_class.relname = pg_tables.tablename
WHERE schemaname = 'public' 
AND tablename IN ('produtos', 'aberturas_caixa', 'produto_historico', 'clientes', 'pedidos', 'vendas_balcao')
ORDER BY tablename;

-- Verifica políticas de INSERT para cada tabela
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles::text,
    cmd as comando,
    qual as condicao_using,
    with_check as condicao_with_check
FROM pg_policies 
WHERE schemaname = 'public'
AND tablename IN ('produtos', 'aberturas_caixa', 'produto_historico', 'clientes', 'pedidos', 'vendas_balcao')
AND cmd IN ('INSERT', 'ALL')
ORDER BY tablename, cmd;

-- Verifica se as tabelas têm política INSERT permissiva
SELECT 
    tablename,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_policies p 
            WHERE p.tablename = pg_tables.tablename 
            AND p.cmd IN ('INSERT', 'ALL')
        ) THEN '✅ Tem política INSERT'
        ELSE '❌ SEM política INSERT'
    END as status_insert
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN ('produtos', 'aberturas_caixa', 'produto_historico', 'clientes', 'pedidos', 'vendas_balcao')
ORDER BY tablename;

-- Verifica permissões para anon (autenticação anônima)
SELECT 
    table_name,
    privilege_type,
    grantee
FROM information_schema.table_privileges
WHERE table_schema = 'public'
AND table_name IN ('produtos', 'aberturas_caixa', 'produto_historico', 'clientes', 'pedidos', 'vendas_balcao')
AND grantee IN ('anon', 'authenticated', 'public')
ORDER BY table_name, privilege_type;

-- ============================================================
-- CORREÇÃO RÁPIDA (execute se necessário)
-- ============================================================

-- Para produto_historico (se não tiver política INSERT)
CREATE POLICY IF NOT EXISTS "insert_anon_produto_historico" ON produto_historico
FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY IF NOT EXISTS "insert_authenticated_produto_historico" ON produto_historico
FOR INSERT TO authenticated WITH CHECK (true);

-- Para aberturas_caixa (se não tiver política INSERT)
CREATE POLICY IF NOT EXISTS "insert_anon_aberturas_caixa" ON aberturas_caixa
FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY IF NOT EXISTS "insert_authenticated_aberturas_caixa" ON aberturas_caixa
FOR INSERT TO authenticated WITH CHECK (true);

-- Para produtos (se não tiver política INSERT)
CREATE POLICY IF NOT EXISTS "insert_anon_produtos" ON produtos
FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY IF NOT EXISTS "insert_authenticated_produtos" ON produtos
FOR INSERT TO authenticated WITH CHECK (true);

-- ============================================================
-- GRANT PERMISSÕES (se necessário)
-- ============================================================

GRANT ALL ON produtos TO anon;
GRANT ALL ON produtos TO authenticated;
GRANT ALL ON aberturas_caixa TO anon;
GRANT ALL ON aberturas_caixa TO authenticated;
GRANT ALL ON produto_historico TO anon;
GRANT ALL ON produto_historico TO authenticated;

-- ============================================================
-- RESUMO FINAL
-- ============================================================
SELECT 'Diagnóstico concluído!' as status;

-- ============================================================
-- VERIFICAÇÃO FINAL - Tabelas necessárias para sincronização
-- ============================================================

-- 1. Verificar se todas as tabelas existem
SELECT 
    table_name,
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables 
                     WHERE table_schema = 'public' 
                     AND table_name = t.table_name) 
        THEN '✅ Existe'
        ELSE '❌ NÃO existe'
    END as status
FROM (VALUES 
    ('produtos'),
    ('aberturas_caixa'),
    ('produto_historico'),
    ('clientes'),
    ('pedidos')
) as t(table_name);

-- 2. Verificar RLS nas tabelas principais
SELECT 
    c.relname as tabela,
    c.relrowsecurity as rls_habilitado,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = c.relname) as total_policies
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' 
AND n.nspname = 'public'
AND c.relname IN ('produtos', 'aberturas_caixa', 'produto_historico', 'clientes', 'pedidos')
ORDER BY c.relname;

-- 3. Contar registros (verificar se dados estão chegando)
SELECT 'produtos' as tabela, COUNT(*) as registros FROM produtos
UNION ALL
SELECT 'aberturas_caixa', COUNT(*) FROM aberturas_caixa
UNION ALL
SELECT 'produto_historico', COUNT(*) FROM produto_historico
UNION ALL
SELECT 'clientes', COUNT(*) FROM clientes;

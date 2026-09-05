-- ============================================================
-- DIAGNÓSTICO DO HISTÓRICO DE PRODUTOS NO SUPABASE
-- Execute este SQL no Supabase SQL Editor para verificar
-- por que os dados não estão sendo sincronizados
-- ============================================================

-- 1. VERIFICAR SE A TABELA EXISTE
SELECT 
    'TABELA' as tipo,
    schemaname || '.' || tablename as nome,
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'produto_historico') 
        THEN '✅ Tabela existe'
        ELSE '❌ Tabela NÃO existe'
    END as status
UNION ALL
-- 2. VERIFICAR SE RLS ESTÁ HABILITADO
SELECT 
    'RLS' as tipo,
    'Row Level Security' as nome,
    CASE 
        WHEN relrowsecurity = true THEN '✅ RLS habilitado'
        ELSE '⚠️ RLS desabilitado'
    END as status
FROM pg_class 
WHERE relname = 'produto_historico' AND relnamespace = 'public'::regnamespace
UNION ALL
-- 3. VERIFICAR POLÍTICAS EXISTENTES
SELECT 
    'POLICY' as tipo,
    policyname as nome,
    '✅ Política: ' || cmd as status
FROM pg_policies 
WHERE tablename = 'produto_historico'
UNION ALL
-- 4. VERIFICAR SE A TABELA ESTÁ EXPOSTA NA API REST
SELECT 
    'API' as tipo,
    'REST API' as nome,
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_class WHERE relname = 'produto_historico' AND relnamespace = 'public'::regnamespace) 
        THEN '✅ Tabela visível na API (schema public)'
        ELSE '❌ Tabela não visível'
    END as status
UNION ALL
-- 5. CONTAR REGISTROS NA TABELA
SELECT 
    'DADOS' as tipo,
    'Total de registros' as nome,
    COALESCE(
        (SELECT COUNT(*)::TEXT || ' registros' FROM produto_historico), 
        '0 registros'
    ) as status;

-- ============================================================
-- TESTE DE INSERÇÃO MANUAL (opcional - execute se quiser testar)
-- ============================================================
-- Descomente as linhas abaixo para testar uma inserção manual:
/*
INSERT INTO produto_historico (
    id, empresa_id, produto_id, produto_nome, tipo_operacao, campos_alterados
) VALUES (
    'test-' || gen_random_uuid()::TEXT,
    'test-empresa',
    'test-produto',
    'Produto Teste',
    'UPDATE',
    'nome,preco'
);

SELECT '✅ Teste de inserção manual concluído' as resultado;
DELETE FROM produto_historico WHERE empresa_id = 'test-empresa';
*/

-- ============================================================
-- VERIFICAR ESTRUTURA DA TABELA
-- ============================================================
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'produto_historico' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- VERIFICAR PERMISSÕES
-- ============================================================
SELECT 
    grantee,
    privilege_type
FROM information_schema.table_privileges 
WHERE table_name = 'produto_historico'
AND table_schema = 'public'
ORDER BY privilege_type;

-- ============================================================
-- RESUMO DAS POLÍTICAS RLS
-- ============================================================
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual as using_expression,
    with_check as with_check_expression
FROM pg_policies 
WHERE tablename = 'produto_historico';

-- ============================================================
-- NOTAS PARA CORREÇÃO
-- ============================================================
/*
Se a tabela NÃO EXISTIR:
1. Execute a migração: 004_produto_historico.sql

Se RLS estiver habilitado mas sem políticas de INSERT:
1. Adicione a política de INSERT:
   CREATE POLICY "insert_empresa" ON produto_historico
   FOR INSERT TO authenticated WITH CHECK (true);

Se a tabela não estiver exposta na API:
1. Verifique em Project Settings > API > Exposed schemas
2. Adicione 'public' se não estiver listado

Se houver erro de permissão:
1. Execute: GRANT ALL ON produto_historico TO authenticated;
2. Execute: GRANT ALL ON produto_historico TO anon;
*/

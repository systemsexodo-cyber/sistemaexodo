-- ============================================================
-- DIAGNÓSTICO: COMPARAR TABELAS ENTRE OS DOIS BANCOS
-- ============================================================
-- Execute este SQL em AMBOS os bancos (PostgreSQL local e Supabase)
-- e compare os resultados.
-- ============================================================

-- 1. LISTAR TODAS AS TABELAS PUBLICAS E SUAS QUANTIDADES DE COLUNAS
SELECT 
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns c 
     WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) as colunas,
    (SELECT COUNT(*) FROM information_schema.table_constraints tc
     JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
     WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
     AND tc.constraint_type = 'PRIMARY KEY') as pk_count,
    '---' as separador
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name NOT LIKE 'pg_%'
ORDER BY table_name;

-- ============================================================
-- 2. QUAIS TABELAS DO SISTEMA EXISTEM AQUI?
-- ============================================================
WITH tabelas_sistema AS (
    SELECT unnest(ARRAY[
        'aberturas_caixa',
        'agendamentos_servico',
        'bridge_config',
        'cache_dados',
        'clientes',
        'comissoes_vendedores',
        'contas_pagar',
        'empresas',
        'entregas',
        'estoque_historico',
        'exodo_config',
        'fechamentos_caixa',
        'funcionarios',
        'links_vendedores',
        'mesas_comandas',
        'motoristas',
        'nfces',
        'notas_entrada',
        'ordens_servico',
        'pedidos',
        'produto_historico',
        'produtos',
        'romaneios',
        'sangrias_caixa',
        'servicos',
        'suprimentos_caixa',
        'sync_logs',
        'sync_status',
        'taxas_entrega',
        'trocas_devolucoes',
        'usuarios',
        'vendas_balcao'
    ]) AS table_name
)
SELECT 
    s.table_name,
    CASE 
        WHEN t.table_name IS NOT NULL THEN 'EXISTE'
        ELSE 'FALTANDO'
    END as status,
    CASE 
        WHEN t.table_name IS NOT NULL THEN (SELECT COUNT(*) FROM information_schema.columns c WHERE c.table_schema = 'public' AND c.table_name = s.table_name)::TEXT
        ELSE '-'
    END as colunas
FROM tabelas_sistema s
LEFT JOIN information_schema.tables t 
    ON t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
    AND t.table_name = s.table_name
ORDER BY s.table_name;

-- ============================================================
-- 3. TABELAS EXTRAS (existem neste banco mas NAO estao no sistema)
-- ============================================================
SELECT 
    table_name as tabela_extra,
    (SELECT COUNT(*) FROM information_schema.columns c 
     WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) as colunas
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name NOT LIKE 'pg_%'
  AND table_name NOT IN (
    'aberturas_caixa', 'agendamentos_servico', 'bridge_config', 'cache_dados',
    'clientes', 'comissoes_vendedores', 'contas_pagar', 'empresas',
    'entregas', 'estoque_historico', 'exodo_config', 'fechamentos_caixa',
    'funcionarios', 'links_vendedores', 'mesas_comandas', 'motoristas',
    'nfces', 'notas_entrada', 'ordens_servico', 'pedidos',
    'produto_historico', 'produtos', 'romaneios', 'sangrias_caixa',
    'servicos', 'suprimentos_caixa', 'sync_logs', 'sync_status',
    'taxas_entrega', 'trocas_devolucoes', 'usuarios', 'vendas_balcao'
  )
ORDER BY table_name;

-- ============================================================
-- 4. ESTRUTURA DAS TABELAS (colunas, tipos, constraints)
-- ============================================================
SELECT 
    c.table_name,
    c.column_name,
    c.data_type,
    c.is_nullable,
    c.column_default,
    CASE WHEN pk.column_name IS NOT NULL THEN 'PK' ELSE '' END as pk
FROM information_schema.columns c
LEFT JOIN (
    SELECT kcu.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu 
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY'
      AND tc.table_schema = 'public'
) pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
WHERE c.table_schema = 'public'
  AND c.table_name IN (
    'aberturas_caixa', 'agendamentos_servico', 'clientes', 'empresas',
    'entregas', 'produto_historico', 'produtos', 'sync_logs', 'sync_status',
    'vendas_balcao'
  )
ORDER BY c.table_name, c.ordinal_position;

-- ============================================================
-- 5. RESUMO FINAL
-- ============================================================
SELECT 
    'RESUMO' as info,
    COUNT(*)::TEXT || ' tabelas no total' as valor
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
  AND table_name NOT LIKE 'pg_%'

UNION ALL

SELECT 
    'SISTEMA',
    COUNT(*)::TEXT || ' tabelas do sistema'
FROM (
    SELECT unnest(ARRAY[
        'aberturas_caixa', 'agendamentos_servico', 'bridge_config', 'cache_dados',
        'clientes', 'comissoes_vendedores', 'contas_pagar', 'empresas',
        'entregas', 'estoque_historico', 'exodo_config', 'fechamentos_caixa',
        'funcionarios', 'links_vendedores', 'mesas_comandas', 'motoristas',
        'nfces', 'notas_entrada', 'ordens_servico', 'pedidos',
        'produto_historico', 'produtos', 'romaneios', 'sangrias_caixa',
        'servicos', 'suprimentos_caixa', 'sync_logs', 'sync_status',
        'taxas_entrega', 'trocas_devolucoes', 'usuarios', 'vendas_balcao'
    ]) AS table_name
) s
JOIN information_schema.tables t 
    ON t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
    AND t.table_name = s.table_name;

-- ============================================================
-- EXECUTE UMA ÚNICA VEZ NO SUPABASE DASHBOARD > SQL EDITOR
-- Isso cria uma função que o app pode usar para criar tabelas
-- ============================================================

CREATE OR REPLACE FUNCTION executar_sql(sql_query TEXT)
RETURNS TEXT AS $$
BEGIN
  EXECUTE sql_query;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERRO: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dá permissão para o service_role usar a função
GRANT EXECUTE ON FUNCTION executar_sql(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION executar_sql(TEXT) TO anon;

-- Teste (deve retornar 'OK')
SELECT executar_sql('CREATE TABLE IF NOT EXISTS _teste_conexao (id TEXT PRIMARY KEY)');
SELECT executar_sql('DROP TABLE IF EXISTS _teste_conexao');

-- ============================================================
-- PRONTO! Agora o app pode criar tabelas automaticamente.
-- ============================================================

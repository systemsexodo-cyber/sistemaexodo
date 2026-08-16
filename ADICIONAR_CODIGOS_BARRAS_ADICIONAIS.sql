-- ============================================================
--  MÚLTIPLOS CÓDIGOS DE BARRAS POR PRODUTO
--  Executar no Supabase (SQL Editor) antes de testar a sincronização
-- ============================================================
--  Adiciona a coluna que guarda os códigos de barras adicionais
--  (além do código de barras principal 'codigo_barras').
--  Sem esta coluna, o app não consegue sincronizar produtos
--  que possuem códigos de barras extras (erro PGRST204).
-- ============================================================

ALTER TABLE produtos
  ADD COLUMN IF NOT EXISTS codigos_barras_adicionais JSONB DEFAULT '[]'::jsonb;

-- Índice GIN (opcional) para buscas futuras dentro da lista de códigos
-- CREATE INDEX IF NOT EXISTS idx_produtos_codigos_barras_adicionais
--   ON produtos USING gin (codigos_barras_adicionais);

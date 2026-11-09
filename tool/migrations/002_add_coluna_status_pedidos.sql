-- Migration 002: Add coluna status nas pedidos
-- Esta migration adiciona a coluna status na tabela pedidos se ela ainda nao existir

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'pedidos' AND column_name = 'status'
  ) THEN
    ALTER TABLE pedidos ADD COLUMN status TEXT DEFAULT 'pendente';
    INSERT INTO _schema_migrations (versao, descricao) VALUES ('002', 'Add status na tabela pedidos');
  END IF;
END $$;
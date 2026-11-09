-- Migration 001: Criar tabela de configuração do sistema
-- Esta migration cria a tabela config_sistema e registra o schema versionado

-- Criar tabela se não existir
CREATE TABLE IF NOT EXISTS config_sistema (
  chave TEXT PRIMARY KEY,
  valor TEXT NOT NULL,
  atualizada_em TIMESTAMP DEFAULT now()
);

-- Registrar esta migration na tabela de controle
-- Note: A tabela _schema_migrations deve existir antes ou ser criada na primeira migration
INSERT INTO _schema_migrations (versao, descricao) VALUES ('001', 'Create config_sistema table');
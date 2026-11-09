-- Migration 003: Criar tabela pagamentos
-- Esta migration cria uma nova tabela para registrar pagamentos

CREATE TABLE IF NOT EXISTS pagamentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id UUID REFERENCES pedidos(id),
  valor NUMERIC(12,2) NOT NULL,
  metodo_pagamento TEXT NOT NULL,
  status_pagamento TEXT DEFAULT 'pendente',
  data_pagamento TIMESTAMP DEFAULT now(),
  descricao TEXT
);

-- Registrar migration
INSERT INTO _schema_migrations (versao, descricao) VALUES ('003', 'Create pagamentos table');
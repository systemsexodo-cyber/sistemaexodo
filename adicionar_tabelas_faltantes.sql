-- Script para adicionar tabelas faltantes no SQLite
-- Execute no DB Browser for SQLite no arquivo exodo_local.db

-- 1. Notas de Entrada
CREATE TABLE IF NOT EXISTS notas_entrada_local (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT,
    fornecedor TEXT,
    valor_total REAL,
    data_emissao TEXT,
    data_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_notas_entrada_empresa ON notas_entrada_local(empresa_id);

-- 2. Ordens de Servio
CREATE TABLE IF NOT EXISTS ordens_servico_local (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT,
    cliente_nome TEXT,
    status TEXT,
    valor_total REAL,
    data_abertura TEXT,
    data_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_ordens_servico_empresa ON ordens_servico_local(empresa_id);

-- 3. Trocas e Devolues
CREATE TABLE IF NOT EXISTS trocas_devolucoes_local (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT,
    tipo TEXT,
    cliente_nome TEXT,
    valor REAL,
    status TEXT,
    data TEXT,
    data_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_trocas_devolucoes_empresa ON trocas_devolucoes_local(empresa_id);

-- Verificar tabelas criadas
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_local' ORDER BY name;

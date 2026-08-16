-- ==========================================================================
-- CRIAÇÃO DA TABELA NFES NO SUPABASE - SISTEMA ÊXODO  (v2 - corrige erro 42703)
-- ==========================================================================
-- Execute este script no SQL Editor do Supabase:
--   Dashboard do Supabase > SQL Editor > New query > colar > Run
--
-- O que este script faz:
--   1. DETECTA e REMOVE a tabela nfes incompleta (se existir) e RECRIA correta
--   2. Cria a tabela public.nfes (emissões de NF-e) SEPARADA da nfces (NFC-e)
--   3. Cria índices, habilita RLS e cria as políticas de acesso
--   4. MOVE as NF-e (modelo 55) que estavam MISTURADAS na tabela nfces
--      para a nova tabela nfes (identificadas pela chave de acesso,
--      posições 21-22 = modelo do documento)
--
-- ⚠️ CORREÇÃO IMPORTANTE (v2):
-- O script de manutenção SUPABASE_FIX_ALL.sql cria qualquer tabela da lista
-- com um schema MÍNIMO (id, empresa_id, created_at, updated_at). Se ele foi
-- executado antes, a tabela nfes já existe incompleta e o comando
-- "CREATE TABLE IF NOT EXISTS" era ignorado, causando o erro:
--     ERROR: 42703: column "chave_acesso" does not exist
-- Esta versão resolve isso: se a nfes existir SEM a coluna chave_acesso,
-- ela é removida automaticamente e recriada com o schema completo.
-- (Seguro: a tabela mínima está vazia - o app nunca conseguiu gravar nela.)
-- ==========================================================================

-- --------------------------------------------------------------------------
-- 0. REMOVER TABELA NFES INCOMPLETA (se existir sem a coluna chave_acesso)
-- --------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'public' AND tablename = 'nfes')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = 'public' AND table_name = 'nfes'
                         AND column_name = 'chave_acesso') THEN
        RAISE NOTICE 'Tabela nfes incompleta detectada - removendo para recriar do zero';
        DROP TABLE IF EXISTS public.nfes;
    END IF;
END $$;

-- --------------------------------------------------------------------------
-- 1. CRIAR TABELA NFES (com todas as colunas que o app Flutter envia)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.nfes (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL DEFAULT '',
    numero TEXT DEFAULT '',
    serie TEXT DEFAULT '',
    chave_acesso TEXT DEFAULT '',
    protocolo TEXT DEFAULT '',
    status TEXT DEFAULT 'pendente',
    valor_total NUMERIC DEFAULT 0,
    cpf_cnpj_consumidor TEXT DEFAULT '',
    nome_consumidor TEXT DEFAULT '',
    qr_code TEXT DEFAULT '',
    xml_autorizado TEXT DEFAULT '',
    xml_enviado TEXT DEFAULT '',
    xml_retorno TEXT DEFAULT '',
    data_emissao TIMESTAMP WITH TIME ZONE,
    itens JSONB DEFAULT '[]'::jsonb,
    pagamentos JSONB DEFAULT '[]'::jsonb,
    modelo INTEGER DEFAULT 55,
    venda_id TEXT DEFAULT '',
    venda_numero TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    -- Colunas camelCase (o app envia os dois formatos - compatibilidade)
    "dataEmissao" TIMESTAMP WITH TIME ZONE,
    "empresaId" TEXT,
    "valorTotal" NUMERIC,
    "cpfCnpjConsumidor" TEXT,
    "nomeConsumidor" TEXT,
    "chaveAcesso" TEXT,
    "xmlEnviado" TEXT,
    "xmlRetorno" TEXT,
    "qrCode" TEXT,
    "vendaId" TEXT,
    "vendaNumero" TEXT,
    "createdAt" TIMESTAMP WITH TIME ZONE,
    "updatedAt" TIMESTAMP WITH TIME ZONE
);

-- --------------------------------------------------------------------------
-- 2. ÍNDICES
-- --------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nfes_empresa_id ON public.nfes(empresa_id);
CREATE INDEX IF NOT EXISTS idx_nfes_chave_acesso ON public.nfes(chave_acesso);
CREATE INDEX IF NOT EXISTS idx_nfes_created_at ON public.nfes(created_at DESC);

-- --------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY E POLÍTICAS
-- --------------------------------------------------------------------------
ALTER TABLE public.nfes ENABLE ROW LEVEL SECURITY;

-- Política de acesso total para usuários autenticados (app)
DROP POLICY IF EXISTS nfes_permitir_autenticado ON public.nfes;
CREATE POLICY nfes_permitir_autenticado ON public.nfes
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Política de acesso total para o service_role (sistema/admin)
DROP POLICY IF EXISTS nfes_admin ON public.nfes;
CREATE POLICY nfes_admin ON public.nfes
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- --------------------------------------------------------------------------
-- 4. MIGRAR AS NF-e QUE ESTAVAM MISTURADAS NA TABELA NFCES
--    (identificadas pela chave de acesso: posições 21-22 = modelo; 55 = NF-e)
-- --------------------------------------------------------------------------
INSERT INTO public.nfes (
    id, empresa_id, numero, serie, chave_acesso, protocolo, status,
    valor_total, cpf_cnpj_consumidor, nome_consumidor, qr_code, xml_autorizado,
    data_emissao, itens, pagamentos, modelo, venda_id, created_at, updated_at
)
SELECT
    id, empresa_id, numero, serie, chave_acesso, protocolo, status,
    valor_total, cpf_cnpj_consumidor, nome_consumidor, qr_code, xml_autorizado,
    data_emissao, itens, pagamentos, 55, "vendaId", created_at, updated_at
FROM public.nfces
WHERE substr(chave_acesso, 21, 2) = '55'
  AND NOT EXISTS (SELECT 1 FROM public.nfes n WHERE n.id = nfces.id);

-- --------------------------------------------------------------------------
-- 5. REMOVER AS NF-e DA TABELA NFCES (apenas as que foram migradas para nfes)
-- --------------------------------------------------------------------------
DELETE FROM public.nfces nfc
WHERE substr(nfc.chave_acesso, 21, 2) = '55'
  AND EXISTS (SELECT 1 FROM public.nfes n WHERE n.id = nfc.id);

-- --------------------------------------------------------------------------
-- CONFERÊNCIA (opcional): deve retornar a quantidade de NF-e migradas
-- --------------------------------------------------------------------------
-- SELECT count(*) AS nfes_migradas FROM public.nfes;
-- SELECT count(*) AS nfces_restantes FROM public.nfces;

-- ==========================================================================
-- PORTAL DO CONTADOR - SISTEMA ÊXODO
-- ==========================================================================
-- Cria a estrutura do portal onde o CONTADOR entra com CNPJ + senha e baixa
-- os XMLs das notas da empresa (NFC-e emitidas, NF-e emitidas e NF-e de
-- entrada/recebidas), separados por tipo.
--
-- COMO USAR:
--   1. Abra o Supabase Dashboard -> SQL Editor -> New query
--   2. Cole TODO este script e clique em RUN
--   3. Pode executar quantas vezes quiser (é idempotente)
--
-- Depois de rodar este script, cadastre o acesso do contador com:
--   python criar_acesso_portal_contador.py --cnpj 00000000000191 --senha "MinhaSenha"
-- ==========================================================================

-- --------------------------------------------------------------------------
-- 1. TABELA DE ACESSOS DO CONTADOR
-- --------------------------------------------------------------------------
-- Cada linha = um login de contador. O campo `cnpj` é o que ele digita na
-- tela e também identifica de qual empresa ele enxerga as notas.
-- Para um escritório que atende vários clientes, crie um acesso por CNPJ.
CREATE TABLE IF NOT EXISTS public.portal_contador_acessos (
    id            TEXT PRIMARY KEY,
    cnpj          TEXT NOT NULL,              -- somente dígitos
    nome          TEXT,
    email         TEXT,
    senha_hash    TEXT NOT NULL,              -- sha256(salt + senha) em hex
    salt          TEXT NOT NULL,
    ativo         BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_acesso TIMESTAMP WITH TIME ZONE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at    TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Um único acesso por CNPJ (evita duplicidade de login no portal).
CREATE UNIQUE INDEX IF NOT EXISTS idx_portal_contador_acessos_cnpj
    ON public.portal_contador_acessos (cnpj);

-- --------------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY
-- --------------------------------------------------------------------------
ALTER TABLE public.portal_contador_acessos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS portal_contador_permitir_autenticado ON public.portal_contador_acessos;
CREATE POLICY portal_contador_permitir_autenticado ON public.portal_contador_acessos
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- O app/portal usa a chave service_role (passa por cima do RLS).
DROP POLICY IF EXISTS portal_contador_admin ON public.portal_contador_acessos;
CREATE POLICY portal_contador_admin ON public.portal_contador_acessos
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- --------------------------------------------------------------------------
-- 3. GARANTIR AS COLUNAS DE XML NAS TABELAS FISCAIS
-- --------------------------------------------------------------------------
-- O portal lê o XML direto das tabelas (é de lá que vêm os dados da nuvem).
-- Estas colunas já existem na maioria dos bancos; os comandos abaixo só
-- garantem que nada fique faltando (todos ignoram quando a coluna existe).

-- NFC-e emitidas (modelo 65) -> tabela nfces
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS xml_autorizado TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS xml_enviado TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS xml_retorno TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "xmlAutorizado" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "xmlEnviado" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "xmlRetorno" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS chave_acesso TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "chaveAcesso" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS protocolo TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS numero TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS serie TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS valor_total NUMERIC;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "valorTotal" NUMERIC;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS nome_consumidor TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "nomeConsumidor" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS cpf_cnpj_consumidor TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "cpfCnpjConsumidor" TEXT;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS data_emissao TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.nfces ADD COLUMN IF NOT EXISTS "dataEmissao" TIMESTAMP WITH TIME ZONE;

-- NF-e emitidas (modelo 55) -> tabela nfes
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS xml_autorizado TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS xml_enviado TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS xml_retorno TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS "xmlEnviado" TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS "xmlRetorno" TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS chave_acesso TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS protocolo TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS numero TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS serie TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS valor_total NUMERIC;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS "valorTotal" NUMERIC;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS nome_consumidor TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS cpf_cnpj_consumidor TEXT;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS data_emissao TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.nfes ADD COLUMN IF NOT EXISTS "dataEmissao" TIMESTAMP WITH TIME ZONE;

-- NF-e de entrada / recebidas -> tabela notas_entrada
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS numero TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS serie TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS modelo TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "numeroNotaReal" TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "chaveNFe" TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "fornecedorNome" TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "fornecedorCNPJ" TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS xml_original TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "xmlOriginal" TEXT;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS data_emissao TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "dataEmissao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS valor_total NUMERIC;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS "valorTotal" NUMERIC;
ALTER TABLE public.notas_entrada ADD COLUMN IF NOT EXISTS status TEXT;

-- --------------------------------------------------------------------------
-- 4. ÍNDICES PARA O FILTRO DO PORTAL (empresa + data)
-- --------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_nfces_empresa_data
    ON public.nfces (empresa_id, data_emissao DESC);
CREATE INDEX IF NOT EXISTS idx_nfes_empresa_data
    ON public.nfes (empresa_id, data_emissao DESC);
CREATE INDEX IF NOT EXISTS idx_notas_entrada_empresa
    ON public.notas_entrada (empresa_id);

-- --------------------------------------------------------------------------
-- CONFERÊNCIA (opcional)
-- --------------------------------------------------------------------------
-- SELECT cnpj, nome, ativo, ultimo_acesso FROM public.portal_contador_acessos;

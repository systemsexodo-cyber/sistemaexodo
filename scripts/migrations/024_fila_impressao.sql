-- ============================================================
-- 024 — FILA DE IMPRESSÃO REMOTA (CELULAR -> CAIXA)
-- ============================================================
-- FONTE ÚNICA: aplicado pelo app no banco LOCAL (runner em
-- lib/services/database_service.dart) e deve ser colado no banco da NUVEM
-- (Neon) para as vendas lançadas pelo celular em 4G também chegarem ao PC
-- do caixa. É portável de propósito.
--
-- Fluxo:
--   1. O celular finaliza a venda/pedido e grava uma linha aqui
--      (`status = 'pendente'`);
--   2. O app instalado no Windows do caixa varre a fila a cada 2,5 s e
--      imprime no spooler do Windows (`status = 'impresso'`);
--   3. Se a impressora falhar, a linha fica com `status = 'erro'` e o
--      motivo em `erro` (nada é apagado).
--
-- Na LAN o celular escreve no MESMO PostgreSQL do caixa, então a impressão
-- sai em milissegundos. Em 4G o celular escreve na nuvem e o sincronizador
-- do caixa traz a linha no ciclo seguinte.
--
-- Idempotente: pode rodar quantas vezes quiser.

CREATE TABLE IF NOT EXISTS public.fila_impressao (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL,
    -- 'venda_balcao' | 'pedido' | 'producao'
    -- 'producao' = via de cozinha/bar: o conteudo_json é o TicketProducao
    -- (setor + nome da impressora do setor + itens), impresso pelo PC do
    -- caixa direto na impressora daquele setor.
    tipo TEXT NOT NULL,
    documento_id TEXT,
    numero TEXT,
    -- Cupom serializado (VendaBalcao.toMap()/Pedido.toMap()) para o caixa
    -- reconstruir o PDF sem depender de mais nenhuma consulta.
    conteudo_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    impressora_destino TEXT NOT NULL DEFAULT 'caixa',
    -- 'pendente' | 'impresso' | 'erro'
    status TEXT NOT NULL DEFAULT 'pendente',
    erro TEXT,
    criado_em TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    impresso_em TIMESTAMP WITH TIME ZONE,
    impresso_por TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Bancos que já receberam a tabela numa versão anterior (sem estes campos)
-- ganham as colunas aqui: sem `updated_at`/`created_at` o download delta da
-- nuvem não enxerga a linha e o trigger abaixo falharia.
ALTER TABLE public.fila_impressao
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now();
ALTER TABLE public.fila_impressao
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now();

-- Consulta do monitor do caixa: pendentes de uma empresa, mais antigas antes.
CREATE INDEX IF NOT EXISTS idx_fila_impressao_pendentes
    ON public.fila_impressao (empresa_id, status, criado_em);

CREATE INDEX IF NOT EXISTS idx_fila_impressao_documento
    ON public.fila_impressao (documento_id);

-- Mantém updated_at para o download delta da nuvem. Não carimba quando o
-- sincronizador aplica réplica (exodo.sync_mode='on'), para as máquinas não
-- ficarem puxando a mesma linha para sempre.
CREATE OR REPLACE FUNCTION public.set_fila_impressao_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('exodo.sync_mode', true) IS DISTINCT FROM 'on' THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_fila_impressao_updated_at ON public.fila_impressao;
CREATE TRIGGER set_fila_impressao_updated_at
    BEFORE UPDATE ON public.fila_impressao
    FOR EACH ROW
    EXECUTE FUNCTION public.set_fila_impressao_updated_at();

-- OUTBOX LOCAL: entra no log de eventos como as outras tabelas operacionais,
-- para o sincronizador levar a linha do caixa de volta para a nuvem (status
-- 'impresso') e para outros PCs. Na nuvem este bloco é pulado.
DO $$
BEGIN
    IF to_regclass('public._exodo_sync_log') IS NOT NULL
       AND to_regprocedure('public.log_sync_event()') IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_exodo_sync_log_fila_impressao'
        ) THEN
            CREATE TRIGGER trg_exodo_sync_log_fila_impressao
                AFTER INSERT OR UPDATE OR DELETE ON public.fila_impressao
                FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
        END IF;
    END IF;
END $$;

COMMENT ON TABLE public.fila_impressao IS
    'Fila de impressão remota: vendas, pedidos e vias de produção feitos no celular e impressos no PC do caixa (cada via de produção na impressora do seu setor).';

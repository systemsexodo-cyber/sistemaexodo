-- ============================================================
-- 005 — AJUSTES DE ESTOQUE EM LOTE (ESTOQUE E PREÇO)
-- ============================================================
-- FONTE ÚNICA: este arquivo é aplicado pelo próprio app no banco LOCAL
-- (runner em lib/services/database_service.dart) e também pode ser colado no
-- Supabase SQL Editor para a nuvem. É portável de propósito.
--
-- Guarda cada aplicação feita na tela "Ajuste Geral • Estoque e Preço":
-- quem aplicou, quando, o que mudou e os valores ANTERIORES de cada produto —
-- o que permite desfazer o ajuste inteiro depois.
--
-- Idempotente: pode rodar quantas vezes quiser.

CREATE TABLE IF NOT EXISTS public.ajustes_estoque_lote (
    id TEXT PRIMARY KEY,
    empresa_id TEXT NOT NULL,
    data TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    usuario TEXT,
    observacao TEXT,
    origem TEXT DEFAULT 'Ajuste em massa',
    -- Detalhamento item a item: [{produto_id, produto_nome, produto_codigo,
    -- estoque_anterior, estoque_novo, preco_anterior, preco_novo}, ...]
    itens JSONB NOT NULL DEFAULT '[]'::jsonb,
    total_itens INTEGER DEFAULT 0,
    total_estoques INTEGER DEFAULT 0,
    total_precos INTEGER DEFAULT 0,
    desfeito BOOLEAN NOT NULL DEFAULT false,
    data_desfeito TIMESTAMP WITH TIME ZONE,
    usuario_desfeito TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Índices para consultas rápidas
CREATE INDEX IF NOT EXISTS idx_ajustes_estoque_lote_empresa ON public.ajustes_estoque_lote(empresa_id);
CREATE INDEX IF NOT EXISTS idx_ajustes_estoque_lote_data ON public.ajustes_estoque_lote(data DESC);
CREATE INDEX IF NOT EXISTS idx_ajustes_estoque_lote_usuario ON public.ajustes_estoque_lote(usuario);
CREATE INDEX IF NOT EXISTS idx_ajustes_estoque_lote_desfeito ON public.ajustes_estoque_lote(desfeito);

-- Trigger para manter updated_at (usada também pelo sync delta).
-- Não carimba quando o sincronizador aplica réplica (exodo.sync_mode='on'),
-- senão as máquinas puxariam a mesma linha para sempre — mesma regra do
-- set_updated_at() do banco local.
CREATE OR REPLACE FUNCTION public.set_ajustes_estoque_lote_updated_at()
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

DROP TRIGGER IF EXISTS set_ajustes_estoque_lote_updated_at ON public.ajustes_estoque_lote;
CREATE TRIGGER set_ajustes_estoque_lote_updated_at
    BEFORE UPDATE ON public.ajustes_estoque_lote
    FOR EACH ROW
    EXECUTE FUNCTION public.set_ajustes_estoque_lote_updated_at();

-- OUTBOX LOCAL: se este banco tem a fila de sincronização (_exodo_sync_log),
-- entra no log de eventos como as outras tabelas operacionais. Na nuvem a
-- tabela não existe e este bloco é pulado.
DO $$
BEGIN
    IF to_regclass('public._exodo_sync_log') IS NOT NULL
       AND to_regprocedure('public.log_sync_event()') IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_exodo_sync_log_ajustes_estoque_lote'
        ) THEN
            CREATE TRIGGER trg_exodo_sync_log_ajustes_estoque_lote
                AFTER INSERT OR UPDATE OR DELETE ON public.ajustes_estoque_lote
                FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
        END IF;
    END IF;
END $$;

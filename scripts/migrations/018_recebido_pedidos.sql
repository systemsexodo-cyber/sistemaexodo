-- ============================================================
-- 018 — COLUNA recebido NA TABELA pedidos
-- ============================================================
-- Problema: a coluna 'recebido' na tabela 'pedidos' nao existe no schema da nuvem
-- (Supabase/PostgREST), gerando erros PGRST204 nos logs de sincronia.
-- Isso faz com que o app tente enviar a coluna 'recebido' para o banco,
-- mas a tabela nao tem ela, o que enche o log mas nao bloqueia o pedido.
-- 
-- Solucao: criar a coluna 'recebido boolean default false' na tabela 'pedidos'
-- do banco da nuvem para limpar os erros de sincronia e permitir
-- que o status do pedido seja controlado corretamente.
--
-- After this migration, the app will be able to properly track which
-- payments have been received, and the order status ('Pago' vs 'Pendente')
-- will be calculated correctly based on the 'recebido' field of each payment.
--
-- Idempotente: pode rodar quantas vezes quiser. Se a coluna ja existir,
-- o ALTER TABLE nao causara erro.

DO $$
BEGIN
    -- Adicionar coluna 'recebido' se nao existir
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'pedidos' 
        AND column_name = 'recebido'
    ) THEN
        ALTER TABLE pedidos ADD COLUMN recebido boolean DEFAULT false;
        RAISE NOTICE 'Coluna recebido adicionada à tabela pedidos';
    ELSE
        RAISE NOTICE 'Coluna recebido ja existe na tabela pedidos — migracao idempotente';
    END IF;
END$$;

-- Comment on the column for documentation
COMMENT ON COLUMN pedidos.recebido IS 'Indica se o pedido foi pago/recebido (true) ou nao (false). Usado pelo PDV para determinar status do pedido.';

-- Update any existing orders to have recebido = false (default)
UPDATE pedidos SET recebido = false WHERE recebido IS NULL;

-- Grant access to the anonymous role if needed
-- GRANT SELECT, UPDATE ON pedidos TO anon; -- descomente se necessario

-- Note: O campo 'recebido' dos pagamentos (PagamentoPedido.recebido)
-- ja existe no modelo Dart e é usado para calcular o total recebido.
-- Esta coluna na tabela pedidos eh um complemento para tracking no level de pedido.

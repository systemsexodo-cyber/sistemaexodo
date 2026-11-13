-- ============================================================
-- 019 - Codigo publico de acompanhamento do pedido
-- ============================================================
-- A loja online gera um codigo curto (link_cliente) para o cliente
-- acompanhar o pedido em /pedido/<codigo>. Sem a coluna na nuvem, o app
-- gravava o pedido sem esse codigo e o rastreio pelo celular nao achava nada.
-- Idempotente: pode rodar quantas vezes quiser.

ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS link_cliente text;
CREATE INDEX IF NOT EXISTS idx_pedidos_link_cliente ON pedidos (link_cliente);
COMMENT ON COLUMN pedidos.link_cliente IS 'Codigo publico de acompanhamento do pedido (pagina /pedido/<codigo>).';

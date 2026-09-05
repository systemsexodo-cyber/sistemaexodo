-- Mover TODOS os dados da empresa antiga para a empresa BMJ (22ae2c16-a730-43f3-a4f9-19f105eb0d13)
-- Execute no Supabase SQL Editor

DO $$
DECLARE
  empresa_antiga TEXT := '66a880c8-51c7-496f-826b-d2ff9ab8ed2d';
  empresa_nova TEXT := '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
  contador INT;
BEGIN
  -- Produtos
  UPDATE produtos SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Produtos movidos: %', contador;

  -- Clientes
  UPDATE clientes SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Clientes movidos: %', contador;

  -- Pedidos
  UPDATE pedidos SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Pedidos movidos: %', contador;

  -- Vendas Balcão
  UPDATE vendas_balcao SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Vendas Balcão movidas: %', contador;

  -- Mesas/Comandas
  UPDATE mesas_comandas SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Mesas/Comandas movidas: %', contador;

  -- Agendamentos
  UPDATE agendamentos_servico SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Agendamentos movidos: %', contador;

  -- Serviços
  UPDATE servicos SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Serviços movidos: %', contador;

  -- Ordens de Serviço
  UPDATE ordens_servico SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Ordens de Serviço movidas: %', contador;

  -- Trocas/Devoluções
  UPDATE trocas_devolucoes SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Trocas/Devoluções movidas: %', contador;

  -- Notas de Entrada
  UPDATE notas_entrada SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Notas de Entrada movidas: %', contador;

  -- Funcionários
  UPDATE funcionarios SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Funcionários movidos: %', contador;

  -- Taxas de Entrega
  UPDATE taxas_entrega SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Taxas de Entrega movidas: %', contador;

  -- Contas a Pagar
  UPDATE contas_pagar SET empresa_id = empresa_nova WHERE empresa_id = empresa_antiga;
  GET DIAGNOSTICS contador = ROW_COUNT;
  RAISE NOTICE 'Contas a Pagar movidas: %', contador;

  RAISE NOTICE '=== MIGRAÇÃO CONCLUÍDA ===';
END $$;

-- Verificar se os dados foram movidos
SELECT 
  (SELECT COUNT(*) FROM produtos WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') as produtos_nova_empresa,
  (SELECT COUNT(*) FROM clientes WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') as clientes_nova_empresa,
  (SELECT COUNT(*) FROM pedidos WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') as pedidos_nova_empresa;

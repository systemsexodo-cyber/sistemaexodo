-- Mover os dados da empresa "Empresa de testes" (6bb61873) para a BMJ (22ae2c16)
-- O app está aberto na BMJ, mas o catalogo/vendas foram gravados com o
-- empresa_id da "Empresa de testes" — por isso os produtos apareciam zerados.
--
-- Seguro para rodar no Postgres LOCAL e no Supabase (tabelas inexistentes sao
-- ignoradas). Idempotente: rodar de novo nao altera nada.

DO $$
DECLARE
  origem  TEXT := '6bb61873-768f-4162-8b36-e3ef41fbb34f'; -- Empresa de testes
  destino TEXT := '22ae2c16-a730-43f3-a4f9-19f105eb0d13'; -- BMJ Petshop
  tabelas TEXT[] := ARRAY[
    'produtos',
    'clientes',
    'pedidos',
    'vendas_balcao',
    'mesas_comandas',
    'agendamentos_servico',
    'orcamentos',
    'taxas_entrega',
    'contas_pagar'
  ];
  t TEXT;
  n INT;
  total INT := 0;
BEGIN
  FOREACH t IN ARRAY tabelas LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'tabela % inexistente - pulando', t;
      CONTINUE;
    END IF;

    EXECUTE format('UPDATE public.%I SET empresa_id = $1 WHERE empresa_id = $2', t)
      USING destino, origem;

    GET DIAGNOSTICS n = ROW_COUNT;
    total := total + n;
    RAISE NOTICE '%: % linha(s) movida(s)', t, n;
  END LOOP;

  RAISE NOTICE 'TOTAL: % linha(s) movida(s) de % para %', total, origem, destino;
END $$;

-- Conferencia
SELECT
  (SELECT COUNT(*) FROM public.produtos  WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') AS produtos_bmj,
  (SELECT COUNT(*) FROM public.clientes  WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') AS clientes_bmj,
  (SELECT COUNT(*) FROM public.vendas_balcao WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13') AS vendas_bmj;

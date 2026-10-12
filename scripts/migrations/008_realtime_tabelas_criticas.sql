-- ============================================================
-- 008 — REALTIME DAS TABELAS CRÍTICAS (só NUVEM / Supabase)
-- ============================================================
-- Publica as tabelas críticas na publicação supabase_realtime e liga
-- REPLICA IDENTITY FULL, para UPDATE/DELETE chegarem em <100ms (multi-PC).
--
-- Num banco LOCAL a publicação supabase_realtime não existe: o bloco pula com
-- NOTICE (undefined_object). REPLICA IDENTITY é inofensivo aqui.
-- Idempotente. Espelhada de supabase/migrations/008.

DO $$
DECLARE
    t    text;
    alvo text[] := ARRAY[
        'mesas_comandas', 'vendas_balcao', 'pedidos', 'produtos',
        'aberturas_caixa', 'fechamentos_caixa', 'agendamentos_servico',
        'contas_pagar', 'clientes', 'funcionarios', 'notas_entrada',
        'ordens_servico', 'taxas_entrega', 'romaneios', 'bridge_status'
    ];
BEGIN
    FOREACH t IN ARRAY alvo LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            RAISE NOTICE '[008] tabela % nao existe — pulando', t;
            CONTINUE;
        END IF;

        BEGIN
            EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '[008] replica identity em %: %', t, SQLERRM;
        END;

        BEGIN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
            RAISE NOTICE '[008] % adicionada a publicacao', t;
        EXCEPTION
            WHEN duplicate_object THEN NULL;
            WHEN undefined_object THEN
                RAISE NOTICE '[008] publicacao supabase_realtime nao existe — habilite Realtime no painel';
        END;
    END LOOP;
END $$;

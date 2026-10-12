-- ============================================================
-- 013 — BLOQUEAR TROCA DE EMPRESA (PROTEÇÃO ANTI-MISTURA)
-- ============================================================
-- Regra de ouro: um registro NUNCA troca de dono. Se uma linha já pertence à
-- empresa A, nenhuma gravação pode alterar o `empresa_id` dela para B — vinda
-- do app, do sincronizador, de SQL manual ou do Realtime.
--
-- Por que existe: o `INSERT ... ON CONFLICT (id) DO UPDATE` casa pela chave
-- primária `id`, que NÃO inclui a empresa. Com ids repetidos entre empresas
-- (ex.: produto "Diversos" `produto-diversos-9999`, ids '1'..'15', ou
-- `Date.now().millisecondsSinceEpoch` colidindo), a gravação de uma empresa
-- atualizava a linha da outra e o registro "mudava de dono" — foi assim que os
-- dados se misturaram.
--
-- Esta trava é a rede de segurança FINAL, no banco: mesmo que algum caminho de
-- código esqueça de conferir a empresa, o UPDATE é recusado com erro. As travas
-- do app (`_carimbarEmpresaId`, `_upsertRows`, `WHERE ... = EXCLUDED.empresa_id`)
-- evitam o caso no dia a dia; esta garante que ele nunca passe.
--
-- Tabelas GLOBAIS (`empresas`, `usuarios`) ficam de fora: elas não pertencem a
-- uma empresa só.
--
-- MOVER DADOS ENTRE EMPRESAS DE PROPÓSITO (suporte): esta trava BLOQUEIA
-- `UPDATE ... SET empresa_id = ...`. Se for realmente preciso mover um registro
-- de empresa (ex.: os scripts corrigir_dados_empresa.sql / mover_dados_empresa.sql),
-- desligue a trava daquela tabela na hora e religue depois:
--
--     ALTER TABLE public.produtos DISABLE TRIGGER trg_exodo_empresa_imutavel;
--     UPDATE public.produtos SET empresa_id = '<nova>' WHERE ...;
--     ALTER TABLE public.produtos ENABLE TRIGGER trg_exodo_empresa_imutavel;
--
-- Idempotente: pode rodar várias vezes. Portável (roda no Supabase igual).

CREATE OR REPLACE FUNCTION public.exodo_bloquear_troca_de_empresa()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_old text;
    v_new text;
    v_id  text;
BEGIN
    v_old := to_jsonb(OLD)->>'empresa_id';
    v_new := to_jsonb(NEW)->>'empresa_id';

    -- Só bloqueia quando a linha JÁ tinha dono e o novo dono é diferente.
    -- NULL/'': o dono ainda não tinha sido definido (não é troca).
    IF v_old IS NOT NULL AND v_old <> ''
       AND v_new IS DISTINCT FROM v_old THEN
        v_id := COALESCE(to_jsonb(OLD)->>'id', '?');
        RAISE EXCEPTION
            'TROCA DE EMPRESA BLOQUEADA: % (id=%) tentou mudar de empresa_id ''%'' para ''%''. Um registro nunca troca de dono.',
            TG_TABLE_NAME, v_id, v_old, COALESCE(v_new, '<nulo>')
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

-- Anexa a trava a TODA tabela que tem `empresa_id`, exceto as globais.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'public'
          AND c.column_name = 'empresa_id'
          AND t.table_type = 'BASE TABLE'
          AND c.table_name NOT IN ('empresas', 'usuarios')
    LOOP
        -- Recria sempre para pegar a versão mais nova da função.
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_exodo_empresa_imutavel ON public.%I',
            r.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_exodo_empresa_imutavel '
            'BEFORE UPDATE ON public.%I '
            'FOR EACH ROW EXECUTE FUNCTION public.exodo_bloquear_troca_de_empresa()',
            r.table_name);
        RAISE NOTICE '[013] trava de empresa aplicada em %', r.table_name;
    END LOOP;
END $$;

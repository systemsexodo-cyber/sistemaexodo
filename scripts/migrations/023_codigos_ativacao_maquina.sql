-- ============================================================
-- 023 — CÓDIGOS DE ATIVAÇÃO PRESOS À MÁQUINA (só NUVEM / Supabase)
-- ============================================================
-- Acrescenta `machine_id` em `licencas_ativacao`: quando preenchido, o código
-- só pode ser consumido pelo computador cujo ID foi informado na geração
-- (tools/licencas/gerar_codigos_ativacao.js --maquina <64 hex>).
--
--   - `machine_id` NULL  = código comum (emitido antes desta migração ou sem
--     `--maquina`): vale para qualquer computador, mas continua sendo de USO
--     ÚNICO (`usada_por`);
--   - `machine_id` preenchido = só aquela máquina pode usá-lo; nas demais a
--     função responde 403 `codigo_outra_maquina`.
--
-- Acesso apenas pela edge function `licenca-instalacao` (service_role): RLS
-- já ligado na migração 021, sem policy.
--
-- Idempotente: pode rodar várias vezes. Só adiciona coluna/índice.
-- ============================================================

DO $guard$
BEGIN
    IF to_regclass('auth.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[023] auth/authenticated ausente (banco local) — pulando vínculo de máquina do código de ativação.';
        RETURN;
    END IF;

    IF to_regclass('public.licencas_ativacao') IS NULL THEN
        RAISE NOTICE '[023] public.licencas_ativacao ausente (migração 021 não aplicada) — pulando.';
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'licencas_ativacao'
          AND column_name = 'machine_id'
    ) THEN
        EXECUTE $sql$
            ALTER TABLE public.licencas_ativacao ADD COLUMN machine_id text
        $sql$;
    END IF;

    EXECUTE $sql$
        COMMENT ON COLUMN public.licencas_ativacao.machine_id IS
          'ID do computador para o qual o código foi emitido (64 hex). NULL = qualquer computador (uso único).'
    $sql$;

    EXECUTE $sql$
        CREATE INDEX IF NOT EXISTS licencas_ativacao_maquina_idx
          ON public.licencas_ativacao (machine_id)
    $sql$;
END
$guard$;

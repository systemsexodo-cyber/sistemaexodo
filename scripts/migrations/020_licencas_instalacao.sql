-- ============================================================
-- 020 — LICENÇA DE INSTALAÇÃO (só NUVEM / Supabase)
-- ============================================================
-- A primeira liberação do sistema instalado (30 dias por computador) e a
-- renovação depois do pagamento da mensalidade.
--
-- Quem lê/grava estas tabelas é apenas a edge function
-- `supabase/functions/licenca-instalacao` (service_role). O app NUNCA acessa:
-- RLS ligado e sem policy.
--
-- Depende do schema auth/roles do Supabase. Num banco LOCAL o bloco inteiro é
-- pulado (RAISE NOTICE), então o arquivo pode rodar nos dois sem erro.
--
-- Idempotente: pode rodar várias vezes.

DO $guard$
BEGIN
    IF to_regclass('auth.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[020] auth/authenticated ausente (banco local) — pulando licencas de instalacao.';
        RETURN;
    END IF;

    EXECUTE $sql$
        CREATE TABLE IF NOT EXISTS public.licencas_instalacao (
            machine_id     text PRIMARY KEY,
            machine_name   text NOT NULL DEFAULT '',
            empresa_id     text,
            license_id     uuid NOT NULL DEFAULT gen_random_uuid(),
            emitida_em     timestamptz NOT NULL DEFAULT now(),
            expira_em      timestamptz NOT NULL,
            renovacoes     integer NOT NULL DEFAULT 0,
            bloqueada      boolean NOT NULL DEFAULT false,
            atualizada_em  timestamptz NOT NULL DEFAULT now()
        );
    $sql$;

    EXECUTE $sql$
        COMMENT ON TABLE public.licencas_instalacao IS
          'Licenca inicial de 30 dias por computador, emitida na instalacao e renovada apos pagamento da mensalidade.';
    $sql$;

    EXECUTE $sql$
        CREATE TABLE IF NOT EXISTS public.licencas_instalacao_historico (
            id          bigserial PRIMARY KEY,
            machine_id  text NOT NULL,
            empresa_id  text,
            acao        text NOT NULL,
            license_id  uuid NOT NULL,
            emitida_em  timestamptz NOT NULL,
            expira_em   timestamptz NOT NULL,
            criado_em   timestamptz NOT NULL DEFAULT now()
        );
    $sql$;

    EXECUTE $sql$
        COMMENT ON TABLE public.licencas_instalacao_historico IS
          'Cada licenca de instalacao emitida (ativacao ou renovacao), para auditoria.';
    $sql$;

    EXECUTE $sql$
        CREATE INDEX IF NOT EXISTS licencas_instalacao_empresa_idx
          ON public.licencas_instalacao (empresa_id);
    $sql$;

    EXECUTE $sql$
        CREATE INDEX IF NOT EXISTS licencas_instalacao_historico_maquina_idx
          ON public.licencas_instalacao_historico (machine_id, criado_em DESC);
    $sql$;

    EXECUTE 'ALTER TABLE public.licencas_instalacao ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.licencas_instalacao_historico ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.licencas_instalacao FROM anon, authenticated';
    EXECUTE 'REVOKE ALL ON TABLE public.licencas_instalacao_historico FROM anon, authenticated';
END
$guard$;

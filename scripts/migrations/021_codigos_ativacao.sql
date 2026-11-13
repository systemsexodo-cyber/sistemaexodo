-- ============================================================
-- 021 — CÓDIGOS DE ATIVAÇÃO POR VENDA (só NUVEM / Supabase)
-- ============================================================
-- Cada venda recebe um código (ex.: EXO-7F2K-9M4Q-8PXR). O setup pede esse
-- código e a função `licenca-instalacao` confere na nuvem. O código:
--
--   - só pode ser usado UMA vez, em UM computador (`usada_por`);
--   - pode estar preso a uma empresa (`empresa_id`) — a licença já nasce
--     vinculada a ela, então a renovação confere a mensalidade certa;
--   - pode ser revogado (`revogado`) ou ter prazo (`expira_em`).
--
-- Assim, copiar o setup para outro PC não libera: falta um código válido.
--
-- O `codigo` é guardado NORMALIZADO (maiúsculo, só A-Z0-9, sem hífens) para a
-- comparação não depender de como o cliente digita.
--
-- Acesso apenas pela edge function (service_role): RLS ligado e sem policy.
-- Guarda de banco local, igual à 020.
--
-- Idempotente: pode rodar várias vezes.

DO $guard$
BEGIN
    IF to_regclass('auth.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[021] auth/authenticated ausente (banco local) — pulando codigos de ativacao.';
        RETURN;
    END IF;

    EXECUTE $sql$
        CREATE TABLE IF NOT EXISTS public.licencas_ativacao (
            codigo      text PRIMARY KEY,
            empresa_id  text,
            observacao  text NOT NULL DEFAULT '',
            revogado    boolean NOT NULL DEFAULT false,
            expira_em   timestamptz,
            usada_por   text,
            usada_em    timestamptz,
            criado_em   timestamptz NOT NULL DEFAULT now()
        );
    $sql$;

    EXECUTE $sql$
        COMMENT ON TABLE public.licencas_ativacao IS
          'Codigo de ativacao por venda: uso unico, em um computador. Emitido por tools/licencas/gerar_codigos_ativacao.js.';
    $sql$;

    EXECUTE $sql$
        CREATE INDEX IF NOT EXISTS licencas_ativacao_empresa_idx
          ON public.licencas_ativacao (empresa_id);
    $sql$;

    EXECUTE 'ALTER TABLE public.licencas_ativacao ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.licencas_ativacao FROM anon, authenticated';
END
$guard$;

-- ============================================================
-- 009 — SESSÃO EXCLUSIVA DE USUÁRIO (só NUVEM / Supabase)
-- ============================================================
-- Bloqueia a mesma conta em mais de um dispositivo ao mesmo tempo.
--
-- Depende de auth.users e dos papéis anon/authenticated, que só existem no
-- Supabase. Num banco LOCAL o bloco inteiro é pulado (RAISE NOTICE), então
-- este arquivo pode rodar nos dois sem erro.
--
-- Idempotente: pode rodar várias vezes.

DO $guard$
BEGIN
    IF to_regclass('auth.users') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        RAISE NOTICE '[009] auth/authenticated ausente (banco local) — pulando sessao exclusiva.';
        RETURN;
    END IF;

    EXECUTE $sql$
        CREATE TABLE IF NOT EXISTS public.user_device_sessions (
            user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
            machine_id text NOT NULL,
            machine_name text NOT NULL DEFAULT '',
            last_seen_at timestamptz NOT NULL DEFAULT now()
        );
    $sql$;

    EXECUTE 'ALTER TABLE public.user_device_sessions ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.user_device_sessions FROM anon, authenticated';

    EXECUTE $sql$
        CREATE OR REPLACE FUNCTION public.claim_user_device_session(
            p_machine_id text,
            p_machine_name text
        )
        RETURNS boolean
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = ''
        AS $body$
        DECLARE
            v_user_id uuid := auth.uid();
            v_claimed boolean;
        BEGIN
            IF v_user_id IS NULL
               OR p_machine_id IS NULL
               OR length(p_machine_id) < 16 THEN
                RETURN false;
            END IF;

            INSERT INTO public.user_device_sessions AS current_session (
                user_id, machine_id, machine_name, last_seen_at
            )
            VALUES (v_user_id, p_machine_id, COALESCE(p_machine_name, ''), now())
            ON CONFLICT (user_id) DO UPDATE
            SET machine_id = EXCLUDED.machine_id,
                machine_name = EXCLUDED.machine_name,
                last_seen_at = now()
            WHERE current_session.machine_id = EXCLUDED.machine_id
               OR current_session.last_seen_at < now() - interval '90 seconds'
            RETURNING true INTO v_claimed;

            RETURN COALESCE(v_claimed, false);
        END;
        $body$;
    $sql$;

    EXECUTE $sql$
        CREATE OR REPLACE FUNCTION public.release_user_device_session(p_machine_id text)
        RETURNS void
        LANGUAGE sql
        SECURITY DEFINER
        SET search_path = ''
        AS $body$
            DELETE FROM public.user_device_sessions
            WHERE user_id = auth.uid()
              AND machine_id = p_machine_id;
        $body$;
    $sql$;

    EXECUTE 'REVOKE ALL ON FUNCTION public.claim_user_device_session(text, text) FROM PUBLIC, anon';
    EXECUTE 'REVOKE ALL ON FUNCTION public.release_user_device_session(text) FROM PUBLIC, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_user_device_session(text, text) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.release_user_device_session(text) TO authenticated';
END
$guard$;

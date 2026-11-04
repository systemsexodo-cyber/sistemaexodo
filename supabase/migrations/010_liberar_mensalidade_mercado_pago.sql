CREATE OR REPLACE FUNCTION public.registrar_pagamento_mensalidade(
    p_empresa_id TEXT,
    p_dados JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.empresas
    SET configuracoes = COALESCE(configuracoes, '{}'::jsonb) || p_dados,
        updated_at = NOW()
    WHERE id = p_empresa_id;

    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_pagamento_mensalidade(TEXT, JSONB)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.registrar_pagamento_mensalidade(TEXT, JSONB)
TO service_role;

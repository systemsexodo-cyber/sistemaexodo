#!/usr/bin/env python3
"""Diagnóstico do perfil tributário na nuvem Supabase (se ainda estiver ativa)."""
from __future__ import annotations

import sys
import urllib.parse
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "tool"))

import psycopg2  # noqa: E402
from migrar_local_para_neon import _parse_env  # noqa: E402


def dsn_supabase() -> str:
    env = _parse_env(RAIZ / ".env")
    host = env.get("SUPABASE_DB_HOST", "").strip()
    if not host:
        raise SystemExit("SUPABASE_DB_HOST ausente")
    return (
        f"postgresql://{urllib.parse.quote(env.get('SUPABASE_DB_USER', 'postgres'), safe='')}:"
        f"{urllib.parse.quote(env.get('SUPABASE_DB_PASSWORD', ''), safe='')}@"
        f"{host}:{env.get('SUPABASE_DB_PORT', '5432')}/{env.get('SUPABASE_DB_NAME', 'postgres')}"
        "?sslmode=require"
    )


def main() -> int:
    conn = psycopg2.connect(dsn_supabase(), connect_timeout=20)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT column_name, data_type, is_nullable, column_default "
                "FROM information_schema.columns "
                "WHERE table_schema='public' AND table_name='produtos' "
                "AND column_name='perfil_tributario_id'"
            )
            print("coluna perfil_tributario_id:", cur.fetchone())
            cur.execute(
                "SELECT count(*) FROM produtos WHERE perfil_tributario_id IS NULL "
                "OR btrim(perfil_tributario_id) = ''"
            )
            print("produtos SEM perfil (null/vazio):", cur.fetchone()[0])
            cur.execute("SELECT count(*) FROM produtos")
            print("produtos no total:", cur.fetchone()[0])
            cur.execute(
                "SELECT COALESCE(NULLIF(btrim(perfil_tributario_id), ''), '<vazio>') "
                "AS perfil, count(*) FROM produtos GROUP BY 1 ORDER BY 2 DESC"
            )
            print("por perfil:")
            for perfil, qtd in cur.fetchall():
                print(f"  {perfil!r}: {qtd}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

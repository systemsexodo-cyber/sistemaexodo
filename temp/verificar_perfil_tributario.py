#!/usr/bin/env python3
"""Diagnóstico: perfil_tributario_id no banco LOCAL e na NUVEM (Neon).

Não imprime credenciais. Somente contagens/colunas.
"""
from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "tool"))

import psycopg2  # noqa: E402
from migrar_local_para_neon import _dsn_local, _dsn_neon  # noqa: E402


def resumo(nome: str, dsn: str) -> None:
    print("=" * 72)
    print(nome)
    conn = psycopg2.connect(dsn, connect_timeout=20)
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

            cur.execute(
                "SELECT id, nome, empresa_id, perfil_tributario_id "
                "FROM produtos WHERE perfil_tributario_id IS NULL "
                "OR btrim(perfil_tributario_id) = '' LIMIT 5"
            )
            amostra = cur.fetchall()
            if amostra:
                print("amostra sem perfil:")
                for linha in amostra:
                    print(" ", linha)
    finally:
        conn.close()


def main() -> int:
    resumo("LOCAL (PostgreSQL)", _dsn_local())
    resumo("NUVEM (Neon)", _dsn_neon())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

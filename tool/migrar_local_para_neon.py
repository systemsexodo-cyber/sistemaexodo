#!/usr/bin/env python3
"""Migra os dados do PostgreSQL LOCAL para o Neon (nuvem principal).

Fecha a migração Supabase -> Neon: o schema do Neon já existe, o que faltava era
levar/atualizar os dados de negócio do banco local. O script NÃO apaga nada na
nuvem: ele faz UPSERT por chave primária (INSERT ... ON CONFLICT DO UPDATE).

Como é rápido: cada tabela é copiada para uma tabela TEMP no Neon com
`COPY` (uma ida) e o merge é feito com UM único INSERT ... SELECT ... ON
CONFLICT. Antes, o envio era linha a linha e cada round-trip até o Neon custava
~100 ms — levar `produtos` sozinho passava de 7 minutos.

Uso:

    python tool/migrar_local_para_neon.py --dry-run     # só lista o plano
    python tool/migrar_local_para_neon.py               # executa
    python tool/migrar_local_para_neon.py --tabelas produtos,nfces

De onde vêm as credenciais (nenhuma senha fica no script):

  * LOCAL : `.env` (DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD) e, se a
            conexão falhar, `assets/app.env` (mesmos nomes).
  * NEON  : `.env.neon` (DATABASE_URL_UNPOOLED ou DATABASE_URL) e, se o
            arquivo não existir, `neon connection-string`.

Tabelas locais de infraestrutura NÃO são copiadas (ver TABELAS_IGNORADAS):
fila de sincronização, status dos PCs e configuração da máquina são de cada
computador, não do banco compartilhado. Linhas cujo `empresa_id` não existe em
`empresas` no Neon são puladas com aviso (as chaves estrangeiras da nuvem não
são desligadas em momento nenhum).
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
import urllib.parse
from datetime import date, datetime
from pathlib import Path

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:  # pragma: no cover - só orienta o operador
    sys.exit("psycopg2 ausente. Rode: pip install psycopg2-binary")

RAIZ = Path(__file__).resolve().parent.parent

# Tabelas que pertencem a UM computador (fila, status, config local) e por isso
# não vão para a nuvem compartilhada.
TABELAS_IGNORADAS = {
    "cache_dados",
    "schema_migrations",
    "bridge_commands",
    "bridge_status",
    "sync_status",
    "exodo_config",
}

# Colunas que existem só de um lado e devem ser puladas na cópia.
COLUNAS_IGNORADAS = {"visto_em"}

MARCA_NULO = r"\N"

TIPOS_NUMERICOS = {"smallint", "integer", "bigint", "numeric", "real", "double precision"}
TIPOS_TEMPO = {"timestamp with time zone", "timestamp without time zone"}
TIPOS_JSON = {"json", "jsonb"}


def _parse_env(caminho: Path) -> dict[str, str]:
    valores: dict[str, str] = {}
    if not caminho.exists():
        return valores
    for linha in caminho.read_text(encoding="utf-8", errors="replace").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        valor = valor.strip()
        if len(valor) >= 2 and valor[0] == valor[-1] and valor[0] in "\"'":
            valor = valor[1:-1]
        valores[chave.strip()] = valor
    return valores


def _dsn_local() -> str:
    """Monta a DSN do banco local tentando `.env` e, se preciso, `assets/app.env`."""
    candidatos = [_parse_env(RAIZ / ".env"), _parse_env(RAIZ / "assets" / "app.env")]
    for env in candidatos:
        host = env.get("DB_HOST")
        if not host:
            continue
        dsn = (
            f"postgresql://{urllib.parse.quote(env.get('DB_USER', ''), safe='')}:"
            f"{urllib.parse.quote(env.get('DB_PASSWORD', ''), safe='')}@"
            f"{host}:{env.get('DB_PORT', '5432')}/{env.get('DB_NAME', 'exodo_db')}"
        )
        try:
            conn = psycopg2.connect(dsn, connect_timeout=5)
            conn.close()
            return dsn
        except psycopg2.Error:
            continue
    raise SystemExit(
        "Não consegui conectar no PostgreSQL local. Confira DB_HOST/DB_USER/"
        "DB_PASSWORD no .env (ou passe --local-dsn)."
    )


def _dsn_neon() -> str:
    env = _parse_env(RAIZ / ".env.neon")
    for chave in ("NEON_DATABASE_URL_UNPOOLED", "DATABASE_URL_UNPOOLED",
                  "NEON_DATABASE_URL", "DATABASE_URL"):
        valor = (env.get(chave) or "").strip()
        if valor:
            return valor
    raise SystemExit(
        "Sem DATABASE_URL no .env.neon. Rode:\n"
        "  neon env pull --file .env.neon"
    )


def _colunas(conn, tabela: str) -> dict[str, str]:
    """{coluna: tipo} do schema public de uma tabela."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name, data_type FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name=%s "
            "ORDER BY ordinal_position",
            (tabela,),
        )
        return {linha[0]: linha[1] for linha in cur.fetchall()}


def _chave_primaria(conn, tabela: str) -> list[str]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT a.attname
            FROM pg_constraint con
            JOIN pg_class c ON c.oid = con.conrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN unnest(con.conkey) k(attnum) ON true
            JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
            WHERE con.contype = 'p' AND n.nspname = 'public' AND c.relname = %s
            ORDER BY array_position(con.conkey, k.attnum)
            """,
            (tabela,),
        )
        return [linha[0] for linha in cur.fetchall()]


def _chaves_estrangeiras(conn, tabela: str) -> list[tuple[list[str], str, list[str]]]:
    """[(colunas_locais, tabela_pai, colunas_pai)] das FKs da tabela na nuvem."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT con.conname,
                   array_agg(a.attname ORDER BY k.ord) AS cols,
                   cl2.relname AS pai,
                   array_agg(a2.attname ORDER BY k.ord) AS cols_pai
            FROM pg_constraint con
            JOIN pg_class c ON c.oid = con.conrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_class cl2 ON cl2.oid = con.confrelid
            JOIN unnest(con.conkey) WITH ORDINALITY k(attnum, ord) ON true
            JOIN unnest(con.confkey) WITH ORDINALITY fk(attnum, ord) ON fk.ord = k.ord
            JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
            JOIN pg_attribute a2 ON a2.attrelid = cl2.oid AND a2.attnum = fk.attnum
            WHERE con.contype = 'f' AND n.nspname = 'public' AND c.relname = %s
            GROUP BY con.conname, cl2.relname
            """,
            (tabela,),
        )
        return [(list(cols), pai, list(cols_pai)) for _, cols, pai, cols_pai in cur.fetchall()]


def _contar(conn, tabela: str) -> int:
    try:
        with conn.cursor() as cur:
            cur.execute(f'SELECT count(*) FROM "{tabela}"')
            return cur.fetchone()[0]
    except psycopg2.Error:
        return -1


def _tabelas_comuns(local, neon, pedidas: list[str] | None) -> list[str]:
    def base(conn):
        with conn.cursor() as cur:
            cur.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema='public' AND table_type='BASE TABLE' "
                "AND LEFT(table_name, 1) <> '_' "
                "AND LEFT(table_name, 3) <> 'vw_' ORDER BY 1"
            )
            return {linha[0] for linha in cur.fetchall()}

    comuns = sorted(base(local) & base(neon) - TABELAS_IGNORADAS)
    if pedidas:
        faltando = [t for t in pedidas if t not in comuns]
        if faltando:
            raise SystemExit(f"Tabela(s) sem par na nuvem: {', '.join(faltando)}")
        comuns = [t for t in comuns if t in set(pedidas)]
    else:
        # As maiores primeiro (o que mais importa sobe cedo), mas `empresas`
        # SEMPRE na frente: as demais tabelas têm FK para ela.
        comuns.sort(key=lambda t: _contar(local, t), reverse=True)
        if "empresas" in comuns:
            comuns.remove("empresas")
            comuns.insert(0, "empresas")
    return comuns


_FORMATOS_DATA = (
    "%Y-%m-%d %H:%M:%S.%f%z",
    "%Y-%m-%d %H:%M:%S%z",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S.%f%z",
    "%Y-%m-%dT%H:%M:%S%z",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%d",
    "%d/%m/%Y %H:%M:%S",
    "%d/%m/%Y",
)

_convertidos_ruins: list[str] = []


def _converter(valor, tipo_alvo: str, contexto: str):
    """Ajusta o valor do banco local para o tipo da coluna no Neon."""
    if valor is None:
        return None
    if isinstance(valor, str) and valor.strip() == "" and tipo_alvo not in ("text",):
        return None
    if tipo_alvo == "text" or tipo_alvo.startswith("character varying"):
        return valor if isinstance(valor, str) else str(valor)
    if tipo_alvo in TIPOS_JSON:
        if isinstance(valor, (dict, list)):
            return json.dumps(valor, ensure_ascii=False)
        texto = str(valor).strip()
        try:
            json.loads(texto)
            return texto
        except (ValueError, TypeError):
            _convertidos_ruins.append(f"{contexto}: JSON inválido ({texto[:40]!r})")
            return None
    if tipo_alvo in TIPOS_TEMPO or tipo_alvo == "date":
        if isinstance(valor, (datetime, date)):
            return valor
        texto = str(valor).strip()
        try:
            return datetime.fromisoformat(texto.replace("Z", "+00:00"))
        except ValueError:
            pass
        for formato in _FORMATOS_DATA:
            try:
                return datetime.strptime(texto, formato)
            except ValueError:
                continue
        _convertidos_ruins.append(f"{contexto}: data inválida ({texto[:40]!r})")
        return None
    if tipo_alvo == "boolean":
        if isinstance(valor, bool):
            return valor
        texto = str(valor).strip().lower()
        if texto in {"true", "t", "1", "sim", "yes"}:
            return True
        if texto in {"false", "f", "0", "nao", "no"}:
            return False
        return None
    if tipo_alvo == "uuid":
        texto = str(valor).strip()
        if re.fullmatch(r"[0-9a-fA-F-]{36}", texto):
            return texto
        _convertidos_ruins.append(f"{contexto}: UUID inválido ({texto[:40]!r})")
        return None
    if tipo_alvo in TIPOS_NUMERICOS:
        if isinstance(valor, (int, float)):
            return valor
        texto = str(valor).strip().replace(" ", "")
        if "," in texto and "." not in texto:
            texto = texto.replace(",", ".")
        try:
            return float(texto) if "." in texto else int(texto)
        except ValueError:
            _convertidos_ruins.append(f"{contexto}: número inválido ({texto[:40]!r})")
            return None
    if tipo_alvo.endswith("[]"):
        if isinstance(valor, (list, tuple)):
            return valor
        texto = str(valor).strip()
        return texto
    # Demais tipos (interval, time, bytea...): passa direto e deixa o Postgres
    # decidir; se recusar, a tabela cai no relatório de falhas.
    return valor


def _texto_copy(valor) -> str:
    """Serializa o valor para o formato CSV aceito pelo COPY."""
    if valor is None:
        return MARCA_NULO
    if isinstance(valor, bool):
        return "true" if valor else "false"
    if isinstance(valor, datetime):
        return valor.isoformat(sep=" ")
    if isinstance(valor, date):
        return valor.isoformat()
    if isinstance(valor, (list, tuple)):
        return "{" + ",".join(
            '"' + str(item).replace('\\', '\\\\').replace('"', '\\"') + '"'
            for item in valor
        ) + "}"
    return str(valor)


def _montar_csv(linhas, colunas, tipos_neon, tabela):
    buffer = io.StringIO()
    escritor = csv.writer(buffer, lineterminator="\n")
    for linha in linhas:
        escritor.writerow([
            _texto_copy(_converter(linha[c], tipos_neon[c], f"{tabela}.{c}"))
            for c in colunas
        ])
    return buffer.getvalue()


def migrar_tabela(local, neon, tabela: str, dry_run: bool) -> tuple[int, int, list[str]]:
    """Devolve (linhas_enviadas, linhas_puladas_por_fk, avisos)."""
    tipos_local = _colunas(local, tabela)
    tipos_neon = _colunas(neon, tabela)
    colunas = [c for c in tipos_local if c in tipos_neon and c not in COLUNAS_IGNORADAS]
    if not colunas:
        return 0, 0, [f"{tabela}: nenhuma coluna em comum"]
    pk = _chave_primaria(neon, tabela)
    if not pk:
        return 0, 0, [f"{tabela}: sem chave primária na nuvem (pulada)"]

    with local.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            f'SELECT {", ".join(chr(34) + c + chr(34) for c in colunas)} FROM "{tabela}"'
        )
        linhas = cur.fetchall()
    if not linhas:
        return 0, 0, []
    if dry_run:
        return len(linhas), 0, []

    avisos: list[str] = []
    lista_colunas = ", ".join(f'"{c}"' for c in colunas)
    atualiza = ", ".join(f'"{c}" = EXCLUDED."{c}"' for c in colunas if c not in pk)
    conflito = ", ".join(f'"{c}"' for c in pk)

    # Filtro de integridade: só entra linha cuja FK aponta para registro que
    # existe na nuvem (o Neon tem as constraints ligadas, o local não).
    def condicao_fk(chave, pai, chave_pai):
        pareamento = " AND ".join(
            f"r.{chr(34)}{cp}{chr(34)} = s.{chr(34)}{cc}{chr(34)}"
            for cc, cp in zip(chave, chave_pai)
        )
        nulos = " AND ".join(f's."{cc}" IS NULL' for cc in chave)
        return (f"({nulos} OR EXISTS (SELECT 1 FROM \"{pai}\" r WHERE {pareamento}))")

    fks = _chaves_estrangeiras(neon, tabela)
    filtro = " AND ".join(condicao_fk(*fk) for fk in fks)

    csv_dados = _montar_csv(linhas, colunas, tipos_neon, tabela)

    enviados = pulados = 0
    try:
        with neon.cursor() as cur:
            cur.execute('CREATE TEMP TABLE _mig_stage AS SELECT * FROM '
                        f'"{tabela}" WITH NO DATA')
            cur.copy_expert(
                f'COPY _mig_stage ({lista_colunas}) FROM STDIN '
                f"WITH (FORMAT csv, NULL '{MARCA_NULO}')",
                io.StringIO(csv_dados),
            )
            cur.execute("SELECT count(*) FROM _mig_stage")
            no_stage = cur.fetchone()[0]
            if filtro:
                cur.execute(f"SELECT count(*) FROM _mig_stage s WHERE NOT ({filtro})")
                pulados = cur.fetchone()[0]
            cur.execute(
                f'INSERT INTO "{tabela}" ({lista_colunas}) '
                f"SELECT {lista_colunas} FROM _mig_stage s "
                + (f"WHERE {filtro} " if filtro else "")
                + f"ON CONFLICT ({conflito}) DO "
                + (f"UPDATE SET {atualiza}" if atualiza else "NOTHING")
            )
            enviados = no_stage - pulados
            cur.execute("DROP TABLE _mig_stage")
        neon.commit()
    except psycopg2.Error as erro:
        neon.rollback()
        primeira = str(erro).strip().splitlines()[0]
        avisos.append(f"{tabela}: FALHOU ({primeira})")
        return 0, 0, avisos

    if pulados:
        avisos.append(
            f"{tabela}: {pulados} linha(s) pulada(s) por chave estrangeira "
            "(registro pai ausente na nuvem)"
        )
    return enviados, pulados, avisos


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="Só mostra quantas linhas seriam enviadas por tabela.")
    parser.add_argument("--tabelas", default="",
                        help="Lista separada por vírgula (padrão: todas as comuns).")
    parser.add_argument("--local-dsn", default="", help="DSN do banco local (opcional).")
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    local_dsn = args.local_dsn or _dsn_local()
    neon_dsn = _dsn_neon()
    pedidas = [t.strip() for t in args.tabelas.split(",") if t.strip()]

    print("=" * 74)
    print("Migração de dados: PostgreSQL local -> Neon")
    print(f"local : {local_dsn.split('@')[-1]}")
    print(f"nuvem : {neon_dsn.split('@')[-1].split('?')[0]}")
    print(f"modo  : {'SIMULAÇÃO (nada é gravado)' if args.dry_run else 'GRAVAÇÃO (upsert)'}")
    print("=" * 74)

    local = psycopg2.connect(local_dsn)
    neon = psycopg2.connect(neon_dsn, connect_timeout=15)
    try:
        tabelas = _tabelas_comuns(local, neon, pedidas or None)
        total = pulados_total = 0
        avisos: list[str] = []
        for tabela in tabelas:
            enviados, pulados, avisos_tabela = migrar_tabela(local, neon, tabela, args.dry_run)
            total += enviados
            pulados_total += pulados
            avisos.extend(avisos_tabela)
            print(f"{tabela:<28} {enviados:>7} linha(s)"
                  + (f"  ({pulados} pulada(s) por FK)" if pulados else "")
                  + ("  <-- ver avisos" if any(a.startswith(tabela) for a in avisos_tabela) else ""))
        print("-" * 74)
        print(f"tabelas: {len(tabelas)} | linhas enviadas: {total} | puladas por FK: {pulados_total}")
        if _convertidos_ruins:
            print(f"valores não convertidos (viraram NULL): {len(_convertidos_ruins)}")
            for aviso in _convertidos_ruins[:10]:
                print(f"  - {aviso}")
        if avisos:
            print(f"avisos: {len(avisos)}")
            for aviso in avisos[:20]:
                print(f"  - {aviso}")
        print("=" * 74)
        return 0 if not any("FALHOU" in a for a in avisos) else 1
    finally:
        local.close()
        neon.close()


if __name__ == "__main__":
    raise SystemExit(main())

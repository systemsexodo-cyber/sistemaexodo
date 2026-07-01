#!/usr/bin/env python3
"""
Script de Migração: Supabase → PostgreSQL local

Busca os dados das tabelas do Supabase via REST API e sincroniza em um
PostgreSQL local apontado pelas variáveis DB_*.

Exemplos:
    python migrar_supabase_postgresql.py --mode append
    python migrar_supabase_postgresql.py --mode replace --table empresas --table clientes
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List

import psycopg2
from dotenv import load_dotenv
from psycopg2 import sql
from psycopg2.extras import execute_values


class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def print_header(text):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.RESET}\n")


def print_ok(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.RESET}")


def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.RESET}")


def print_warning(text):
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.RESET}")


def print_info(text):
    print(f"{Colors.BLUE}ℹ️  {text}{Colors.RESET}")


@dataclass
class TableStats:
    table: str
    rows_migrated: int = 0
    rows_updated: int = 0
    skipped: int = 0
    status: str = 'pendente'
    notes: List[str] = field(default_factory=list)


DEFAULT_TABLES = [
    'empresas',
    'usuarios',
    'clientes',
    'produtos',
    'servicos',
    'pedidos',
    'ordens_servico',
    'entregas',
    'vendas_balcao',
    'trocas_devolucoes',
    'estoque_historico',
    'aberturas_caixa',
    'fechamentos_caixa',
    'motoristas',
    'agendamentos_servico',
    'notas_entrada',
    'funcionarios',
    'taxas_entrega',
    'contas_pagar',
    'nfces',
    'romaneios',
    'sangrias_caixa',
    'suprimentos_caixa',
    'mesas_comandas',
    'links_vendedores',
    'comissoes_vendedores',
    'bridge_status',
]


def parse_args():
    parser = argparse.ArgumentParser(
        description='Migra dados do Supabase para o PostgreSQL local.'
    )
    parser.add_argument(
        '--mode',
        choices=['append', 'replace'],
        default='append',
        help='append = upsert incremental, replace = recriar as tabelas localmente',
    )
    parser.add_argument(
        '--table',
        action='append',
        dest='tables',
        default=None,
        help='Tabela específica do Supabase a migrar (pode repetir)',
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=1000,
        help='Quantidade de linhas por lote',
    )
    parser.add_argument(
        '--sample-size',
        type=int,
        default=100,
        help='Quantidade de linhas usadas para inferir o schema',
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Mostra quais tabelas seriam migradas sem executar',
    )
    return parser.parse_args()


def looks_like_timestamp(value):
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace('Z', '+00:00'))
        return True
    except ValueError:
        return False


def infer_pg_type(column_name, values):
    inferred = []
    for value in values:
        if value is None:
            continue
        if isinstance(value, bool):
            inferred.append('BOOLEAN')
        elif isinstance(value, (int,)) and not isinstance(value, bool):
            inferred.append('BIGINT')
        elif isinstance(value, float):
            inferred.append('NUMERIC')
        elif isinstance(value, (list, dict)):
            inferred.append('JSONB')
        elif isinstance(value, str):
            if looks_like_timestamp(value):
                inferred.append('TIMESTAMP WITH TIME ZONE')
            elif _looks_like_json(value):
                inferred.append('JSONB')
            else:
                inferred.append('TEXT')
        else:
            inferred.append('TEXT')

    if not inferred:
        return 'TEXT'

    if 'JSONB' in inferred:
        return 'JSONB'

    if 'TIMESTAMP WITH TIME ZONE' in inferred:
        return 'TIMESTAMP WITH TIME ZONE'

    if 'NUMERIC' in inferred:
        return 'NUMERIC'

    if 'BIGINT' in inferred:
        return 'BIGINT'

    if 'BOOLEAN' in inferred:
        return 'BOOLEAN'

    return 'TEXT'


def _looks_like_json(value):
    if not isinstance(value, str):
        return False
    stripped = value.strip()
    if not stripped:
        return False
    return (stripped.startswith('{') and stripped.endswith('}')) or (
        stripped.startswith('[') and stripped.endswith(']')
    )


def build_request(url, api_key):
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'apikey': api_key,
    }
    if api_key:
        headers['Authorization'] = f'Bearer {api_key}'
    return urllib.request.Request(url, headers=headers)


def fetch_all_supabase_tables(supabase_url, api_key):
    """Descobre automaticamente todas as tabelas disponíveis no Supabase."""
    # O Supabase expõe o schema OpenAPI em /rest/v1/
    url = f"{supabase_url.rstrip('/')}/rest/v1/"
    request = build_request(url, api_key)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.loads(response.read().decode('utf-8'))
            # O schema OpenAPI lista as tabelas em 'definitions' ou 'paths'
            tables = []
            if 'definitions' in data:
                tables = list(data['definitions'].keys())
            elif 'paths' in data:
                for path in data['paths']:
                    name = path.lstrip('/')
                    if name and '/' not in name:
                        tables.append(name)
            # Remover views de sistema e entradas vazias
            tables = [t for t in tables if t and not t.startswith('_') and '.' not in t]
            return sorted(tables)
    except Exception as exc:
        print_warning(f'Não foi possível descobrir tabelas automaticamente: {exc}')
        return []


def fetch_rows(supabase_url, table_name, api_key, offset, limit):
    url = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}"
    params = urllib.parse.urlencode({
        'select': '*',
        'order': 'id.asc',
        'limit': limit,
        'offset': offset,
    })
    request = build_request(f"{url}?{params}", api_key)

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read().decode('utf-8')
            return json.loads(data)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def infer_schema(rows):
    schema = {}
    for row in rows:
        for key, value in row.items():
            if key not in schema:
                schema[key] = []
            schema[key].append(value)

    inferred = {}
    for column, values in schema.items():
        inferred[column] = infer_pg_type(column, values)

    return inferred


def build_create_table_statement(table_name, inferred_schema):
    columns = []
    for column, pg_type in inferred_schema.items():
        if column == 'id':
            columns.append(f'"{column}" TEXT PRIMARY KEY')
        else:
            columns.append(f'"{column}" {pg_type}')

    return f"CREATE TABLE IF NOT EXISTS \"{table_name}\" (\n    " + ",\n    ".join(columns) + "\n)"


def get_existing_columns(pg_conn, table_name):
    with pg_conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = %s
            ORDER BY ordinal_position
            """,
            (table_name,),
        )
        return {row[0] for row in cursor.fetchall()}


def ensure_table(pg_conn, table_name, inferred_schema, mode):
    if mode == 'replace':
        with pg_conn.cursor() as cursor:
            cursor.execute(sql.SQL('DROP TABLE IF EXISTS {} CASCADE').format(sql.Identifier(table_name)))
        pg_conn.commit()

    existing_columns = get_existing_columns(pg_conn, table_name)
    if not existing_columns:
        create_sql = build_create_table_statement(table_name, inferred_schema)
        with pg_conn.cursor() as cursor:
            cursor.execute(create_sql)
        pg_conn.commit()
        return

    for column, pg_type in inferred_schema.items():
        if column not in existing_columns:
            with pg_conn.cursor() as cursor:
                cursor.execute(
                    sql.SQL('ALTER TABLE {} ADD COLUMN {} {}').format(
                        sql.Identifier(table_name),
                        sql.Identifier(column),
                        sql.SQL(pg_type),
                    )
                )
            pg_conn.commit()


def insert_rows(pg_conn, table_name, column_names, rows, mode):
    if not rows:
        return 0, 0

    if mode == 'replace':
        # Already recreated the table in ensure_table. This path is only used for append.
        pass

    columns_sql = sql.SQL(', ').join([sql.Identifier(col) for col in column_names])
    insert_query = sql.SQL("INSERT INTO {table} ({columns}) VALUES %s").format(
        table=sql.Identifier(table_name),
        columns=columns_sql,
    )

    if 'id' in column_names:
        update_assignments = sql.SQL(', ').join(
            [
                sql.SQL("{col} = EXCLUDED.{col}").format(col=sql.Identifier(col))
                for col in column_names
                if col != 'id'
            ]
        )
        upsert_query = sql.SQL("{base} ON CONFLICT (id) DO UPDATE SET {updates}").format(
            base=insert_query,
            updates=update_assignments,
        )
        query = upsert_query
    else:
        query = insert_query

    count = 0
    try:
        with pg_conn.cursor() as cursor:
            execute_values(cursor, query.as_string(cursor), rows)
        pg_conn.commit()
        count = len(rows)
    except Exception:
        pg_conn.rollback()
        raise

    return count, 0


def migrate_table(pg_conn, table_name, api_key, supabase_url, batch_size, sample_size, mode):
    stats = TableStats(table=table_name)

    # Pular views (não são migráveis como tabela)
    if table_name.startswith('vw_') or table_name.startswith('view_'):
        stats.status = 'ignorando'
        stats.notes.append('View ignorada - não é uma tabela de dados')
        return stats

    sample_rows = fetch_rows(supabase_url, table_name, api_key, 0, sample_size)
    if sample_rows is None:
        stats.status = 'ignorando'
        stats.notes.append('Tabela não encontrada ou sem acesso')
        return stats

    if not isinstance(sample_rows, list):
        sample_rows = [sample_rows]

    if not sample_rows:
        stats.status = 'vazia'
        return stats

    inferred_schema = infer_schema(sample_rows)
    ensure_table(pg_conn, table_name, inferred_schema, mode)

    from psycopg2.extras import Json
    import json as _json

    def serialize_val(val, col_name, inferred_schema):
        col_type = inferred_schema.get(col_name, 'TEXT')
        if val is None:
            return None
        # Tratar timestamps numéricos (milissegundos Unix)
        if col_type == 'TIMESTAMP WITH TIME ZONE' and isinstance(val, (int, float)):
            from datetime import datetime, timezone
            try:
                return datetime.fromtimestamp(val / 1000, tz=timezone.utc).isoformat()
            except Exception:
                return None
        if col_type == 'TIMESTAMP WITH TIME ZONE' and isinstance(val, str):
            # Verifica se é um número disfarado de string
            try:
                ms = int(val)
                from datetime import datetime, timezone
                return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat()
            except (ValueError, OSError):
                pass
        # Tratar campos JSONB
        if col_type == 'JSONB':
            if isinstance(val, (dict, list)):
                return Json(val)
            if isinstance(val, str):
                try:
                    _json.loads(val)  # valida se é JSON válido
                    return val
                except (_json.JSONDecodeError, ValueError):
                    # String inválida como JSON: salva como string JSON
                    return Json(val)
            if isinstance(val, (int, float, bool)):
                return Json(val)
        return val

    sample_rows = [row for row in sample_rows if row is not None]
    column_names = list(sample_rows[0].keys())
    initial_count, _ = insert_rows(pg_conn, table_name, column_names, [tuple(serialize_val(row.get(col), col, inferred_schema) for col in column_names) for row in sample_rows], mode)
    stats.rows_migrated += initial_count

    offset = sample_size
    while True:
        batch = fetch_rows(supabase_url, table_name, api_key, offset, batch_size)
        if batch is None:
            break
        if not isinstance(batch, list):
            batch = [batch]
        if not batch:
            break

        batch_rows = [row for row in batch if row is not None]
        if not batch_rows:
            break

        if list(batch_rows[0].keys()) != column_names:
            # Atualiza o schema se novas colunas chegarem no meio da migração
            refreshed_schema = infer_schema(batch_rows + sample_rows)
            ensure_table(pg_conn, table_name, refreshed_schema, mode)
            column_names = list(refreshed_schema.keys())

        values = [tuple(serialize_val(row.get(col), col, inferred_schema) for col in column_names) for row in batch_rows]
        inserted_count, _ = insert_rows(pg_conn, table_name, column_names, values, mode)
        stats.rows_migrated += inserted_count
        offset += batch_size

        if len(batch_rows) < batch_size:
            break

    stats.status = 'ok'
    return stats


def main():
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════════╗")
    print("║              SUPABASE → POSTGRESQL LOCAL                         ║")
    print("║           Exodo System - 28 de Maio de 2026                      ║")
    print("╚════════════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)

    load_dotenv()

    args = parse_args()

    supabase_url = os.getenv('SUPABASE_URL')
    service_role_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')
    anon_key = os.getenv('SUPABASE_ANON_KEY')
    api_key = service_role_key or anon_key

    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')

    if not all([supabase_url, api_key]):
        print_error('Configuração do Supabase incompleta')
        print_warning('Defina SUPABASE_URL e pelo menos SUPABASE_SERVICE_ROLE_KEY ou SUPABASE_ANON_KEY.')
        return 1

    if not all([db_name, db_user, db_password]):
        print_error('Variáveis PostgreSQL não configuradas!')
        print_warning('Configure no arquivo .env: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD')
        return 1

    if args.tables:
        tables_to_process = args.tables
    else:
        print_info('Descobrindo tabelas automaticamente no Supabase...')
        tables_to_process = fetch_all_supabase_tables(supabase_url, api_key)
        if tables_to_process:
            print_ok(f'Encontradas {len(tables_to_process)} tabelas no Supabase: {", ".join(tables_to_process)}')
        else:
            print_warning('Não foi possível listar tabelas automaticamente, usando lista padrão.')
            tables_to_process = DEFAULT_TABLES

    if args.dry_run:
        print_info('Execução em modo dry-run. Tabelas que seriam migradas:')
        for table in tables_to_process:
            print(f'  - {table}')
        return 0

    print_ok(f'Supabase configurado: {supabase_url}')
    print_ok(f'PostgreSQL configurado: {db_user}@{db_host}:{db_port}/{db_name}')
    print_ok(f'Modo de sincronização: {args.mode}')
    print_ok(f'Total de tabelas para migrar: {len(tables_to_process)}')


    print_header('1️⃣  CONECTANDO AO POSTGRESQL LOCAL')
    try:
        pg_conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=10,
        )
        print_ok('Conectado ao PostgreSQL local com sucesso')
    except Exception as exc:
        print_error(f'Erro ao conectar ao PostgreSQL: {exc}')
        return 1

    print_header('2️⃣  MIGRANDO DADOS')
    stats = []
    for table_name in tables_to_process:
        print_info(f'Migrando tabela: {table_name}')
        try:
            result = migrate_table(
                pg_conn,
                table_name,
                api_key,
                supabase_url,
                args.batch_size,
                args.sample_size,
                args.mode,
            )
            stats.append(result)
            if result.status == 'ok':
                print_ok(f"{table_name}: {result.rows_migrated} registros sincronizados")
            elif result.status == 'vazia':
                print_warning(f"{table_name}: sem registros retornados")
            else:
                print_warning(f"{table_name}: {result.status}")
        except Exception as exc:
            print_error(f'Erro ao migrar {table_name}: {exc}')
            stats.append(TableStats(table=table_name, status='erro', notes=[str(exc)]))

    pg_conn.close()

    print_header('3️⃣  RESUMO FINAL')
    total_rows = sum(item.rows_migrated for item in stats)
    ok_tables = sum(1 for item in stats if item.status == 'ok')
    print(f"Tabelas processadas: {len(stats)}")
    print(f"Tabelas sincronizadas: {ok_tables}")
    print(f"Registros sincronizados: {total_rows}")

    print(f"\n{Colors.BOLD}{Colors.BLUE}Checklist de uso:{Colors.RESET}")
    print("  1. Verifique o PostgreSQL local com test_postgres_connection.py")
    print("  2. Para um banco compartilhado entre máquinas, ajuste DB_HOST para o host do PostgreSQL compartilhado")
    print("  3. Reexecute o script para atualizar o espelho local a partir do Supabase")

    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""
Script melhorado de Migração: Supabase → PostgreSQL local
Com melhor diagnostico e tratamento de erros
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from typing import Dict, List, Optional

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


def fetch_rows_v2(supabase_url, table_name, api_key, offset=0, limit=1000):
    """Versão melhorada de fetch_rows com melhor tratamento de erros"""
    table_escaped = urllib.parse.quote(table_name, safe='')
    url = f"{supabase_url.rstrip('/')}/rest/v1/{table_escaped}"
    
    params = urllib.parse.urlencode({
        'select': '*',
        'order': 'id.asc',
        'limit': limit,
        'offset': offset,
    })
    
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'apikey': api_key,
        'Authorization': f'Bearer {api_key}'
    }
    
    request = urllib.request.Request(f"{url}?{params}", headers=headers)
    
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read().decode('utf-8')
            result = json.loads(data)
            return result if isinstance(result, list) else [result]
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        elif exc.code == 401:
            print_error(f"Erro de autenticação (401) para tabela {table_name}")
            print_warning("Verifique suas credenciais do Supabase")
            return None
        elif exc.code == 403:
            print_warning(f"Acesso proibido (403) para tabela {table_name}")
            print_warning("Pode ser um problema de RLS (Row Level Security)")
            return None
        else:
            raise
    except Exception as e:
        print_error(f"Erro ao buscar {table_name}: {e}")
        return None


def infer_pg_type(column_name, values):
    """Inferir tipo PostgreSQL a partir dos valores"""
    inferred = []
    
    for value in values:
        if value is None:
            continue
        
        if isinstance(value, bool):
            inferred.append('BOOLEAN')
        elif isinstance(value, int) and not isinstance(value, bool):
            inferred.append('BIGINT')
        elif isinstance(value, float):
            inferred.append('NUMERIC')
        elif isinstance(value, (list, dict)):
            inferred.append('JSONB')
        elif isinstance(value, str):
            if _looks_like_timestamp(value):
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


def _looks_like_timestamp(value):
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace('Z', '+00:00'))
        return True
    except ValueError:
        return False


def _looks_like_json(value):
    if not isinstance(value, str):
        return False
    stripped = value.strip()
    if not stripped:
        return False
    return (stripped.startswith('{') and stripped.endswith('}')) or (
        stripped.startswith('[') and stripped.endswith(']')
    )


def build_create_table_statement(table_name, inferred_schema):
    """Criar declaração CREATE TABLE"""
    columns = []
    for column, pg_type in inferred_schema.items():
        if column == 'id':
            columns.append(f'"{column}" TEXT PRIMARY KEY')
        else:
            columns.append(f'"{column}" {pg_type}')
    
    return f"CREATE TABLE IF NOT EXISTS \"{table_name}\" (\n    " + ",\n    ".join(columns) + "\n)"


def ensure_table(pg_conn, table_name, inferred_schema):
    """Garantir que a tabela existe no PostgreSQL"""
    with pg_conn.cursor() as cursor:
        # Obter colunas existentes
        cursor.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            ORDER BY ordinal_position
            """,
            (table_name,),
        )
        existing_columns = {row[0] for row in cursor.fetchall()}
    
    if not existing_columns:
        # Tabela não existe - criar
        create_sql = build_create_table_statement(table_name, inferred_schema)
        with pg_conn.cursor() as cursor:
            cursor.execute(create_sql)
        pg_conn.commit()
        return True
    
    # Tabela existe - adicionar colunas faltantes
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
    
    return False


def insert_rows(pg_conn, table_name, column_names, rows):
    """Inserir ou atualizar registros com UPSERT"""
    if not rows:
        return 0
    
    columns_sql = sql.SQL(', ').join([sql.Identifier(col) for col in column_names])
    
    insert_query = sql.SQL("INSERT INTO {table} ({columns}) VALUES %s").format(
        table=sql.Identifier(table_name),
        columns=columns_sql,
    )
    
    # Criar UPSERT query se houver coluna 'id'
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
    
    try:
        with pg_conn.cursor() as cursor:
            execute_values(cursor, query.as_string(cursor), rows)
        pg_conn.commit()
        return len(rows)
    except Exception as e:
        pg_conn.rollback()
        print_error(f"Erro ao inserir linhas em {table_name}: {e}")
        raise


def migrate_table(pg_conn, table_name, api_key, supabase_url, batch_size=1000):
    """Migrar uma tabela específica"""
    
    # Buscar primeira amostra
    sample_rows = fetch_rows_v2(supabase_url, table_name, api_key, 0, batch_size)
    
    if sample_rows is None:
        print_warning(f"{table_name}: não encontrada ou sem acesso")
        return 0
    
    if not sample_rows:
        print_warning(f"{table_name}: vazia")
        return 0
    
    # Inferir schema
    inferred_schema = {}
    for row in sample_rows:
        for key, value in row.items():
            if key not in inferred_schema:
                inferred_schema[key] = []
            inferred_schema[key].append(value)
    
    # Converter para tipos PostgreSQL
    for column, values in inferred_schema.items():
        inferred_schema[column] = infer_pg_type(column, values)
    
    # Criar tabela
    ensure_table(pg_conn, table_name, inferred_schema)
    
    # Preparar dados para inserção
    column_names = list(sample_rows[0].keys())
    rows = [tuple(row.get(col) for col in column_names) for row in sample_rows]
    
    # Inserir primeira amostra
    count = insert_rows(pg_conn, table_name, column_names, rows)
    
    # Buscar e inserir os demais registros em lotes
    offset = batch_size
    while True:
        batch = fetch_rows_v2(supabase_url, table_name, api_key, offset, batch_size)
        
        if batch is None or not batch:
            break
        
        rows = [tuple(row.get(col) for col in column_names) for row in batch]
        batch_count = insert_rows(pg_conn, table_name, column_names, rows)
        count += batch_count
        
        if len(batch) < batch_size:
            break
        
        offset += batch_size
    
    return count


def main():
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════════╗")
    print("║        SUPABASE → POSTGRESQL LOCAL (VERSÃO MELHORADA)            ║")
    print("║              Exodo System - 30 de Maio de 2026                   ║")
    print("╚════════════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)
    
    load_dotenv()
    
    supabase_url = os.getenv('SUPABASE_URL')
    api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
    
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    
    if not all([supabase_url, api_key]):
        print_error('Configuração do Supabase incompleta')
        return 1
    
    if not all([db_name, db_user, db_password]):
        print_error('Variáveis PostgreSQL não configuradas!')
        return 1
    
    print_ok(f'Supabase: {supabase_url}')
    print_ok(f'PostgreSQL: {db_user}@{db_host}:{db_port}/{db_name}')
    
    print_header('1️⃣  CONECTANDO AO POSTGRESQL')
    
    try:
        pg_conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=10,
        )
        print_ok('Conectado ao PostgreSQL')
    except Exception as e:
        print_error(f'Erro ao conectar: {e}')
        return 1
    
    print_header('2️⃣  MIGRANDO DADOS DO SUPABASE')
    
    total_migrated = 0
    successful_tables = 0
    
    for table_name in DEFAULT_TABLES:
        print_info(f'Migrando: {table_name}')
        try:
            count = migrate_table(pg_conn, table_name, api_key, supabase_url)
            if count > 0:
                print_ok(f"{table_name}: {count} registros")
                total_migrated += count
                successful_tables += 1
        except Exception as e:
            print_error(f'Erro ao migrar {table_name}: {e}')
    
    pg_conn.close()
    
    print_header('3️⃣  RESUMO FINAL')
    print(f"Tabelas migradas com sucesso: {successful_tables}")
    print(f"Total de registros sincronizados: {total_migrated}")
    
    if total_migrated > 0:
        print_ok("Migração completada com sucesso!")
    else:
        print_warning("Nenhum dado foi migrado. Verifique as credenciais.")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime

# Fix encoding
os.environ['PYTHONIOENCODING'] = 'utf-8'

try:
    import psycopg2
    from psycopg2 import sql
    from psycopg2.extras import execute_values
    from dotenv import load_dotenv
except ImportError as e:
    print(f"Erro: {e}")
    sys.exit(1)

load_dotenv()

# Configuration
SUPABASE_URL = os.getenv('SUPABASE_URL', '').strip()
SUPABASE_KEY = os.getenv('SUPABASE_ANON_KEY', '').strip() or os.getenv('SUPABASE_SERVICE_ROLE_KEY', '').strip()
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = int(os.getenv('DB_PORT', '5432'))
DB_NAME = os.getenv('DB_NAME', 'exodo_db')
DB_USER = os.getenv('DB_USER', 'exodo_user')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'senha123')

TABLES = [
    'empresas', 'usuarios', 'clientes', 'produtos', 'servicos',
    'pedidos', 'ordens_servico', 'entregas', 'vendas_balcao',
    'trocas_devolucoes', 'estoque_historico', 'aberturas_caixa',
    'fechamentos_caixa', 'motoristas', 'agendamentos_servico',
    'notas_entrada', 'funcionarios', 'taxas_entrega', 'contas_pagar',
    'nfces', 'romaneios', 'sangrias_caixa', 'suprimentos_caixa',
    'mesas_comandas', 'links_vendedores', 'comissoes_vendedores',
    'bridge_status'
]

def fetch_from_supabase(table_name, offset=0, limit=1000):
    """Fetch data from Supabase REST API"""
    try:
        url = f"{SUPABASE_URL.rstrip('/')}/rest/v1/{table_name}"
        params = urllib.parse.urlencode({
            'select': '*',
            'order': 'id.asc',
            'limit': limit,
            'offset': offset
        })
        
        headers = {
            'Accept': 'application/json',
            'apikey': SUPABASE_KEY,
            'Authorization': f'Bearer {SUPABASE_KEY}'
        }
        
        req = urllib.request.Request(f"{url}?{params}", headers=headers)
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    except Exception as e:
        print(f"Erro ao buscar {table_name}: {e}")
        return None

def infer_type(value):
    """Infer PostgreSQL type from Python value"""
    if value is None:
        return 'TEXT'
    if isinstance(value, bool):
        return 'BOOLEAN'
    if isinstance(value, int):
        return 'BIGINT'
    if isinstance(value, float):
        return 'NUMERIC'
    if isinstance(value, (dict, list)):
        return 'JSONB'
    if isinstance(value, str):
        if 'T' in value and ('Z' in value or '+' in value or '-' in value[-6:]):
            return 'TIMESTAMP WITH TIME ZONE'
    return 'TEXT'

def sync_table(conn, table_name, rows):
    """Insert/upsert rows into PostgreSQL"""
    if not rows:
        return 0
    
    cursor = conn.cursor()
    columns = list(rows[0].keys())
    
    # Build INSERT with ON CONFLICT DO UPDATE
    col_list = sql.SQL(', ').join([sql.Identifier(c) for c in columns])
    placeholders = sql.SQL(', ').join([sql.Placeholder()] * len(columns))
    
    if 'id' in columns:
        updates = sql.SQL(', ').join([
            sql.SQL(f'"{c}" = EXCLUDED."{c}"')
            for c in columns if c != 'id'
        ])
        query = sql.SQL(f"""
            INSERT INTO "{table_name}" ({col_list.as_string(cursor)})
            VALUES ({placeholders.as_string(cursor)})
            ON CONFLICT (id) DO UPDATE SET {updates.as_string(cursor)}
        """)
    else:
        query = sql.SQL(f"""
            INSERT INTO "{table_name}" ({col_list.as_string(cursor)})
            VALUES ({placeholders.as_string(cursor)})
        """)
    
    data = [tuple(row.get(c) for c in columns) for row in rows]
    
    try:
        execute_values(cursor, query.as_string(cursor), data)
        conn.commit()
        count = len(rows)
        cursor.close()
        return count
    except Exception as e:
        conn.rollback()
        cursor.close()
        print(f"  Erro ao inserir: {e}")
        return 0

def create_table(conn, table_name, sample_rows):
    """Create table based on sample data"""
    cursor = conn.cursor()
    columns = {}
    
    for row in sample_rows:
        for key, value in row.items():
            if key not in columns:
                columns[key] = infer_type(value)
    
    col_defs = []
    for col, col_type in columns.items():
        if col == 'id':
            col_defs.append(f'"{col}" TEXT PRIMARY KEY')
        else:
            col_defs.append(f'"{col}" {col_type}')
    
    create_sql = f'CREATE TABLE IF NOT EXISTS "{table_name}" (\n    ' + ',\n    '.join(col_defs) + '\n)'
    
    try:
        cursor.execute(create_sql)
        conn.commit()
        cursor.close()
        return True
    except Exception as e:
        print(f"  Erro ao criar tabela: {e}")
        cursor.close()
        return False

def main():
    print("\n" + "="*70)
    print("MIGRACAO: SUPABASE -> POSTGRESQL LOCAL")
    print("="*70 + "\n")
    
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("ERRO: Configuracao do Supabase incompleta!")
        print("Configure SUPABASE_URL e SUPABASE_ANON_KEY no .env")
        return 1
    
    print(f"[1] Conectando ao PostgreSQL: {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME}")
    
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=10
        )
        print("[OK] Conectado\n")
    except Exception as e:
        print(f"[ERRO] {e}")
        return 1
    
    total_rows = 0
    success_tables = 0
    
    for table_name in TABLES:
        print(f"[{table_name}]", end=" ", flush=True)
        
        # Fetch sample
        sample = fetch_from_supabase(table_name, 0, 100)
        if sample is None:
            print("NAO ENCONTRADA")
            continue
        
        if not sample:
            print("VAZIA")
            continue
        
        if not isinstance(sample, list):
            sample = [sample]
        
        # Create table
        if not create_table(conn, table_name, sample):
            print("ERRO AO CRIAR")
            continue
        
        # Sync sample
        count = sync_table(conn, table_name, sample)
        rows_synced = count
        offset = len(sample)
        
        # Fetch remaining
        while True:
            batch = fetch_from_supabase(table_name, offset, 500)
            if not batch or not isinstance(batch, list) or len(batch) == 0:
                break
            
            count = sync_table(conn, table_name, batch)
            if count == 0:
                break
            
            rows_synced += count
            offset += len(batch)
            
            if len(batch) < 500:
                break
        
        print(f"OK ({rows_synced} linhas)")
        total_rows += rows_synced
        success_tables += 1
    
    conn.close()
    
    print("\n" + "="*70)
    print(f"RESULTADO: {success_tables} tabelas sincronizadas, {total_rows} registros")
    print("="*70 + "\n")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())

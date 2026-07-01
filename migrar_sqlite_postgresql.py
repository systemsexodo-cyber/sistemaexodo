#!/usr/bin/env python3
"""
Script de Migração: SQLite → PostgreSQL

Migra todas as tabelas, índices e dados do SQLite para PostgreSQL
Arquivo SQLite esperado: %USERPROFILE%\Documents\exodo_local.db
"""

import os
import sqlite3
import psycopg2
from psycopg2 import sql
from dotenv import load_dotenv
import sys
from pathlib import Path
from datetime import datetime

# Cores para output
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

def get_sqlite_path():
    """Encontrar arquivo SQLite"""
    # Procurar em Documents
    documents = Path.home() / "Documents"
    sqlite_file = documents / "exodo_local.db"
    
    if sqlite_file.exists():
        return str(sqlite_file)
    
    # Procurar em diretório local
    if Path("exodo_local.db").exists():
        return "exodo_local.db"
    
    return None

def get_sqlite_tables(sqlite_path):
    """Listar todas as tabelas do SQLite"""
    try:
        conn = sqlite3.connect(sqlite_path)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='table' 
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """)
        tables = [row[0] for row in cursor.fetchall()]
        conn.close()
        return tables
    except Exception as e:
        print_error(f"Erro ao ler tabelas SQLite: {e}")
        return []

def get_table_schema(sqlite_conn, table_name):
    """Obter schema de uma tabela SQLite"""
    cursor = sqlite_conn.cursor()
    cursor.execute(f"PRAGMA table_info({table_name})")
    columns = cursor.fetchall()
    return columns

def sqlite_type_to_postgres(sqlite_type):
    """Converter tipo SQLite para PostgreSQL"""
    sqlite_type = sqlite_type.upper()
    
    mapping = {
        'INTEGER': 'INTEGER',
        'INT': 'INTEGER',
        'REAL': 'REAL',
        'FLOAT': 'REAL',
        'DOUBLE': 'DOUBLE PRECISION',
        'TEXT': 'TEXT',
        'VARCHAR': 'VARCHAR',
        'CHAR': 'CHAR',
        'BLOB': 'BYTEA',
        'BOOLEAN': 'BOOLEAN',
        'BOOL': 'BOOLEAN',
        'TIMESTAMP': 'TIMESTAMP',
        'DATETIME': 'TIMESTAMP',
        'DATE': 'DATE',
        'TIME': 'TIME',
        'NUMERIC': 'NUMERIC',
        'DECIMAL': 'NUMERIC',
    }
    
    for sqlite_t, pg_t in mapping.items():
        if sqlite_t in sqlite_type:
            return pg_t
    
    return 'TEXT'  # Padrão

def create_table_in_postgres(pg_conn, table_name, columns):
    """Criar tabela no PostgreSQL"""
    cursor = pg_conn.cursor()
    
    column_defs = []
    for col in columns:
        col_name = col[1]
        col_type = col[2]
        col_notnull = col[3]
        col_default = col[4]
        col_pk = col[5]
        
        # Converter tipo
        pg_type = sqlite_type_to_postgres(col_type)
        
        # Construir definição
        col_def = f"{col_name} {pg_type}"
        
        # Adicionar constraint PRIMARY KEY
        if col_pk:
            col_def += " PRIMARY KEY"
        
        # Adicionar NOT NULL
        if col_notnull:
            col_def += " NOT NULL"
        
        # Adicionar DEFAULT
        if col_default:
            col_def += f" DEFAULT {col_default}"
        
        column_defs.append(col_def)
    
    create_sql = f"CREATE TABLE IF NOT EXISTS {table_name} ({', '.join(column_defs)})"
    
    try:
        cursor.execute(create_sql)
        pg_conn.commit()
        print_ok(f"Tabela '{table_name}' criada no PostgreSQL")
        return True
    except Exception as e:
        pg_conn.rollback()
        print_error(f"Erro ao criar tabela '{table_name}': {e}")
        return False
    finally:
        cursor.close()

def migrate_data(sqlite_path, pg_conn, table_name):
    """Migrar dados de uma tabela"""
    sqlite_conn = sqlite3.connect(sqlite_path)
    sqlite_conn.row_factory = sqlite3.Row
    sqlite_cursor = sqlite_conn.cursor()
    
    try:
        # Ler dados do SQLite
        sqlite_cursor.execute(f"SELECT * FROM {table_name}")
        rows = sqlite_cursor.fetchall()
        
        if not rows:
            print_info(f"Tabela '{table_name}' vazia (0 registros)")
            sqlite_conn.close()
            return 0
        
        # Inserir dados no PostgreSQL
        pg_cursor = pg_conn.cursor()
        columns = [description[0] for description in sqlite_cursor.description]
        
        inserted_count = 0
        for row in rows:
            values = tuple(row)
            placeholders = ','.join(['%s'] * len(columns))
            insert_sql = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
            
            try:
                pg_cursor.execute(insert_sql, values)
                inserted_count += 1
            except Exception as e:
                print_warning(f"Erro ao inserir linha: {e}")
        
        pg_conn.commit()
        print_ok(f"Tabela '{table_name}': {inserted_count} registros migrados")
        
        pg_cursor.close()
        sqlite_conn.close()
        return inserted_count
        
    except Exception as e:
        pg_conn.rollback()
        print_error(f"Erro ao migrar dados de '{table_name}': {e}")
        sqlite_conn.close()
        return 0

def main():
    """Função principal"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════════╗")
    print("║              MIGRAÇÃO SQLITE → POSTGRESQL                          ║")
    print("║           Exodo System - 26 de Maio de 2026                       ║")
    print("╚════════════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)
    
    # Carregar ambiente
    load_dotenv()
    
    # ======== VERIFICAÇÃO DE AMBIENTE ========
    print_header("1️⃣  VERIFICAÇÃO DE AMBIENTE")
    
    # Verificar SQLite
    sqlite_path = get_sqlite_path()
    if not sqlite_path:
        print_error("Arquivo exodo_local.db não encontrado!")
        print_warning("Procurado em:")
        print(f"  • {Path.home() / 'Documents' / 'exodo_local.db'}")
        print(f"  • exodo_local.db (diretório atual)")
        return 1
    
    print_ok(f"SQLite encontrado: {sqlite_path}")
    
    # Verificar PostgreSQL
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    
    if not all([db_name, db_user, db_password]):
        print_error("Variáveis PostgreSQL não configuradas!")
        print_warning("Configure no arquivo .env:")
        print("  DB_HOST=localhost")
        print("  DB_PORT=5432")
        print("  DB_NAME=exodo_db")
        print("  DB_USER=exodo_user")
        print("  DB_PASSWORD=sua_senha")
        return 1
    
    print_ok(f"PostgreSQL configurado: {db_user}@{db_host}:{db_port}/{db_name}")
    
    # ======== CONECTAR AO POSTGRESQL ========
    print_header("2️⃣  CONECTANDO AO POSTGRESQL")
    
    try:
        pg_conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=5
        )
        print_ok("Conectado ao PostgreSQL com sucesso!")
    except Exception as e:
        print_error(f"Erro ao conectar: {e}")
        return 1
    
    # ======== LISTAR TABELAS ========
    print_header("3️⃣  TABELAS ENCONTRADAS NO SQLITE")
    
    tables = get_sqlite_tables(sqlite_path)
    if not tables:
        print_warning("Nenhuma tabela encontrada!")
        return 1
    
    print(f"Total de tabelas: {len(tables)}\n")
    for i, table in enumerate(tables, 1):
        print(f"  {i}. {table}")
    
    # ======== MIGRAR TABELAS ========
    print_header("4️⃣  MIGRANDO TABELAS")
    
    sqlite_conn = sqlite3.connect(sqlite_path)
    migration_stats = {
        'tables_created': 0,
        'tables_failed': 0,
        'total_records': 0
    }
    
    for table_name in tables:
        print_info(f"Migrando tabela: {table_name}")
        
        # Obter schema
        columns = get_table_schema(sqlite_conn, table_name)
        
        # Criar tabela
        if create_table_in_postgres(pg_conn, table_name, columns):
            migration_stats['tables_created'] += 1
            
            # Migrar dados
            record_count = migrate_data(sqlite_path, pg_conn, table_name)
            migration_stats['total_records'] += record_count
        else:
            migration_stats['tables_failed'] += 1
    
    sqlite_conn.close()
    pg_conn.close()
    
    # ======== RESUMO ========
    print_header("📊 RESUMO DA MIGRAÇÃO")
    
    print(f"Tabelas criadas:    {Colors.GREEN}{migration_stats['tables_created']}{Colors.RESET}")
    print(f"Tabelas falhadas:   {Colors.RED}{migration_stats['tables_failed']}{Colors.RESET}")
    print(f"Registros migrados: {Colors.GREEN}{migration_stats['total_records']}{Colors.RESET}")
    
    print(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}")
    
    if migration_stats['tables_failed'] == 0:
        print(f"\n{Colors.GREEN}{Colors.BOLD}✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!{Colors.RESET}")
        print(f"\n{Colors.GREEN}Próximos passos:{Colors.RESET}")
        print("  1. Verificar dados no PostgreSQL")
        print("  2. Atualizar código para usar PostgreSQL")
        print("  3. Testar aplicação")
        print("  4. Fazer backup do exodo_local.db (opcional)")
        return 0
    else:
        print(f"\n{Colors.RED}{Colors.BOLD}❌ MIGRAÇÃO CONCLUÍDA COM ERROS{Colors.RESET}")
        print(f"\n{Colors.YELLOW}Verifique os erros acima e tente novamente{Colors.RESET}")
        return 1

if __name__ == '__main__':
    sys.exit(main())

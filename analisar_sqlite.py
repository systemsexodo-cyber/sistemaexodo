#!/usr/bin/env python3
"""
Script de Análise do SQLite

Analisa o banco de dados SQLite e exibe informações detalhadas
sobre tabelas, colunas, tipos de dados e volume de registros
"""

import os
import sqlite3
from pathlib import Path
from datetime import datetime
import sys

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
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
    documents = Path.home() / "Documents"
    sqlite_file = documents / "exodo_local.db"
    
    if sqlite_file.exists():
        return str(sqlite_file)
    
    if Path("exodo_local.db").exists():
        return "exodo_local.db"
    
    return None

def analyze_sqlite(sqlite_path):
    """Análise completa do SQLite"""
    
    try:
        conn = sqlite3.connect(sqlite_path)
        cursor = conn.cursor()
        
        # Informações do arquivo
        file_size = os.path.getsize(sqlite_path)
        file_size_mb = file_size / (1024 * 1024)
        
        print_header("📁 INFORMAÇÕES DO ARQUIVO")
        print(f"Caminho:  {sqlite_path}")
        print(f"Tamanho:  {file_size_mb:.2f} MB ({file_size:,} bytes)")
        print(f"Leitura:  {datetime.fromtimestamp(os.path.getmtime(sqlite_path)).strftime('%d/%m/%Y %H:%M:%S')}")
        
        # Verificação de integridade
        print_header("🔍 VERIFICAÇÃO DE INTEGRIDADE")
        try:
            cursor.execute("PRAGMA integrity_check")
            result = cursor.fetchone()[0]
            if result == 'ok':
                print_ok("Banco de dados íntegro")
            else:
                print_warning(f"Possível problema: {result}")
        except Exception as e:
            print_error(f"Erro ao verificar: {e}")
        
        # Listar tabelas
        print_header("📊 TABELAS")
        cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='table' 
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """)
        
        tables = [row[0] for row in cursor.fetchall()]
        if not tables:
            print_warning("Nenhuma tabela encontrada")
            conn.close()
            return
        
        print(f"Total de tabelas: {len(tables)}\n")
        
        total_records = 0
        
        for table_name in tables:
            # Contar registros
            cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
            row_count = cursor.fetchone()[0]
            total_records += row_count
            
            # Obter schema
            cursor.execute(f"PRAGMA table_info({table_name})")
            columns = cursor.fetchall()
            
            # Tamanho aproximado
            cursor.execute(f"SELECT SUM(LENGTH(CAST(* AS TEXT))) FROM {table_name}")
            size_result = cursor.fetchone()[0]
            size_kb = (size_result or 0) / 1024
            
            print(f"{Colors.BOLD}{Colors.CYAN}{table_name}{Colors.RESET}")
            print(f"  Registros: {row_count:,}")
            print(f"  Tamanho:   ~{size_kb:.1f} KB")
            print(f"  Colunas:   {len(columns)}")
            print(f"")
            
            # Listar colunas
            for col in columns:
                col_name = col[1]
                col_type = col[2]
                col_notnull = "NOT NULL" if col[3] else "NULL"
                col_pk = "PRIMARY KEY" if col[5] else ""
                
                constraints = f"[{' '.join(filter(None, [col_notnull, col_pk]))}]"
                print(f"    • {col_name:<30} {col_type:<15} {constraints}")
            
            print("")
        
        # Resumo
        print_header("📈 RESUMO")
        print(f"Total de tabelas:  {len(tables)}")
        print(f"Total de registros: {total_records:,}")
        print(f"Tamanho do banco:  {file_size_mb:.2f} MB")
        
        # Verificar índices
        cursor.execute("""
            SELECT COUNT(*) FROM sqlite_master 
            WHERE type='index' 
            AND name NOT LIKE 'sqlite_%'
        """)
        index_count = cursor.fetchone()[0]
        print(f"Índices:           {index_count}")
        
        # Próximos passos
        print_header("📋 PRÓXIMOS PASSOS")
        print("1. Instalar PostgreSQL (se ainda não tiver):")
        print("   INSTALACAO_MANUAL_POSTGRESQL.md")
        print("")
        print("2. Executar migração:")
        print("   python migrar_sqlite_postgresql.py")
        print("")
        print("3. Verificar dados no PostgreSQL:")
        print("   python test_postgres_connection.py")
        
        conn.close()
        return True
        
    except Exception as e:
        print_error(f"Erro ao analisar banco: {e}")
        return False

def main():
    """Função principal"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════════╗")
    print("║              ANÁLISE DO BANCO SQLITE                              ║")
    print("║           Exodo System - 26 de Maio de 2026                       ║")
    print("╚════════════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)
    
    # Procurar arquivo SQLite
    sqlite_path = get_sqlite_path()
    
    if not sqlite_path:
        print_error("Arquivo exodo_local.db não encontrado!")
        print_warning("Procurado em:")
        print(f"  • {Path.home() / 'Documents' / 'exodo_local.db'}")
        print(f"  • exodo_local.db (diretório atual)")
        print_info("\nDica: Se o arquivo está em outro lugar, copie para:")
        print(f"     {Path.home() / 'Documents'}")
        return 1
    
    # Executar análise
    if analyze_sqlite(sqlite_path):
        print(f"\n{Colors.GREEN}{Colors.BOLD}✅ ANÁLISE CONCLUÍDA{Colors.RESET}\n")
        return 0
    else:
        return 1

if __name__ == '__main__':
    sys.exit(main())

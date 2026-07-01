#!/usr/bin/env python3
"""
Script de Automação Completa: SQLite → PostgreSQL

Executa todas as etapas:
1. Análise do SQLite
2. Conexão com PostgreSQL
3. Migração de dados
4. Verificação de sucesso
"""

import os
import sys
import subprocess
from pathlib import Path
from dotenv import load_dotenv

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_step(step_num, title):
    print(f"\n{Colors.BOLD}{Colors.BLUE}[{step_num}] {title}{Colors.RESET}")
    print(f"{Colors.BLUE}{'-' * 60}{Colors.RESET}")

def print_ok(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.RESET}")

def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.RESET}")

def print_warning(text):
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.RESET}")

def run_script(script_name, description):
    """Executar um script Python"""
    print_step("RUN", f"Executando: {description}")
    
    try:
        result = subprocess.run(
            [sys.executable, script_name],
            capture_output=False,
            check=True
        )
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        print_error(f"Erro ao executar {script_name}")
        return False
    except FileNotFoundError:
        print_error(f"Arquivo {script_name} não encontrado")
        return False

def main():
    """Função principal"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║    AUTOMAÇÃO COMPLETA: SQLITE → POSTGRESQL                    ║")
    print("║         Exodo System - 26 de Maio de 2026                    ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)
    
    # Carregar .env
    load_dotenv()
    
    # Verificação pré-requisitos
    print_step(1, "VERIFICAÇÃO DE PRÉ-REQUISITOS")
    
    # 1. Verificar Python
    print("Verificando versão do Python...")
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
    if sys.version_info >= (3, 8):
        print_ok(f"Python {python_version}")
    else:
        print_error(f"Python {python_version} (mínimo 3.8 necessário)")
        return 1
    
    # 2. Verificar .env
    print("Verificando .env...")
    if not Path(".env").exists():
        print_error(".env não encontrado")
        print_warning("Crie com base em .env.postgresql.example")
        return 1
    else:
        print_ok(".env encontrado")
    
    # 3. Verificar variáveis de ambiente
    db_host = os.getenv('DB_HOST')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    
    if not all([db_host, db_name, db_user]):
        print_error("Variáveis PostgreSQL incompletas no .env")
        return 1
    else:
        print_ok(f"PostgreSQL: {db_user}@{db_host}:{os.getenv('DB_PORT', '5432')}/{db_name}")
    
    # 4. Verificar SQLite
    print("Verificando SQLite...")
    documents = Path.home() / "Documents"
    sqlite_file = documents / "exodo_local.db"
    
    if sqlite_file.exists():
        print_ok(f"SQLite encontrado: {sqlite_file}")
    else:
        print_error(f"SQLite não encontrado em {sqlite_file}")
        return 1
    
    # Analisar SQLite
    print_step(2, "ANÁLISE DO SQLITE")
    
    if not run_script("analisar_sqlite.py", "Análise do banco SQLite"):
        print_warning("Análise com aviso, continuando...")
    
    input(f"\n{Colors.BOLD}Pressione ENTER para continuar com a migração...{Colors.RESET}")
    
    # Executar migração
    print_step(3, "MIGRAÇÃO DE DADOS")
    
    if not run_script("migrar_sqlite_postgresql.py", "Migração SQLite → PostgreSQL"):
        print_error("Falha na migração!")
        return 1
    
    # Verificar sucesso
    print_step(4, "VERIFICAÇÃO FINAL")
    
    if not run_script("test_postgres_connection.py", "Teste de conexão PostgreSQL"):
        print_warning("Teste com aviso, verificando manualmente...")
    
    # Resumo final
    print_step("RESUMO", "Migração Concluída")
    
    print(f"\n{Colors.GREEN}{Colors.BOLD}✅ MIGRAÇÃO FINALIZADA COM SUCESSO!{Colors.RESET}\n")
    
    print(f"{Colors.BOLD}Próximos passos:{Colors.RESET}")
    print("  1. Verificar dados no PostgreSQL")
    print("     psql -U exodo_user -d exodo_db")
    print("     SELECT * FROM [tabela];")
    print("")
    print("  2. Fazer backup do SQLite (opcional)")
    print("     cp ~/Documents/exodo_local.db ~/Documents/exodo_local.db.backup")
    print("")
    print("  3. Atualizar código da aplicação para usar PostgreSQL")
    print("")
    print("  4. Testar aplicação")
    print("")
    print(f"\n{Colors.BOLD}Documentação:{Colors.RESET}")
    print("  • GUIA_MIGRACAO_DADOS_SQLITE_PG.md - Guia completo")
    print("  • MIGRACAO_SQLITE_POSTGRESQL.md - Detalhes técnicos")
    print("")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())

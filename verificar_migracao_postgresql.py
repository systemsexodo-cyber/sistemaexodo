#!/usr/bin/env python3
"""
Script de verificação completa da migração SQLite → PostgreSQL

Execute este script para validar se tudo está configurado corretamente
"""

import os
import sys
from dotenv import load_dotenv

# Carregar ambiente
load_dotenv()

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}\n")

def print_ok(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.RESET}")

def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.RESET}")

def print_warning(text):
    print(f"{Colors.YELLOW}⚠️  {text}{Colors.RESET}")

def print_info(text):
    print(f"{Colors.BLUE}ℹ️  {text}{Colors.RESET}")

def check_files():
    """Verificar se arquivos necessários existem"""
    print_header("1️⃣  VERIFICAÇÃO DE ARQUIVOS")
    
    files = {
        'MIGRACAO_SQLITE_POSTGRESQL.md': 'Guia completo de migração',
        'GUIA_RAPIDO_POSTGRESQL.md': 'Guia rápido',
        'INSTALAR_POSTGRESQL_WINDOWS.ps1': 'Script de instalação',
        'test_postgres_connection.py': 'Script de teste',
        '.env.postgresql.example': 'Exemplo de configuração',
    }
    
    all_ok = True
    for filename, description in files.items():
        if os.path.exists(filename):
            print_ok(f"{filename} - {description}")
        else:
            print_error(f"{filename} NÃO ENCONTRADO - {description}")
            all_ok = False
    
    return all_ok

def check_environment():
    """Verificar variáveis de ambiente"""
    print_header("2️⃣  VERIFICAÇÃO DE VARIÁVEIS DE AMBIENTE")
    
    required_vars = {
        'DB_HOST': 'localhost',
        'DB_PORT': '5432',
        'DB_NAME': 'exodo_db',
        'DB_USER': 'exodo_user',
        'DB_PASSWORD': '[deve estar definido]',
    }
    
    all_ok = True
    for var, description in required_vars.items():
        value = os.getenv(var)
        if value:
            print_ok(f"{var} = {value if var != 'DB_PASSWORD' else '***'}")
        else:
            print_error(f"{var} NÃO DEFINIDO (esperado: {description})")
            all_ok = False
    
    if not all_ok:
        print_warning("\n📝 Crie arquivo .env com base em .env.postgresql.example")
        print_info("   Conteúdo mínimo necessário:")
        print("""
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=sua_senha
        """)
    
    return all_ok

def check_python_packages():
    """Verificar pacotes Python necessários"""
    print_header("3️⃣  VERIFICAÇÃO DE PACOTES PYTHON")
    
    packages = {
        'psycopg2': 'Driver PostgreSQL',
        'flask': 'Framework Web',
        'flask_sqlalchemy': 'ORM SQLAlchemy para Flask',
        'dotenv': 'Carregamento de variáveis de ambiente',
    }
    
    all_ok = True
    for package, description in packages.items():
        try:
            __import__(package)
            print_ok(f"{package} - {description}")
        except ImportError:
            print_error(f"{package} NÃO INSTALADO - {description}")
            print_info(f"   Execute: pip install {package}")
            all_ok = False
    
    return all_ok

def check_postgresql_connection():
    """Verificar conexão com PostgreSQL"""
    print_header("4️⃣  VERIFICAÇÃO DE CONEXÃO COM POSTGRESQL")
    
    try:
        import psycopg2
    except ImportError:
        print_error("psycopg2 não instalado - pulando teste de conexão")
        return False
    
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    
    if not all([db_name, db_user, db_password]):
        print_error("Variáveis de ambiente incompletas")
        return False
    
    try:
        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            database=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=5
        )
        
        cursor = conn.cursor()
        cursor.execute("SELECT version();")
        version = cursor.fetchone()[0]
        
        print_ok(f"Conexão bem-sucedida!")
        print_info(f"PostgreSQL: {version[:50]}...")
        
        # Verificar tabelas
        cursor.execute("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
        """)
        table_count = cursor.fetchone()[0]
        print_info(f"Tabelas na base: {table_count}")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print_error(f"Erro de conexão: {e}")
        print_warning("\nPossíveis causas:")
        print("  • PostgreSQL não está rodando")
        print("  • Host/porta/credenciais incorretos")
        print("  • Banco de dados não existe")
        return False

def check_app_structure():
    """Verificar estrutura de diretórios"""
    print_header("5️⃣  VERIFICAÇÃO DE ESTRUTURA DO PROJETO")
    
    directories = {
        'backend_pynfe': 'Backend Python para NFC-e',
        'backend_nfce': 'Backend alternativo',
        'evolution-api': 'API WhatsApp',
    }
    
    all_ok = True
    for dirname, description in directories.items():
        if os.path.isdir(dirname):
            print_ok(f"📁 {dirname} - {description}")
        else:
            print_warning(f"📁 {dirname} não encontrado (opcional)")
    
    # Verificar requirements.txt
    if os.path.exists('backend_pynfe/requirements.txt'):
        print_ok("requirements.txt encontrado em backend_pynfe")
        with open('backend_pynfe/requirements.txt', 'r') as f:
            content = f.read()
            if 'psycopg2' in content or 'postgresql' in content:
                print_ok("✅ requirements.txt já tem drivers PostgreSQL")
            else:
                print_warning("requirements.txt não menciona PostgreSQL")
                print_info("Adicione estas linhas:")
                print("  psycopg2-binary>=2.9.0")
                print("  sqlalchemy>=2.0.0")
    else:
        print_warning("requirements.txt não encontrado em backend_pynfe")
    
    return all_ok

def print_summary(results):
    """Imprimir resumo final"""
    print_header("📊 RESUMO DA VERIFICAÇÃO")
    
    checks = [
        ("Arquivos criados", results['files']),
        ("Variáveis de ambiente", results['environment']),
        ("Pacotes Python", results['packages']),
        ("Conexão com PostgreSQL", results['postgres']),
        ("Estrutura do projeto", results['structure']),
    ]
    
    all_passed = all(results.values())
    
    for check_name, passed in checks:
        status = f"{Colors.GREEN}✅ OK{Colors.RESET}" if passed else f"{Colors.RED}❌ ERRO{Colors.RESET}"
        print(f"{check_name:<40} {status}")
    
    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
    
    if all_passed:
        print(f"{Colors.GREEN}{Colors.BOLD}✅ TUDO PRONTO PARA POSTGRESQL!{Colors.RESET}")
        print(f"\n{Colors.GREEN}Próximos passos:{Colors.RESET}")
        print("  1. python test_postgres_connection.py")
        print("  2. Testar backend com: python app.py")
        print("  3. Acessar em: http://localhost:5000/health")
    else:
        print(f"{Colors.RED}{Colors.BOLD}❌ HÁ PROBLEMAS A RESOLVER{Colors.RESET}")
        print(f"\n{Colors.YELLOW}Corriga os erros acima e execute novamente{Colors.RESET}")
    
    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}\n")
    
    return all_passed

def main():
    """Função principal"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════╗")
    print("║    VERIFICAÇÃO DE MIGRAÇÃO SQLITE → POSTGRESQL             ║")
    print("║         Sistema Exodo - 15 de Abril de 2026               ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print(Colors.RESET)
    
    results = {
        'files': check_files(),
        'environment': check_environment(),
        'packages': check_python_packages(),
        'postgres': check_postgresql_connection(),
        'structure': check_app_structure(),
    }
    
    all_passed = print_summary(results)
    
    return 0 if all_passed else 1

if __name__ == '__main__':
    sys.exit(main())

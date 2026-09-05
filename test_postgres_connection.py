#!/usr/bin/env python3
"""
Script de teste de conexão com PostgreSQL
Verifica se a configuração está correta
"""

import os
import sys
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

def test_postgres_connection():
    """Testa conexão com PostgreSQL"""
    
    print("\n" + "="*60)
    print("🔍 TESTE DE CONEXÃO COM POSTGRESQL")
    print("="*60 + "\n")
    
    # Verificar variáveis de ambiente
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    db_name = os.getenv('DB_NAME')
    db_user = os.getenv('DB_USER')
    db_password = os.getenv('DB_PASSWORD')
    
    print("📋 Configurações detectadas:")
    print(f"  Host: {db_host}")
    print(f"  Porta: {db_port}")
    print(f"  Database: {db_name or '❌ NÃO CONFIGURADO'}")
    print(f"  Usuário: {db_user or '❌ NÃO CONFIGURADO'}")
    print(f"  Senha: {'***' if db_password else '❌ NÃO CONFIGURADA'}")
    print()
    
    # Validações básicas
    if not all([db_name, db_user, db_password]):
        print("❌ Configuração incompleta!")
        print("\n📝 Adicione ao arquivo .env:")
        print("  DB_HOST=localhost")
        print("  DB_PORT=5432")
        print("  DB_NAME=exodo_db")
        print("  DB_USER=exodo_user")
        print("  DB_PASSWORD=sua_senha")
        return False
    
    # Tentar importar psycopg2
    try:
        import psycopg2
        print("✅ psycopg2 instalado")
    except ImportError:
        print("❌ psycopg2 não instalado!")
        print("\n   Execute: pip install psycopg2-binary")
        return False
    
    # Tentar conectar
    try:
        print("\n🔗 Conectando ao PostgreSQL...\n")
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
        db_version = cursor.fetchone()[0]
        
        print(f"✅ Conexão bem-sucedida!\n")
        print(f"   Versão PostgreSQL: {db_version}\n")
        
        # Testar query
        cursor.execute("SELECT 1 as test;")
        result = cursor.fetchone()
        print(f"✅ Query de teste OK: {result}\n")
        
        # Listar tabelas
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            ORDER BY table_name;
        """)
        tables = cursor.fetchall()
        
        if tables:
            print(f"📊 Tabelas encontradas ({len(tables)}):")
            for table in tables:
                print(f"   • {table[0]}")
        else:
            print("📊 Nenhuma tabela encontrada (banco vazio - normal em setup novo)")
        
        print()
        
        cursor.close()
        conn.close()
        
        return True
        
    except psycopg2.OperationalError as e:
        print(f"❌ Erro de conexão:\n   {e}\n")
        print("💡 Verifique:")
        print("   • PostgreSQL está rodando?")
        print("   • Host e porta corretos?")
        print("   • Usuário e senha corretos?")
        print("   • Banco de dados existe?")
        return False
    except Exception as e:
        print(f"❌ Erro inesperado:\n   {type(e).__name__}: {e}\n")
        return False

def create_database():
    """Oferece ajuda para criar banco de dados"""
    print("\n" + "="*60)
    print("🛠️  CRIAR BANCO DE DADOS")
    print("="*60 + "\n")
    
    print("Execute estes comandos no PostgreSQL para setup inicial:\n")
    print("""
# Conectar como administrador
psql -U postgres

# Dentro do psql, executar:

-- Criar usuário
CREATE USER exodo_user WITH PASSWORD 'sua_senha_segura';

-- Criar banco
CREATE DATABASE exodo_db OWNER exodo_user;

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;

-- Sair
\\q
    """)

def main():
    """Função principal"""
    success = test_postgres_connection()
    
    if not success:
        print("\n❌ TESTE FALHOU")
        create_database()
        sys.exit(1)
    
    print("✅ TESTE PASSOU - Sistema pronto para usar PostgreSQL!\n")
    return 0

if __name__ == '__main__':
    sys.exit(main())

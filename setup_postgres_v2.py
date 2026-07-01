#!/usr/bin/env python3
"""
Script direto para criar banco PostgreSQL
"""

import psycopg2
from psycopg2 import sql
import os

def setup_database():
    # Conectar como postgres (admin)
    # Tentaremos sem senha primeiro (trust connection)
    
    connections = [
        {'password': None},  # Try without password
        {'password': 'postgres'},
        {'password': ''},
    ]
    
    conn = None
    for attempt in connections:
        try:
            passwd = attempt['password']
            conn = psycopg2.connect(
                host='localhost',
                port=5432,
                database='postgres',
                user='postgres',
                password=passwd,
                connect_timeout=5
            )
            print(f"✅ Conectado como postgres (password: {passwd if passwd else 'None'})")
            break
        except Exception as e:
            print(f"⚠️  Tentativa falhou: {e}")
            continue
    
    if conn is None:
        print("❌ Não foi possível conectar como postgres")
        return False
    
    try:
        conn.set_isolation_level(0)  # AutoCommit
        cursor = conn.cursor()
        
        print("\n1️⃣  Criando usuário 'exodo_user'...")
        try:
            cursor.execute("CREATE USER exodo_user WITH PASSWORD 'senha123';")
            print("✅ Usuário criado")
        except Exception as e:
            if 'already exists' in str(e):
                print("⚠️  Usuário já existe")
            else:
                print(f"❌ {e}")
        
        print("2️⃣  Concedendo permissões ao usuário...")
        cursor.execute("ALTER ROLE exodo_user CREATEDB;")
        print("✅ Permissões concedidas")
        
        print("3️⃣  Removendo banco antigo (se existe)...")
        try:
            cursor.execute("DROP DATABASE IF EXISTS exodo_db;")
            print("✅ Banco antigo removido")
        except Exception as e:
            print(f"⚠️  {e}")
        
        print("4️⃣  Criando banco 'exodo_db'...")
        try:
            cursor.execute("CREATE DATABASE exodo_db OWNER exodo_user ENCODING 'UTF8';")
            print("✅ Banco criado")
        except Exception as e:
            print(f"❌ {e}")
            return False
        
        print("5️⃣  Concedendo privilégios...")
        cursor.execute("GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;")
        print("✅ Privilégios concedidos")
        
        cursor.close()
        conn.close()
        
        print("\n✅ Banco PostgreSQL criado com sucesso!\n")
        return True
        
    except Exception as e:
        print(f"❌ Erro: {e}")
        return False
    finally:
        if conn:
            conn.close()

if __name__ == '__main__':
    success = setup_database()
    exit(0 if success else 1)

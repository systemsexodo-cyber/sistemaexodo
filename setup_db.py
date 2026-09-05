#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys

# Forçar UTF-8 em todo o script
os.environ['PYTHONIOENCODING'] = 'utf-8'
sys.stdout.reconfigure(encoding='utf-8')

import psycopg2
from psycopg2 import sql

def setup_database():
    try:
        # Conectar como postgres sem autenticação
        conn = psycopg2.connect(
            host='localhost',
            port=5432,
            dbname='postgres',
            user='postgres'
        )
        conn.set_isolation_level(0)  # AutoCommit mode
        
        cursor = conn.cursor()
        
        print("1️⃣  Criando usuário 'exodo_user'...")
        try:
            cursor.execute("CREATE USER exodo_user WITH PASSWORD 'senha123';")
        except Exception as e:
            if 'already exists' in str(e):
                print("   ⚠️  Usuário já existe")
            else:
                raise
        
        print("2️⃣  Concedendo permissões...")
        cursor.execute("ALTER ROLE exodo_user CREATEDB;")
        
        print("3️⃣  Removendo banco antigo...")
        cursor.execute("DROP DATABASE IF EXISTS exodo_db;")
        
        print("4️⃣  Criando banco 'exodo_db'...")
        cursor.execute("CREATE DATABASE exodo_db OWNER exodo_user ENCODING 'UTF8';")
        
        print("5️⃣  Concedendo privilégios...")
        cursor.execute("GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;")
        
        cursor.close()
        conn.close()
        
        print("\n✅ Banco criado com sucesso!")
        return True
        
    except Exception as e:
        print(f"❌ Erro: {type(e).__name__}: {e}")
        return False

if __name__ == '__main__':
    exit(0 if setup_database() else 1)

#!/usr/bin/env python3
"""
Script para criar banco PostgreSQL com UTF-8 correto
"""

import subprocess
import os
import sys

# Caminho do PostgreSQL
pg_path = r"C:\Program Files\PostgreSQL\18\bin"

print("🔧 Criando banco PostgreSQL com UTF-8...")

try:
    # 1. Criar usuário
    print("\n1️⃣  Criando usuário 'exodo_user'...")
    cmd_user = [
        os.path.join(pg_path, 'psql.exe'),
        '-U', 'postgres',
        '-h', 'localhost',
        '-c', "CREATE USER IF NOT EXISTS exodo_user WITH PASSWORD 'senha123';"
    ]
    result = subprocess.run(cmd_user, capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)
    if result.returncode != 0 and 'already exists' not in result.stderr:
        print(f"⚠️  {result.stderr}")

    # 2. Conceder permissões
    print("2️⃣  Concedendo permissões...")
    cmd_perms = [
        os.path.join(pg_path, 'psql.exe'),
        '-U', 'postgres',
        '-h', 'localhost',
        '-c', "ALTER ROLE exodo_user CREATEDB;"
    ]
    result = subprocess.run(cmd_perms, capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)

    # 3. Dropar banco antigo (se existe)
    print("3️⃣  Removendo banco antigo (se existe)...")
    cmd_drop = [
        os.path.join(pg_path, 'psql.exe'),
        '-U', 'postgres',
        '-h', 'localhost',
        '-c', "DROP DATABASE IF EXISTS exodo_db;"
    ]
    result = subprocess.run(cmd_drop, capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)

    # 4. Criar banco novo com UTF-8
    print("4️⃣  Criando banco 'exodo_db' com UTF-8...")
    cmd_db = [
        os.path.join(pg_path, 'psql.exe'),
        '-U', 'postgres',
        '-h', 'localhost',
        '-c', "CREATE DATABASE exodo_db OWNER exodo_user ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C';"
    ]
    result = subprocess.run(cmd_db, capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)
    if result.returncode != 0:
        print(f"❌ Erro: {result.stderr}")
        sys.exit(1)

    # 5. Conceder privilégios
    print("5️⃣  Concedendo privilégios...")
    cmd_grant = [
        os.path.join(pg_path, 'psql.exe'),
        '-U', 'postgres',
        '-h', 'localhost',
        '-c', "GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;"
    ]
    result = subprocess.run(cmd_grant, capture_output=True, text=True, encoding='utf-8')
    print(result.stdout)

    print("\n✅ Banco PostgreSQL criado com sucesso!\n")

except Exception as e:
    print(f"❌ Erro: {e}")
    sys.exit(1)

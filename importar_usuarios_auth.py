import os, urllib.request, json
import psycopg2
from psycopg2.extras import Json
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

db_host     = os.getenv('DB_HOST', 'localhost')
db_port     = os.getenv('DB_PORT', '5432')
db_name     = os.getenv('DB_NAME')
db_user     = os.getenv('DB_USER')
db_password = os.getenv('DB_PASSWORD')

headers = {
    'Accept': 'application/json',
    'apikey': api_key,
    'Authorization': f'Bearer {api_key}',
}

# 1. Buscar todos os usuarios do Supabase Auth
print("Buscando usuarios do Supabase Auth...")
todos_usuarios = []
pagina = 1
por_pagina = 50
while True:
    url = f"{supabase_url}/auth/v1/admin/users?page={pagina}&per_page={por_pagina}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        dados = json.loads(r.read())
    usuarios = dados.get('users', dados) if isinstance(dados, dict) else dados
    if not usuarios:
        break
    todos_usuarios.extend(usuarios)
    if len(usuarios) < por_pagina:
        break
    pagina += 1

print(f"Encontrados {len(todos_usuarios)} usuario(s) no Supabase.")

# 2. Conectar ao PostgreSQL local
print("Conectando ao banco local...")
conn = psycopg2.connect(
    host=db_host, port=int(db_port),
    dbname=db_name, user=db_user, password=db_password
)
cur = conn.cursor()

# 3. Criar tabela usuarios se nao existir
cur.execute("""
    CREATE TABLE IF NOT EXISTS usuarios (
        id                  TEXT PRIMARY KEY,
        email               TEXT,
        nome                TEXT,
        telefone            TEXT,
        perfil              TEXT,
        email_confirmado    BOOLEAN DEFAULT FALSE,
        ultimo_acesso       TEXT,
        criado_em           TEXT,
        atualizado_em       TEXT,
        dados_usuario       JSONB,
        dados_app           JSONB,
        ativo               BOOLEAN DEFAULT TRUE,
        _sincronizado_nuvem BOOLEAN DEFAULT TRUE
    )
""")
conn.commit()
print("Tabela 'usuarios' pronta.")

# 4. Importar cada usuario
importados = 0
for u in todos_usuarios:
    meta     = u.get('user_metadata') or {}
    app_meta = u.get('app_metadata') or {}
    nome = (
        meta.get('nome')
        or meta.get('name')
        or meta.get('full_name')
        or u.get('email', '').split('@')[0]
    )

    cur.execute("""
        INSERT INTO usuarios
            (id, email, nome, telefone, perfil, email_confirmado,
             ultimo_acesso, criado_em, atualizado_em,
             dados_usuario, dados_app, ativo, _sincronizado_nuvem)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (id) DO UPDATE SET
            email            = EXCLUDED.email,
            nome             = EXCLUDED.nome,
            telefone         = EXCLUDED.telefone,
            perfil           = EXCLUDED.perfil,
            email_confirmado = EXCLUDED.email_confirmado,
            ultimo_acesso    = EXCLUDED.ultimo_acesso,
            atualizado_em    = EXCLUDED.atualizado_em,
            dados_usuario    = EXCLUDED.dados_usuario,
            dados_app        = EXCLUDED.dados_app
    """, (
        u.get('id'),
        u.get('email'),
        nome,
        u.get('phone'),
        u.get('role', 'authenticated'),
        bool(u.get('email_confirmed_at')),
        u.get('last_sign_in_at'),
        u.get('created_at'),
        u.get('updated_at'),
        Json(meta),
        Json(app_meta),
        not u.get('banned', False),
        True,
    ))
    importados += 1
    print(f"  -> {u.get('email')} importado com sucesso")

conn.commit()
conn.close()

print(f"\nConcluido! {importados} usuario(s) importado(s) para o banco local.")

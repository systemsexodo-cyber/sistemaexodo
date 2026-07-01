import os, urllib.request, json
import psycopg2
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

# Mapeamento de tipos OpenAPI -> PostgreSQL
def openapi_to_pg(fmt, tipo):
    mapa = {
        ('string', 'uuid'):      'TEXT',
        ('string', 'timestamp'): 'TIMESTAMP WITH TIME ZONE',
        ('string', 'date-time'): 'TIMESTAMP WITH TIME ZONE',
        ('string', 'date'):      'DATE',
        ('string', 'time'):      'TIME',
        ('string', None):        'TEXT',
        ('integer', None):       'BIGINT',
        ('integer', 'int2'):     'SMALLINT',
        ('integer', 'int4'):     'INTEGER',
        ('integer', 'int8'):     'BIGINT',
        ('number', None):        'NUMERIC',
        ('number', 'float4'):    'REAL',
        ('number', 'float8'):    'DOUBLE PRECISION',
        ('boolean', None):       'BOOLEAN',
        ('object', None):        'JSONB',
        ('array', None):         'JSONB',
    }
    return mapa.get((tipo, fmt)) or mapa.get((tipo, None)) or 'TEXT'

# 1. Buscar schema OpenAPI do Supabase
print("Buscando schema completo do Supabase...")
req = urllib.request.Request(f"{supabase_url}/rest/v1/", headers=headers)
with urllib.request.urlopen(req, timeout=30) as r:
    schema = json.loads(r.read())

definitions = schema.get('definitions', {})
print(f"Schema carregado: {len(definitions)} tabelas encontradas.")

# 2. Conectar ao PostgreSQL local
print("Conectando ao banco local...")
conn = psycopg2.connect(
    host=db_host, port=int(db_port),
    dbname=db_name, user=db_user, password=db_password
)
cur = conn.cursor()

# 3. Verificar quais tabelas já existem no local
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
tabelas_existentes = {r[0] for r in cur.fetchall()}
print(f"Tabelas ja existentes no banco local: {len(tabelas_existentes)}")

# 4. Criar tabelas faltantes
criadas = 0
for nome_tabela, definicao in definitions.items():
    # Pular views
    if nome_tabela.startswith('vw_') or nome_tabela.startswith('view_'):
        print(f"  [IGNORADA] {nome_tabela} (e uma view)")
        continue

    if nome_tabela in tabelas_existentes:
        print(f"  [JA EXISTE] {nome_tabela}")
        continue

    propriedades = definicao.get('properties', {})
    required     = definicao.get('required', [])

    if not propriedades:
        print(f"  [SEM SCHEMA] {nome_tabela} - nao foi possivel obter colunas")
        continue

    colunas = []
    for col_nome, col_info in propriedades.items():
        tipo_openapi = col_info.get('type', 'string')
        formato      = col_info.get('format')
        pg_tipo      = openapi_to_pg(formato, tipo_openapi)

        col_def = f'"{col_nome}" {pg_tipo}'
        if col_nome == 'id':
            col_def += ' PRIMARY KEY'
        elif col_nome in required:
            col_def += ' NOT NULL'

        colunas.append(col_def)

    # Adicionar coluna de sincronizacao
    colunas.append('"_sincronizado_nuvem" BOOLEAN DEFAULT FALSE')

    sql_create = f'CREATE TABLE IF NOT EXISTS "{nome_tabela}" (\n    ' + ',\n    '.join(colunas) + '\n)'

    try:
        cur.execute(sql_create)
        conn.commit()
        criadas += 1
        print(f"  [CRIADA] {nome_tabela} ({len(colunas)-1} colunas)")
    except Exception as e:
        conn.rollback()
        print(f"  [ERRO] {nome_tabela}: {e}")

conn.close()
print(f"\nConcluido! {criadas} tabela(s) criada(s) no banco local.")

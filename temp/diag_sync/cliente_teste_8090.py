"""Cliente de teste: banco com schema antigo + migracao pelo portal da central.

Cria `exodo_cliente_teste` a partir do baseline (init_db.sql), dispara
"aplicar pendentes" no portal 8090 apontando para essa conexao e confere o
resultado. Nao imprime credenciais. O banco FICA para inspecao no painel.
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import psycopg2

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ))
sys.path.insert(0, str(RAIZ / "scripts"))

import portal_nuvem  # noqa: E402

BASE = "http://127.0.0.1:8090"
DB = "exodo_cliente_teste"

u = urllib.parse.urlsplit(portal_nuvem._get_local_pg_dsn())
CONN = {
    "host": u.hostname or "localhost",
    "porta": str(u.port or 5432),
    "banco": DB,
    "usuario": urllib.parse.unquote(u.username or ""),
    "senha": urllib.parse.unquote(u.password or ""),
}


def conectar(dbname):
    c = psycopg2.connect(
        host=CONN["host"], port=CONN["porta"], user=CONN["usuario"],
        password=CONN["senha"], dbname=dbname, connect_timeout=8,
    )
    c.set_client_encoding("UTF8")
    return c


def esperar(segundos=30):
    fim = time.time() + segundos
    while time.time() < fim:
        try:
            with urllib.request.urlopen(BASE + "/admin/migrations/list", timeout=3) as r:
                if r.status == 200:
                    return True
        except Exception:
            time.sleep(1)
    return False


def get_json(caminho):
    with urllib.request.urlopen(BASE + caminho, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def post_json(caminho, dados):
    req = urllib.request.Request(
        BASE + caminho, data=json.dumps(dados).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


if not esperar():
    print("ERRO: portal 8090 nao respondeu")
    sys.exit(1)
print("portal 8090 OK")

# 1. Banco do "cliente de teste" com o baseline (schema antigo)
adm = conectar("postgres")
adm.autocommit = True
with adm.cursor() as cur:
    cur.execute(f"DROP DATABASE IF EXISTS {DB} WITH (FORCE)")
    cur.execute(f"CREATE DATABASE {DB} ENCODING 'UTF8' TEMPLATE template0")
adm.close()

conn = conectar(DB)
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute((RAIZ / "scripts/init_db.sql").read_text(encoding="utf-8"))
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema='public' AND table_type='BASE TABLE'")
    print("cliente de teste criado: %d tabelas (baseline)" % cur.fetchone()[0])
    cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
    print("ajustes_estoque_lote antes: %s" % cur.fetchone()[0])
conn.close()

# 2. Lista apontando para o cliente de teste
q = urllib.parse.urlencode({k: CONN[k] for k in ("host", "porta", "banco", "usuario", "senha")})
lista = get_json("/admin/migrations/list?" + q)
print("list: origem=%s total=%s pendentes=%s" % (
    lista.get("origem"), lista.get("total"), lista.get("pendentes")))

# 3. Aplica as pendentes via portal
res = post_json("/admin/migrations/run", {"todas": True, "conn": CONN, "descricao": "Cliente teste"})
print("run: sucesso=%s aplicadas=%s" % (res.get("sucesso"), res.get("aplicadas")))
for r in res.get("resultados") or []:
    if r.get("erro"):
        print("  FALHOU %s %s -> %s" % (r.get("versao"), r.get("arquivo"), r.get("erro")))

# 4. Confere o resultado no banco do cliente
conn = conectar(DB)
with conn.cursor() as cur:
    cur.execute("SELECT versao, nome FROM public.schema_migrations ORDER BY versao")
    regs = cur.fetchall()
    print("schema_migrations no cliente: %d -> %s" % (len(regs), [r[0] for r in regs]))
    cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
    print("ajustes_estoque_lote depois: %s" % cur.fetchone()[0])
conn.close()

print("banco mantido para inspecao: %s (remover: DROP DATABASE %s)" % (DB, DB))

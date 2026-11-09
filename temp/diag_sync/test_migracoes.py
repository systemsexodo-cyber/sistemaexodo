"""Teste ponta a ponta das migracoes de schema pela Central.

Cria um banco descartavel com o baseline (init_db.sql), dispara a migracao pelo
endpoint do portal (como o botao do painel faz) e confere o resultado.
Nao imprime credenciais e apaga o banco no final.
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

BASE = "http://127.0.0.1:8091"
DB = "exodo_teste_migracao"

dsn = portal_nuvem._get_local_pg_dsn()
u = urllib.parse.urlsplit(dsn)
CONN = {
    "host": u.hostname or "localhost",
    "porta": str(u.port or 5432),
    "banco": DB,
    "usuario": urllib.parse.unquote(u.username or ""),
    "senha": urllib.parse.unquote(u.password or ""),
}


def esperar_portal(segundos=25):
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
        BASE + caminho,
        data=json.dumps(dados).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


def conectar(dbname):
    c = psycopg2.connect(
        host=CONN["host"], port=CONN["porta"], user=CONN["usuario"],
        password=CONN["senha"], dbname=dbname, connect_timeout=8,
    )
    c.set_client_encoding("UTF8")
    return c


if not esperar_portal():
    print("ERRO: portal de teste (8091) nao respondeu")
    sys.exit(1)
print("portal de teste OK")

# 1. Banco descartavel + baseline
adm = conectar("postgres")
adm.autocommit = True
with adm.cursor() as cur:
    cur.execute(f'DROP DATABASE IF EXISTS {DB}')
    cur.execute(f"CREATE DATABASE {DB} ENCODING 'UTF8' TEMPLATE template0")
adm.close()

conn = conectar(DB)
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute((RAIZ / "scripts/init_db.sql").read_text(encoding="utf-8"))
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM information_schema.tables "
                "WHERE table_schema='public' AND table_type='BASE TABLE'")
    print("baseline: %d tabelas" % cur.fetchone()[0])
    cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
    print("tem ajustes_estoque_lote antes: %s" % cur.fetchone()[0])
conn.close()

# 2. Lista apontando para o banco do "cliente"
q = urllib.parse.urlencode({k: CONN[k] for k in ("host", "porta", "banco", "usuario", "senha")})
lista = get_json("/admin/migrations/list?" + q)
print("list origem=%s total=%s pendentes=%s" % (
    lista.get("origem"), lista.get("total"), lista.get("pendentes")))

# 3. Aplica todas as pendentes
res = post_json("/admin/migrations/run", {"todas": True, "conn": CONN, "descricao": "teste"})
print("run sucesso=%s aplicadas=%s" % (res.get("sucesso"), res.get("aplicadas")))
for r in res.get("resultados") or []:
    if r.get("erro"):
        print("  FALHOU %s %s -> %s" % (r.get("versao"), r.get("arquivo"), r.get("erro")))

# 4. Confere o efeito real
conn = conectar(DB)
with conn.cursor() as cur:
    cur.execute("SELECT versao, nome FROM public.schema_migrations ORDER BY versao")
    registros = cur.fetchall()
    print("schema_migrations: %d registros -> %s" % (len(registros), [r[0] for r in registros]))
    cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
    print("tem ajustes_estoque_lote depois: %s" % cur.fetchone()[0])
conn.close()

# 5. Segunda execucao: tem que pular tudo (idempotencia do controle)
res2 = post_json("/admin/migrations/run", {"todas": True, "conn": CONN})
puladas = [r["versao"] for r in (res2.get("resultados") or []) if r.get("pulada")]
print("segunda execucao: aplicadas=%s puladas=%s" % (res2.get("aplicadas"), puladas))

# 6. Limpeza
adm = conectar("postgres")
adm.autocommit = True
with adm.cursor() as cur:
    cur.execute(f'DROP DATABASE IF EXISTS {DB} WITH (FORCE)')
adm.close()
print("banco de teste removido")

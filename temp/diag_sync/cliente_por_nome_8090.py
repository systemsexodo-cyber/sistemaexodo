"""Testa o fluxo do painel: salvar conexao do cliente e migrar pelo NOME.

1. Recria o banco `exodo_cliente_teste` no baseline (schema antigo).
2. Salva a conexao como "Cliente Teste" (mesmo botao da aba Banco Local).
3. Lista as migracoes com ?conexao=Cliente Teste.
4. Aplica as pendentes mandando apenas o nome (a senha fica no servidor).
5. Confere o resultado no banco do cliente.
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
NOME = "Cliente Teste"

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
        password=CONN["senha"], dbname=dbname, connect_timeout=8)
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


def req_json(caminho, dados=None, metodo="GET"):
    corpo = json.dumps(dados).encode("utf-8") if dados is not None else None
    req = urllib.request.Request(
        BASE + caminho, data=corpo, method=metodo,
        headers={"Content-Type": "application/json"} if corpo else {})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


if not esperar():
    print("ERRO: portal 8090 nao respondeu")
    sys.exit(1)

# 1. Banco do cliente no baseline
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
    print("cliente recriado no baseline: %d tabelas" % cur.fetchone()[0])
conn.close()

# 2. Salva a conexao do cliente (como o botao "Salvar Conexao")
salvo = req_json("/admin/local/connections", CONN | {"nome": NOME}, "POST")
print("conexao salva: %s" % (salvo.get("conexao", {}).get("nome") or salvo))

# 3. Lista escolhendo o cliente pelo nome
lista = req_json("/admin/migrations/list?conexao=" + urllib.parse.quote(NOME))
print("list por nome: origem=%s total=%s pendentes=%s" % (
    lista.get("origem"), lista.get("total"), lista.get("pendentes")))

# 4. Aplica mandando SO o nome (senha resolvida no servidor)
res = req_json("/admin/migrations/run",
               {"todas": True, "conn": {"nome": NOME}, "descricao": "Cliente Teste"}, "POST")
print("run por nome: sucesso=%s aplicadas=%s" % (res.get("sucesso"), res.get("aplicadas")))
for r in res.get("resultados") or []:
    if r.get("erro"):
        print("  FALHOU %s %s -> %s" % (r.get("versao"), r.get("arquivo"), r.get("erro")))

# 5. Confere no banco
conn = conectar(DB)
with conn.cursor() as cur:
    cur.execute("SELECT versao FROM public.schema_migrations ORDER BY versao")
    vs = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
    tabela = cur.fetchone()[0]
conn.close()
print("schema_migrations no cliente (%d): %s" % (len(vs), vs))
print("ajustes_estoque_lote criada: %s" % tabela)

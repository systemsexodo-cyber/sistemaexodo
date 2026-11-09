"""Testa /admin/migrations/run_all: migra todas as conexoes salvas de uma vez.

1. Cria um segundo banco de teste (`exodo_cliente_teste2`) no baseline.
2. Salva a conexao como "Cliente Teste 2" (o "Cliente Teste" ja esta migrado).
3. Chama run_all e imprime o relatorio por cliente.
4. Confere `schema_migrations` em cada banco.
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
DB2 = "exodo_cliente_teste2"
NOME2 = "Cliente Teste 2"

u = urllib.parse.urlsplit(portal_nuvem._get_local_pg_dsn())
CONN = {
    "host": u.hostname or "localhost",
    "porta": str(u.port or 5432),
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

# 1. Segundo cliente: copia do banco de teste com o controle de migracoes
#    zerado (simula um cliente cujo schema ainda esta atras).
adm = conectar("postgres")
adm.autocommit = True
with adm.cursor() as cur:
    cur.execute(f"DROP DATABASE IF EXISTS {DB2} WITH (FORCE)")
    cur.execute(f"CREATE DATABASE {DB2} ENCODING 'UTF8' TEMPLATE exodo_cliente_teste")
adm.close()
conn = conectar(DB2)
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute("TRUNCATE public.schema_migrations")
    cur.execute("SELECT count(*) FROM public.schema_migrations")
    print("cliente 2 pronto, %d migrations registradas" % cur.fetchone()[0])
conn.close()

# 2. Conexao salva
salvo = req_json("/admin/local/connections",
                 CONN | {"banco": DB2, "nome": NOME2}, "POST")
print("conexao salva: %s" % (salvo.get("conexao", {}).get("nome") or salvo))

# 3. run_all
inicio = time.time()
res = req_json("/admin/migrations/run_all", {}, "POST")
print("run_all em %.1fs: ok=%s/%s erro=%s" % (
    time.time() - inicio, res.get("clientes_ok"), res.get("total_clientes"),
    res.get("clientes_com_erro")))
for c in res.get("relatorio") or []:
    print("  - %s (%s): %s aplicadas=%s puladas=%s %sms%s" % (
        c.get("cliente"), c.get("banco"), c.get("status"),
        c.get("aplicadas"), len(c.get("puladas") or []), c.get("duracao_ms"),
        (" ERRO=" + str(c.get("erro"))) if c.get("erro") else ""))

# 4. Confere os bancos
for nome, db in (("Cliente Teste", "exodo_cliente_teste"), (NOME2, DB2)):
    try:
        c = conectar(db)
        with c.cursor() as cur:
            cur.execute("SELECT versao FROM public.schema_migrations ORDER BY versao")
            vs = [r[0] for r in cur.fetchall()]
            cur.execute("SELECT to_regclass('public.ajustes_estoque_lote') IS NOT NULL")
            tabela = cur.fetchone()[0]
        c.close()
        print("%s -> %s (%d) tabela=%s" % (nome, db, len(vs), tabela))
    except Exception as e:
        print("%s -> %s ERRO %s" % (nome, db, e))

# 5. Segunda chamada deve ser no-op
res2 = req_json("/admin/migrations/run_all", {}, "POST")
print("segunda chamada: aplicadas=%s" % [
    (c.get("cliente"), c.get("aplicadas")) for c in res2.get("relatorio") or []])

# -*- coding: utf-8 -*-
"""Corrige o certificado digital da empresa BMJ no banco local e no Supabase.

Motivo: o certificado NOVO (valido ate 13/07/2027, senha 123456) foi carregado
no app, mas os bytes gravados no banco/nuvem ainda eram o certificado ANTIGO e
VENCIDO (29/07/2026) com senha antiga - causando "senha errada" nas maquinas.
"""
import os
import sys
import json
import base64
import hashlib
import urllib.request
import subprocess
import tempfile

BASE = os.path.dirname(os.path.abspath(__file__))
EMPRESA_ID = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"
SENHA = "123456"
PFX_PATH = os.path.join(BASE, "certificado_83fce25b.pfx")

# ---------------------------------------------------------------- .env
env = {}
with open(os.path.join(BASE, ".env"), encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line and "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()

SUPA_URL = env.get("SUPABASE_URL", "").rstrip("/")
SUPA_KEY = (env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SUPABASE_ANON_KEY") or "")
DB_HOST = env.get("DB_HOST", "localhost")
DB_PORT = env.get("DB_PORT", "5432")
DB_NAME = env.get("DB_NAME", "exodo_db")
DB_USER = env.get("DB_USER", "exodo_user")
DB_PASS = env.get("DB_PASSWORD", "")

PSQL = "C:/SistemaExodo/postgresql/bin/psql.exe"

# ---------------------------------------------------------------- cert
if not os.path.exists(PFX_PATH):
    print("ERRO: arquivo do certificado novo nao encontrado:", PFX_PATH)
    sys.exit(1)

with open(PFX_PATH, "rb") as f:
    b64 = base64.b64encode(f.read()).decode("ascii")
print("[1/4] Certificado novo lido:", PFX_PATH, "| base64:", len(b64), "chars")

# ---------------------------------------------------------------- CLOUD
print("[2/4] Atualizando SUPABASE (nuvem)...")
headers = {
    "apikey": SUPA_KEY,
    "Authorization": "Bearer " + SUPA_KEY,
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}

url_get = SUPA_URL + "/rest/v1/empresas?id=eq." + EMPRESA_ID + "&select=configuracoes"
req = urllib.request.Request(url_get, headers={"apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY})
rows = []
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        rows = json.loads(r.read().decode())
except Exception as e:
    print("   ERRO ao buscar config no Supabase:", e)

cfg = {}
if rows:
    cfg = dict(rows[0].get("configuracoes") or {})

cfg["certificadoDigitalBytes"] = b64
cfg["certificadoDigitalSenha"] = SENHA

payload = {
    "configuracoes": cfg,
    "senha_certificado": SENHA,
    "senhaCertificado": SENHA,
    "certificadoDigitalUrl": "base64:pfx:certificado_83fce25b.pfx",
}

url_patch = SUPA_URL + "/rest/v1/empresas?id=eq." + EMPRESA_ID
req = urllib.request.Request(
    url_patch,
    data=json.dumps(payload).encode(),
    headers=headers,
    method="PATCH",
)
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        print("   Supabase PATCH status:", r.status)
except Exception as e:
    print("   ERRO no PATCH Supabase:", e)

# ---------------------------------------------------------------- LOCAL
print("[3/4] Atualizando PostgreSQL LOCAL...")
b64_sql = b64.replace("'", "''")
sql_literal = (
    "UPDATE public.empresas SET\n"
    "  configuracoes = jsonb_set(\n"
    "    jsonb_set(COALESCE(configuracoes, '{}'::jsonb), '{certificadoDigitalBytes}', to_jsonb('" + b64_sql + "'::text)),\n"
    "    '{certificadoDigitalSenha}', to_jsonb('" + SENHA + "'::text)\n"
    "  ),\n"
    "  senha_certificado = '" + SENHA + "',\n"
    '  "senhaCertificado" = \'' + SENHA + "',\n"
    "  updated_at = now()\n"
    "WHERE id = '" + EMPRESA_ID + "';\n"
)
with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as tf:
    sql_file = tf.name
    tf.write(sql_literal)

cmd = [PSQL, "-U", DB_USER, "-d", DB_NAME, "-h", DB_HOST, "-p", DB_PORT, "-f", sql_file]
r = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, "PGPASSWORD": DB_PASS})
print("   psql stdout:", r.stdout.strip()[:300])
print("   psql stderr:", r.stderr.strip()[:300])
print("   psql returncode:", r.returncode)
try:
    os.unlink(sql_file)
except Exception:
    pass

# ---------------------------------------------------------------- VALIDACAO
print("[4/4] VALIDANDO local e nuvem...")
r = subprocess.run(
    [PSQL, "-U", DB_USER, "-d", DB_NAME, "-h", DB_HOST, "-p", DB_PORT, "-A", "-t", "-c",
     "SELECT md5(configuracoes->>'certificadoDigitalBytes'), senha_certificado, configuracoes->>'certificadoDigitalSenha' FROM empresas WHERE id='" + EMPRESA_ID + "';"],
    capture_output=True, text=True, env={**os.environ, "PGPASSWORD": DB_PASS},
)
print("   LOCAL  ->", r.stdout.strip()[:200])

try:
    url_v = SUPA_URL + "/rest/v1/empresas?id=eq." + EMPRESA_ID + "&select=senha_certificado,senhaCertificado,configuracoes,updated_at"
    req = urllib.request.Request(url_v, headers={"apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY})
    with urllib.request.urlopen(req, timeout=30) as rv:
        vrows = json.loads(rv.read().decode())
    for e in vrows:
        c = e.get("configuracoes") or {}
        print("   NUVEM  -> senha_certificado:", repr(e.get("senha_certificado")),
              "| senhaCertificado:", repr(e.get("senhaCertificado")),
              "| certDigitalSenha:", repr(c.get("certificadoDigitalSenha")),
              "| updated_at:", e.get("updated_at"))
        print("   NUVEM cert bytes md5:", hashlib.md5((c.get("certificadoDigitalBytes") or "").encode()).hexdigest())
except Exception as e:
    print("   ERRO validando nuvem:", e)

print("   CERT NOVO esperado md5 base64: 056db4177e337ecc6a717813f4bf5e06")
print("DONE")

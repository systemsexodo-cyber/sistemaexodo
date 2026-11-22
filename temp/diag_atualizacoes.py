"""Diagnostico somente leitura do sistema de atualizacao remota.

Le .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY), consulta a bridge_config
e o bucket `atualizacoes` e imprime o estado. Nao altera nada.
"""
import json
import os
import sys

import requests


def carregar_env(caminho=".env"):
    dados = {}
    with open(caminho, "r", encoding="utf-8", errors="replace") as f:
        for linha in f:
            linha = linha.strip()
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            chave, valor = linha.split("=", 1)
            dados[chave.strip()] = valor.strip().strip('"').strip("'")
    return dados


env = carregar_env()
url = env.get("SUPABASE_URL", "").rstrip("/")
chave = env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SUPABASE_ANON_KEY", "")
if not url or not chave:
    print("Sem SUPABASE_URL/chave no .env")
    sys.exit(1)

print(f"Supabase: {url}")
print(f"Chave usada: {'service_role' if env.get('SUPABASE_SERVICE_ROLE_KEY') else 'anon'}")

headers = {"apikey": chave, "Authorization": f"Bearer {chave}"}

r = requests.get(
    f"{url}/rest/v1/bridge_config",
    headers=headers,
    params={
        "select": "id,version,download_url,ativo,updated_at",
        "or": "(id.eq.app_latest,id.like.app_update_*,id.like.app_client_*,id.eq.latest,id.eq.sync_latest)",
    },
    timeout=20,
)
print(f"\nbridge_config -> HTTP {r.status_code}")
if r.status_code != 200:
    print(r.text[:800])
else:
    linhas = r.json()
    linhas.sort(key=lambda l: (str(l.get("updated_at")), l.get("id", "")))
    for l in linhas:
        vid = l.get("id")
        if vid in ("latest", "sync_latest"):
            print(f"[{vid}] bridge/sync {l.get('version')} ({l.get('updated_at')})")
            continue
        print(
            f"[{vid}] versao={l.get('version')!r} ativo={l.get('ativo')} "
            f"quando={l.get('updated_at')}"
        )
        print(f"    url={l.get('download_url')}")

r2 = requests.post(
    f"{url}/storage/v1/object/list/atualizacoes",
    headers={**headers, "Content-Type": "application/json"},
    data=json.dumps({"prefix": "", "limit": 200, "sortBy": {"column": "name", "order": "asc"}}),
    timeout=20,
)
print(f"\nbucket 'atualizacoes' -> HTTP {r2.status_code}")
if r2.status_code != 200:
    print(r2.text[:500])
else:
    itens = r2.json()
    print(f"{len(itens)} arquivo(s)")
    for it in itens:
        meta = it.get("metadata") or {}
        print(
            f"  {it.get('name')}  {(meta.get('size') or 0) / 1024 / 1024:.2f} MB  "
            f"{meta.get('lastModified') or meta.get('updated_at') or ''}"
        )

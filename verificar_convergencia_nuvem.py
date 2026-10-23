#!/usr/bin/env python3
"""Verifica se local (este PC) e nuvem (Supabase) estao caminhando para ficar iguais.

Somente leitura. Nao altera nada em nenhum banco.

Uso:
    .venv\\Scripts\\python.exe verificar_convergencia_nuvem.py

Mostra:
  1. Estado do REST da nuvem (o que o sincronizador usa por padrao).
  2. Fila de envio local (_exodo_sync_log) e conflitos abertos.
  3. Tabelas que existem so de um lado.
  4. Contagem de linhas local x nuvem nas tabelas comuns.

Leitura da nuvem: usa a conexao direta pelo POOLER (funciona mesmo com o REST
bloqueado por cota). Por isso o item 1 e o que diz se o sync volta a andar.
"""
import os
import sys

import psycopg2
import requests
from dotenv import load_dotenv

BASE = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE, '.env'))

# Carrega .env.neon se existir
env_neon = {}
caminho_neon = os.path.join(BASE, '.env.neon')
if os.path.exists(caminho_neon):
    with open(caminho_neon, 'r', encoding='utf-8-sig', errors='replace') as f:
        for linha in f:
            linha = linha.strip()
            if linha and not linha.startswith('#') and '=' in linha:
                k, _, v = linha.partition('=')
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                env_neon[k] = v

PROVEDOR = (os.getenv('NUVEM_PROVEDOR') or ('neon' if env_neon else 'supabase')).strip().lower()
if '--supabase' in sys.argv:
    PROVEDOR = 'supabase'

LOCAL = dict(
    host=os.getenv('DB_HOST', '127.0.0.1'),
    port=int(os.getenv('DB_PORT', '5432')),
    dbname=os.getenv('DB_NAME', 'exodo_db'),
    user=os.getenv('DB_USER', 'exodo_user'),
    password=os.getenv('DB_PASSWORD'),
)

if PROVEDOR == 'neon':
    dsn_neon = env_neon.get('DATABASE_URL_UNPOOLED') or env_neon.get('DATABASE_URL') or os.getenv('NEON_DATABASE_URL_UNPOOLED') or os.getenv('NEON_DATABASE_URL')
    NUVEM_DSN = dsn_neon
    NUVEM = None
else:
    NUVEM_DSN = None
    NUVEM = dict(
        host=os.getenv('SUPABASE_POOLER_HOST'),
        port=int(os.getenv('SUPABASE_POOLER_PORT', '5432')),
        dbname=os.getenv('SUPABASE_DB_NAME', 'postgres'),
        user=os.getenv('SUPABASE_POOLER_USER') or os.getenv('SUPABASE_DB_USER'),
        password=os.getenv('SUPABASE_POOLER_PASSWORD') or os.getenv('SUPABASE_DB_PASSWORD'),
    )


def estado_rest():
    if PROVEDOR == 'neon':
        url = (env_neon.get('NEON_DATA_API_URL') or os.getenv('NEON_DATA_API_URL') or '').rstrip('/')
        auth_url = (env_neon.get('NEON_AUTH_BASE_URL') or os.getenv('NEON_AUTH_BASE_URL') or '').rstrip('/')
        if not url:
            return 'sem NEON_DATA_API_URL no .env.neon', None
        token = ''
        if auth_url:
            try:
                r_tok = requests.get(f"{auth_url}/token/anonymous", timeout=10)
                if r_tok.status_code < 300:
                    token = r_tok.json().get('token', '')
            except Exception:
                pass
        headers = {'Accept': 'application/json'}
        if token:
            headers['Authorization'] = f'Bearer {token}'
        try:
            r = requests.get(f"{url}/empresas?select=id&limit=1", headers=headers, timeout=15)
        except Exception as e:
            return f'falha de rede: {e}', None
        if r.status_code < 300:
            return f'NEON LIBERADO ({r.status_code}) - sincronização ativa', r.status_code
        return f'NEON RESPOSTA {r.status_code} - {r.text[:120]}', r.status_code

    url = (os.getenv('SUPABASE_URL') or '').rstrip('/')
    key = os.getenv('SUPABASE_ANON_KEY')
    if not url or not key:
        return 'sem SUPABASE_URL/ANON_KEY no .env', None
    try:
        r = requests.get(f"{url}/rest/v1/empresas?select=id&limit=1",
                         headers={'apikey': key, 'Authorization': f'Bearer {key}'}, timeout=15)
    except Exception as e:
        return f'falha de rede: {e}', None
    if r.status_code < 300:
        return 'LIBERADO - o sincronizador vai escoar a fila sozinho', r.status_code
    msg = ''
    try:
        msg = r.json().get('message', '')
    except Exception:
        msg = r.text[:120]
    return f'BLOQUEADO - {msg}', r.status_code


def tabelas(conn):
    with conn.cursor() as cur:
        cur.execute("""SELECT table_name FROM information_schema.tables
                       WHERE table_schema='public' AND table_type='BASE TABLE'
                       ORDER BY table_name""")
        return {r[0] for r in cur.fetchall()}


def colunas(conn, t):
    with conn.cursor() as cur:
        cur.execute("""SELECT column_name FROM information_schema.columns
                       WHERE table_schema='public' AND table_name=%s""", (t,))
        return {r[0] for r in cur.fetchall()}


def conta(conn, t):
    try:
        with conn.cursor() as cur:
            cur.execute(f'SELECT count(*) FROM public."{t}"')
            return cur.fetchone()[0]
    except Exception as e:
        conn.rollback()
        return f'ERRO'


def main():
    print("=" * 68)
    texto, status = estado_rest()
    print(f"1) NUVEM (REST) : {texto}")

    try:
        cl = psycopg2.connect(**LOCAL)
    except Exception as e:
        print(f"2) LOCAL: nao conectou - {e}")
        return 2
    cur = cl.cursor()
    cur.execute("SELECT count(*) FROM _exodo_sync_log")
    fila = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM exodo_sync_conflitos WHERE resolvido = FALSE")
    conflitos = cur.fetchone()[0]
    cur.execute("""SELECT table_name, count(*) FROM _exodo_sync_log
                   GROUP BY table_name ORDER BY 2 DESC LIMIT 8""")
    top = cur.fetchall()
    print(f"2) FILA DE ENVIO: {fila} pendencia(s) | CONFLITOS abertos: {conflitos}")
    for t, n in top:
        print(f"     {t:<28} {n}")
    if fila == 0 and conflitos == 0 and status and status < 300:
        print("   -> Nada pendente. Local e nuvem devem estar iguais (veja item 4).")

    try:
        if NUVEM_DSN:
            cn = psycopg2.connect(NUVEM_DSN)
        else:
            cn = psycopg2.connect(**NUVEM)
    except Exception as e:
        print(f"3) NUVEM (direto): nao conectou - {e}")
        return 2

    tl, tn = tabelas(cl), tabelas(cn)
    print(f"\n3) TABELAS: local={len(tl)} | nuvem={len(tn)}")
    if tl - tn:
        print(f"   so no local: {sorted(tl - tn)}")
    if tn - tl:
        print(f"   so na nuvem: {sorted(tn - tl)}")

    print("\n4) CONTAGEM POR TABELA (comum)  -- marca = difere")
    divergentes = []
    for t in sorted(tl & tn):
        a, b = conta(cl, t), conta(cn, t)
        marca = ''
        if isinstance(a, int) and isinstance(b, int) and a != b:
            marca = '  <-- difere'
            divergentes.append(t)
        if marca:
            print(f"   {t:<32} local={str(a):>7}  nuvem={str(b):>7}{marca}")

    iguais = len(tl & tn) - len(divergentes)
    print(f"\n   {iguais} tabela(s) iguais, {len(divergentes)} diferente(s).")
    if divergentes:
        print(f"   Diferentes: {', '.join(divergentes)}")
    cl.close()
    cn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())

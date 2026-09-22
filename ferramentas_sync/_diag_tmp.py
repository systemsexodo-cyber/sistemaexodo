#!/usr/bin/env python3
# Diagnostico pontual: schema local x nuvem + busca produtos 29/37
import os, json, ssl, sys
from collections import defaultdict

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv
load_dotenv('.env')
import psycopg2
from psycopg2.extras import RealDictCursor

LOCAL = dict(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    dbname=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD'),
)
NUVEM = dict(
    host=os.getenv('SUPABASE_POOLER_HOST'),
    port=int(os.getenv('SUPABASE_POOLER_PORT', '5432')),
    dbname=os.getenv('SUPABASE_DB_NAME', 'postgres'),
    user=os.getenv('SUPABASE_POOLER_USER'),
    password=os.getenv('SUPABASE_POOLER_PASSWORD'),
    sslmode='require',
)

SKIP = {'_exodo_sync_log', '_sync_controle', 'cache_dados'}

def conectar(cfg, nome):
    print(f'\n=== Conectando {nome}: {cfg["user"]}@{cfg["host"]}:{cfg["port"]}/{cfg["dbname"]} ===')
    try:
        conn = psycopg2.connect(**cfg, connect_timeout=20)
        conn.set_session(readonly=True, autocommit=True)
        print(f'OK {nome}')
        return conn
    except Exception as e:
        print(f'FALHA {nome}: {e}')
        return None

def tabelas(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema='public' AND table_type='BASE TABLE'
            ORDER BY table_name
        """)
        return [r[0] for r in cur.fetchall()]

def colunas(conn, tabela):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema='public' AND table_name=%s
            ORDER BY ordinal_position
        """, (tabela,))
        return {r[0]: {'tipo': r[1], 'null': r[2], 'default': r[3]} for r in cur.fetchall()}

def count(conn, tabela):
    try:
        with conn.cursor() as cur:
            cur.execute(f'SELECT COUNT(*) FROM "{tabela}"')
            return cur.fetchone()[0]
    except Exception as e:
        return f'ERR:{e}'

def buscar_produtos(conn, origem):
    print(f'\n--- Produtos 29/37 em {origem} ---')
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        # schema produtos
        cur.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_schema='public' AND table_name='produtos'
        """)
        cols = [r['column_name'] for r in cur.fetchall()]
        print(f'  colunas produtos ({len(cols)}): {", ".join(cols[:40])}{"..." if len(cols)>40 else ""}')
        if not cols:
            print('  TABELA produtos NAO EXISTE')
            return

        cur.execute('SELECT COUNT(*) AS n FROM produtos')
        print(f'  total produtos: {cur.fetchone()["n"]}')

        # listar alguns códigos para entender formato
        if 'codigo' in cols:
            cur.execute("""
                SELECT id, codigo, nome, empresa_id
                FROM produtos
                ORDER BY CASE WHEN codigo ~ '^[0-9]+$' THEN codigo::int ELSE 999999 END, codigo
                LIMIT 50
            """)
            print('  primeiros 50 por codigo numerico:')
            for r in cur.fetchall():
                print(f"    codigo={r.get('codigo')!r} id={r.get('id')!r} nome={r.get('nome')!r} emp={r.get('empresa_id')!r}")

        # busca direta
        wheres = []
        params = []
        for campo in ('id', 'codigo', 'codigo_barras'):
            if campo in cols:
                wheres.append(f"CAST({campo} AS TEXT) IN ('29','37','0029','0037','00029','00037')")
                wheres.append(f"CAST({campo} AS TEXT) LIKE '%%29%%'")  # too broad? keep separate
        # precise
        sql = """
            SELECT * FROM produtos
            WHERE CAST(id AS TEXT) IN ('29','37')
               OR CAST(codigo AS TEXT) IN ('29','37','0029','0037','00029','00037')
        """
        if 'codigo_barras' in cols:
            sql += " OR CAST(codigo_barras AS TEXT) IN ('29','37')"
        try:
            cur.execute(sql)
            rows = cur.fetchall()
            print(f'  match exato id/codigo 29/37: {len(rows)}')
            for r in rows:
                print('   ', {k: r[k] for k in list(r)[:12]})
        except Exception as e:
            print('  erro busca exata:', e)
            conn.rollback() if not conn.autocommit else None

        # gaps numericos
        if 'codigo' in cols:
            try:
                cur.execute("""
                    SELECT codigo FROM produtos
                    WHERE codigo ~ '^[0-9]+$'
                    ORDER BY codigo::int
                """)
                nums = [int(r['codigo']) for r in cur.fetchall()]
                print(f'  codigos numericos: {len(nums)} (min={nums[0] if nums else None} max={nums[-1] if nums else None})')
                for alvo in (29, 37):
                    print(f'  codigo {alvo} presente? {alvo in nums}')
                if nums:
                    s = set(nums)
                    faltando = [i for i in range(min(nums), min(max(nums), 80)+1) if i not in s]
                    print(f'  gaps ate 80: {faltando}')
            except Exception as e:
                print('  erro gaps:', e)

        # historico
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema='public' AND table_name IN
              ('produto_historico','estoque_historico','historico_produto','lotes_produto')
        """)
        hist_tabs = [r['table_name'] for r in cur.fetchall()]
        for t in hist_tabs:
            cur.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_schema='public' AND table_name=%s
            """, (t,))
            hcols = [r['column_name'] for r in cur.fetchall()]
            conds = []
            if 'produto_id' in hcols:
                conds.append("CAST(produto_id AS TEXT) IN ('29','37')")
            if 'produto_codigo' in hcols:
                conds.append("CAST(produto_codigo AS TEXT) IN ('29','37','0029','0037')")
            if 'codigo' in hcols:
                conds.append("CAST(codigo AS TEXT) IN ('29','37')")
            print(f'  {t} cols={hcols[:15]}')
            if conds:
                try:
                    cur.execute(f'SELECT COUNT(*) AS n FROM "{t}" WHERE {" OR ".join(conds)}')
                    print(f'    matches 29/37: {cur.fetchone()["n"]}')
                    cur.execute(f'SELECT * FROM "{t}" WHERE {" OR ".join(conds)} LIMIT 5')
                    for r in cur.fetchall():
                        print('     ', {k: str(r[k])[:80] for k in list(r)[:10]})
                except Exception as e:
                    print('    erro', e)

        # vendas / pedidos JSON
        for t in ('vendas_balcao', 'pedidos', 'itens_pedido', 'itens_venda'):
            cur.execute("""
                SELECT EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema='public' AND table_name=%s)
            """, (t,))
            if not cur.fetchone()[0]:
                continue
            cur.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_schema='public' AND table_name=%s
            """, (t,))
            tcols = [r['column_name'] for r in cur.fetchall()]
            print(f'  {t} existe, cols={tcols[:20]}')
            try:
                if 'itens' in tcols:
                    cur.execute(f"""
                        SELECT id, itens::text FROM "{t}"
                        WHERE itens::text LIKE '%%"codigo": "29"%%'
                           OR itens::text LIKE '%%"codigo":"29"%%'
                           OR itens::text LIKE '%%"codigo": "37"%%'
                           OR itens::text LIKE '%%"codigo":"37"%%'
                           OR itens::text LIKE '%%"produtoCodigo": "29"%%'
                           OR itens::text LIKE '%%"codigo": 29%%'
                           OR itens::text LIKE '%%"codigo": 37%%'
                        LIMIT 8
                    """)
                    hits = cur.fetchall()
                    print(f'    itens JSON com codigo 29/37: {len(hits)}')
                    for r in hits:
                        txt = r['itens'] if isinstance(r, dict) else r[1]
                        print(f'      venda {r["id"] if isinstance(r, dict) else r[0]} trecho={str(txt)[:200]}')
            except Exception as e:
                print(f'    erro json {t}: {e}')

def empresas(conn, origem):
    print(f'\n--- Empresas {origem} ---')
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute('SELECT id, razao_social, nome_fantasia, cnpj FROM empresas')
            for r in cur.fetchall():
                print(' ', dict(r))
    except Exception as e:
        print('  erro', e)

def main():
    local = conectar(LOCAL, 'LOCAL')
    nuvem = conectar(NUVEM, 'NUVEM')

    tabs_l = tabelas(local) if local else []
    tabs_n = tabelas(nuvem) if nuvem else []
    set_l, set_n = set(tabs_l), set(tabs_n)

    print('\n========== TABELAS ==========')
    print(f'Local: {len(tabs_l)}  Nuvem: {len(tabs_n)}')
    so_local = sorted(set_l - set_n)
    so_nuvem = sorted(set_n - set_l)
    comuns = sorted(set_l & set_n)
    print(f'Só no LOCAL ({len(so_local)}): {so_local}')
    print(f'Só na NUVEM ({len(so_nuvem)}): {so_nuvem}')

    print('\n========== CONTAGENS (comuns) ==========')
    diffs = []
    for t in comuns:
        if t in SKIP or t.startswith('_') or t.startswith('vw_'):
            continue
        cl = count(local, t) if local else None
        cn = count(nuvem, t) if nuvem else None
        mark = ' <DIFF>' if cl != cn else ''
        if cl != cn:
            diffs.append((t, cl, cn))
        print(f'  {t:40} local={str(cl):>8}  nuvem={str(cn):>8}{mark}')

    print('\n========== COLUNAS DIVERGENTES ==========')
    for t in comuns:
        if t.startswith('_'):
            continue
        cl = colunas(local, t) if local else {}
        cn = colunas(nuvem, t) if nuvem else {}
        sl, sn = set(cl), set(cn)
        only_l = sorted(sl - sn)
        only_n = sorted(sn - sl)
        if only_l or only_n:
            print(f'  {t}:')
            if only_l:
                print(f'    só local ({len(only_l)}): {only_l}')
            if only_n:
                print(f'    só nuvem ({len(only_n)}): {only_n}')

    if local:
        empresas(local, 'LOCAL')
        buscar_produtos(local, 'LOCAL')
    if nuvem:
        empresas(nuvem, 'NUVEM')
        buscar_produtos(nuvem, 'NUVEM')

    # sync log
    if local:
        print('\n--- Fila _exodo_sync_log ---')
        try:
            with local.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT table_name, operation, COUNT(*) n
                    FROM _exodo_sync_log GROUP BY 1,2 ORDER BY n DESC
                """)
                rows = cur.fetchall()
                if not rows:
                    print('  vazia')
                for r in rows:
                    print(f"  {r['table_name']} {r['operation']}: {r['n']}")
        except Exception as e:
            print('  ', e)

        print('\n--- _sync_controle (amostra) ---')
        try:
            with local.cursor() as cur:
                cur.execute('SELECT chave, valor FROM _sync_controle ORDER BY chave')
                for k, v in cur.fetchall():
                    print(f'  {k} = {str(v)[:80]}')
        except Exception as e:
            print('  ', e)

        print('\n--- cache_dados empresa ativa ---')
        try:
            with local.cursor() as cur:
                cur.execute("SELECT chave, valor_json FROM cache_dados WHERE chave LIKE 'exodo_%'")
                for r in cur.fetchall():
                    print(' ', r)
        except Exception as e:
            print('  ', e)

    print('\n========== RESUMO DIFFS CONTAGEM ==========')
    for t, cl, cn in diffs:
        print(f'  {t}: local={cl} nuvem={cn} delta={ (cn if isinstance(cn,int) else 0) - (cl if isinstance(cl,int) else 0) }')

    for c in (local, nuvem):
        if c:
            c.close()

if __name__ == '__main__':
    main()

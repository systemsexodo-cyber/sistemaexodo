#!/usr/bin/env python3
"""Compara dois bancos Exodo (o local e um PC da rede local) e diz onde divergem.

A LAN só substitui a cópia antiga pela nova se ela enxergar a divergência. Com a
nuvem fora (HTTP 402), o ciclo roda sozinho entre os dois PCs e este relatório é
o que diz se os dois bancos chegaram no mesmo estado.

Uso:
    PGPASSWORD='...' .venv/Scripts/python.exe comparar_bancos.py [host_par]
"""
import os
import sys

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

BASE = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE, '.env'))

LOCAL = dict(
    host=os.getenv('DB_HOST', '127.0.0.1'),
    port=int(os.getenv('DB_PORT', '5432')),
    dbname=os.getenv('DB_NAME', 'exodo_db'),
    user=os.getenv('DB_USER', 'exodo_user'),
    password=os.getenv('DB_PASSWORD'),
)
PAR = dict(LOCAL, host=sys.argv[1] if len(sys.argv) > 1 else '192.168.0.117')

# Tabelas que a LAN realmente sincroniza entre os PCs.
TABELAS = [
    'empresas', 'departamentos', 'produtos', 'categorias', 'estoques',
    'clientes', 'fornecedores', 'formas_pagamento', 'vendas_balcao', 'pedidos',
]

# Colunas que NUNCA devem ser comparadas (temporais/máquina).
IGNORAR = {'updated_at', 'created_at', 'sincronizado_nuvem', 'id_sincronizacao',
          'empresa_id', 'sync', 'perfis_de_preco', 'perfisDePreco',
          'updatedAt', 'createdAt', 'sincronizadoNuvem', 'idSincronizacao'}


def conecta(cfg):
    return psycopg2.connect(**cfg)


def tabelas_de(conn,tabela):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_schema='public' AND table_name=%s
        """, (tabela,))
        return [r[0] for r in cur.fetchall()]


def linhas(conn, tabela, cols):
    sql = 'SELECT ' + ','.join('"%s"' % c for c in cols) + f' FROM "{tabela}"'
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql)
        return {str(r['id']): dict(r) for r in cur.fetchall()}


def main():
    c1, c2 = conecta(LOCAL), conecta(PAR)
    divergencias = []
    for tabela in TABELAS:
        try:
            # Os dois bancos NÃO têm exatamente o mesmo schema (uma versão do
            # app pode ter criado colunas que a outra não tem). Comparar só as
            # colunas COMUNS evita o erro "coluna não existe" e ainda aponta a
            # divergência que importa.
            c1.rollback()
            c2.rollback()
            cols1 = tabelas_de(c1, tabela)
            cols2 = tabelas_de(c2, tabela)
            if not cols1 or not cols2:
                print(f'  [pular] {tabela}: tabela não existe em um dos bancos')
                continue
            so_no_schema_local = sorted(set(cols1) - set(cols2))
            so_no_schema_par = sorted(set(cols2) - set(cols1))
            comuns = set(cols1) & set(cols2)
            cols = [c for c in cols1 if c in comuns and c not in IGNORAR]
            if not cols:
                print(f'  [pular] {tabela}: nenhuma coluna em comum')
                continue
            a = linhas(c1, tabela, cols)
            b = linhas(c2, tabela, cols)
        except Exception as e:
            # Uma consulta que falha aborta a transação: as próximas respostas
            # seriam "transação interrompida" e TODA a comparação mentiria.
            c1.rollback()
            c2.rollback()
            print(f'  [pular] {tabela}: {str(e).splitlines()[0]}')
            continue

        so_a = set(a) - set(b)
        so_b = set(b) - set(a)
        comum = set(a) & set(b)
        dif = []
        for rid in comum:
            for c in cols:
                if a[rid].get(c) != b[rid].get(c):
                    dif.append((rid, c, a[rid].get(c), b[rid].get(c)))

        if so_a or so_b or dif:
            divergencias.append(tabela)
            print(f'\n### {tabela}: so_no_local={len(so_a)} so_no_par={len(so_b)} '
                  f'diferentes={len(dif)}')
            if so_no_schema_local or so_no_schema_par:
                print(f'  [schema] só no local: {so_no_schema_local}')
                print(f'  [schema] só no par:   {so_no_schema_par}')
            for rid, c, va, vb in dif[:30]:
                print(f'  id={rid} {c}: local={va!r} par={vb!r}')
            for rid in list(so_a)[:10]:
                print(f'  SO LOCAL: {rid}')
            for rid in list(so_b)[:10]:
                print(f'  SO PAR:   {rid}')

    if not divergencias:
        print('\nBancos IGUAIS nas tabelas comparadas.')
    else:
        print('\nTabelas divergentes: ' + ', '.join(divergencias))
    return 0


if __name__ == '__main__':
    sys.exit(main())

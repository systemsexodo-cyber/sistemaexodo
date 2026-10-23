#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A nuvem só sobrescreve o local quando é MAIS NOVA.

Duas garantias que faltavam e explicam os dois sintomas relatados:

  1. "a nuvem parou e sobrescreveu o banco local": o download fazia
     `ON CONFLICT DO UPDATE` sem olhar a data. Uma cópia velha (nuvem parada,
     restaurada de backup) passava por cima de uma linha local mais nova.
     Agora o UPDATE só acontece quando `EXCLUDED.updated_at` é estritamente
     maior que o `updated_at` local.

  2. "altero no site e o app local não muda": conflitos abertos bloqueiam o
     download daquele registro para sempre. Muitos deles eram FALSOS: a versão
     local tinha `10.0` e a da nuvem `10` (ou o mesmo instante em formatos
     diferentes), e a comparação por texto parqueava um conflito que não
     existia. Agora a comparação é por valor e os conflitos sem diferença real
     são fechados automaticamente.

Roda sem banco e sem rede:
    .venv\\Scripts\\python.exe test_nuvem_nao_sobrescreve_local.py
"""
import sys

sys.path.insert(0, '.')
import sincronizar_local_supabase as S  # noqa: E402

FALHOU = []


def checa(condicao, descricao):
    if condicao:
        print('  [ok] %s' % descricao)
    else:
        print('  [FALHOU] %s' % descricao)
        FALHOU.append(descricao)


# ─────────────────────────── dublês ───────────────────────────

class FakeCursor:
    def __init__(self, conn):
        self.conn = conn
        self.rowcount = -1

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql, params=None):
        self.conn.sqls.append((' '.join(sql.split()), params))
        if 'information_schema' in sql:
            self.rowcount = -1
            return
        if sql.strip().upper().startswith('SET LOCAL'):
            self.rowcount = -1
            return
        if sql.strip().upper().startswith('INSERT INTO'):
            # P1 é a cópia velha (rowcount 0 = guarda barrou); P2 é mais nova.
            primeiro = params[0] if params else None
            self.rowcount = 0 if primeiro == 'P1' else 1
            self.conn.aplicados_tentados.append(primeiro)
            return
        if sql.strip().upper().startswith('UPDATE exodo_sync_conflitos'):
            self.rowcount = len(params[0]) if params else 0
            return
        if sql.strip().upper().startswith('SELECT id, tabela'):
            self.rowcount = len(self.conn.conflitos)
            return
        self.rowcount = 1

    def fetchall(self):
        return self.conn.conflitos

    def fetchone(self):
        return None


class FakeConn:
    def __init__(self, conflitos=None):
        self.sqls = []
        self.aplicados_tentados = []
        self.conflitos = conflitos or []
        self.commits = 0
        self.rollbacks = 0

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


COLUNAS_PRODUTO = {
    'id': 'TEXT',
    'nome': 'TEXT',
    'preco': 'NUMERIC',
    'empresa_id': 'TEXT',
    'updated_at': 'TIMESTAMP WITH TIME ZONE',
}


# ─────────────────────────── casos ───────────────────────────

def caso_1_comparacao_por_valor():
    print('1) comparação de valores: número e data, não texto')
    checa(S._valores_equivalentes('10.0', '10'),
          '10.0 (local) e 10 (nuvem) são o MESMO valor')
    checa(S._valores_equivalentes(
         '2026-10-20 07:56:18.461187-03:00',
         '2026-10-20T10:56:18.461187+00:00'),
         'o mesmo instante em formatos diferentes é equivalente')
    checa(not S._valores_equivalentes('10.00', '11.00'),
          'valores realmente diferentes continuam diferentes')
    checa(not S._valores_equivalentes('Pago', 'Cancelado'),
          'status diferente continua diferente')
    checa(S._valores_equivalentes({'total': 10.0}, {'total': '10'}),
          'número dentro de JSON também é comparado por valor')


def caso_2_guarda_de_versao_no_sql():
    print('2) download usa a versão: nuvem velha NÃO sobrescreve a local')
    original = S.get_colunas_e_tipos_tabela
    S.get_colunas_e_tipos_tabela = lambda conn, tabela: dict(COLUNAS_PRODUTO)
    try:
        conn = FakeConn()
        rows = [
            {'id': 'P1', 'nome': 'coca velha', 'preco': 9,
             'empresa_id': 'E1',
             'updated_at': '2026-10-20T10:00:00+00:00'},
            {'id': 'P2', 'nome': 'agua nova', 'preco': 2,
             'empresa_id': 'E1',
             'updated_at': '2026-10-21T10:00:00+00:00'},
        ]
        importados, aplicados = S.gravar_registros_locais(
            conn, 'produtos', rows, empresa_filtro='E1', bloqueados={})

        checa(importados == 1,
              f'só 1 registro entrou (veio {importados})')
        checa(aplicados == ['P2'],
              f'só o registro mais novo foi aplicado (veio {aplicados})')
        checa(conn.aplicados_tentados == ['P1', 'P2'],
              'os dois foram tentados; a guarda barrou o velho')

        upserts = [s for s in conn.sqls if s[0].startswith('INSERT INTO "produtos"')]
        checa(len(upserts) == 2, f'2 upserts montados (veio {len(upserts)})')
        if upserts:
            sql = upserts[0][0]
            checa('EXCLUDED."updated_at" > "produtos"."updated_at"' in sql,
                  'o SQL compara updated_at (nuvem mais nova vence)')
            checa('"produtos"."empresa_id" = EXCLUDED."empresa_id"' in sql,
                  'a trava de empresa continua no mesmo WHERE')

        # Várias tabelas guardam updated_at como TEXTO (nfces, entregas...).
        # A guarda também precisa valer para elas, com cast protegido.
        cond_texto = S._condicao_versao_sql('nfces', 'updated_at', 'TEXT')
        checa('::timestamptz' in cond_texto,
              'coluna de versão em texto é comparada como data')
        checa('EXCLUDED."updated_at"' in cond_texto,
              'a versão da nuvem entra na comparação também no texto')
    finally:
        S.get_colunas_e_tipos_tabela = original


def caso_3_conflito_falso_e_fechado():
    print('3) conflito sem diferença real é fechado; o real continua aberto')
    original_cache = S._tem_tabela_conflitos_cache
    S._tem_tabela_conflitos_cache = True
    try:
        conn = FakeConn(conflitos=[
            {
                'id': 'c1',
                'tabela': 'pedidos',
                'registro_id': 'PED-1',
                'dados_locais': {'id': 'PED-1', 'status': 'Pago', 'total': 10.0,
                                 'updated_at': '2026-10-20 07:56:18-03:00'},
                'dados_nuvem': {'id': 'PED-1', 'status': 'Pago', 'total': 10,
                                'updated_at': '2026-10-20T10:56:37+00:00'},
            },
            {
                'id': 'c2',
                'tabela': 'pedidos',
                'registro_id': 'PED-2',
                'dados_locais': {'id': 'PED-2', 'status': 'Pago'},
                'dados_nuvem': {'id': 'PED-2', 'status': 'Cancelado'},
            },
        ])
        fechados = S.fechar_conflitos_identicos(conn)

        checa(fechados == 1, f'1 conflito falso fechado (veio {fechados})')
        updates = [p for s, p in conn.sqls
                   if s.startswith('UPDATE exodo_sync_conflitos')]
        checa(bool(updates), 'rodou o UPDATE dos conflitos idênticos')
        if updates:
            checa(list(updates[0][0]) == ['c1'],
                  f'só o conflito falso foi fechado (veio {updates[0][0]})')
    finally:
        S._tem_tabela_conflitos_cache = original_cache


def caso_4_regra_independe_do_provedor():
    print('4) a regra vale para NEON e para o SUPABASE LOCAL (mesmo caminho)')
    original_colunas = S.get_colunas_e_tipos_tabela
    original_provedor = S.NUVEM_PROVEDOR
    S.get_colunas_e_tipos_tabela = lambda conn, tabela: dict(COLUNAS_PRODUTO)
    try:
        for provedor in ('neon', 'supabase'):
            S.NUVEM_PROVEDOR = provedor
            conn = FakeConn()
            rows = [
                {'id': 'P1', 'nome': 'coca velha', 'preco': 9,
                 'empresa_id': 'E1',
                 'updated_at': '2026-10-20T10:00:00+00:00'},
                {'id': 'P2', 'nome': 'agua nova', 'preco': 2,
                 'empresa_id': 'E1',
                 'updated_at': '2026-10-21T10:00:00+00:00'},
            ]
            importados, aplicados = S.gravar_registros_locais(
                conn, 'produtos', rows, empresa_filtro='E1', bloqueados={})
            checa(importados == 1 and aplicados == ['P2'],
                  f'{provedor}: a copia velha continua barrada e a nova entra')
            upserts = [s for s in conn.sqls
                       if s[0].startswith('INSERT INTO "produtos"')]
            checa(bool(upserts) and
                  'EXCLUDED."updated_at" > "produtos"."updated_at"' in upserts[0][0],
                  f'{provedor}: o SQL leva a guarda de updated_at')
    finally:
        S.get_colunas_e_tipos_tabela = original_colunas
        S.NUVEM_PROVEDOR = original_provedor

    checa(S._coluna_de_versao({'updated_at': 'TIMESTAMP WITH TIME ZONE'})[0]
          == 'updated_at',
          'a coluna de versao e detectada pelo TIPO, sem olhar provedor')


def caso_5_produto_do_site_chega_e_avisa_a_tela():
    print('5) delta rapido de produtos grava e avisa o app (exodo_ui_event)')
    originais = {
        'fetch_updates_tabela': S.fetch_updates_tabela,
        'get_ultima_sync_tabela': S.get_ultima_sync_tabela,
        'salvar_ultima_sync_tabela': S.salvar_ultima_sync_tabela,
        'ids_bloqueados_no_download': S.ids_bloqueados_no_download,
        'nuvem_bloqueada': S.nuvem_bloqueada,
        'carregar_meta_colunas': S.carregar_meta_colunas,
        'get_colunas_e_tipos_tabela': S.get_colunas_e_tipos_tabela,
        '_colunas_e_tipos_cache': S._colunas_e_tipos_cache,
    }
    cursor_salvo = []
    try:
        S._colunas_e_tipos_cache = {}
        S.carregar_meta_colunas = lambda conn: None
        S.get_colunas_e_tipos_tabela = lambda conn, tabela: dict(COLUNAS_PRODUTO)
        S.get_ultima_sync_tabela = lambda conn, tabela, empresa=None: \
            '2026-10-20T00:00:00+00:00'
        S.salvar_ultima_sync_tabela = lambda conn, tabela, ts, empresa=None: \
            cursor_salvo.append((tabela, ts))
        S.ids_bloqueados_no_download = lambda conn: {}
        S.nuvem_bloqueada = lambda: False
        S.fetch_updates_tabela = lambda tabela, desde, url, key, empresa=None: (
            tabela,
            [{'id': 'P9', 'nome': 'produto alterado no site', 'preco': 12,
              'empresa_id': 'E1',
              'updated_at': '2026-10-21T12:00:00+00:00'}],
            True, False)

        conn = FakeConn()
        recebidos = S.sincronizar_produtos_rapido(
            conn, 'http://nuvem', 'chave', 'E1')

        checa(recebidos == 1, f'o produto do site foi aplicado (veio {recebidos})')
        checa(bool(cursor_salvo) and cursor_salvo[0][0] == 'produtos',
              'o cursor de produtos avancou')
        avisos = [p for s, p in conn.sqls
                  if s.startswith('SELECT pg_notify')]
        checa(avisos == [('exodo_ui_event', 'produtos')],
              f'o app foi avisado UMA vez pelo canal certo (veio {avisos})')
    finally:
        for nome, valor in originais.items():
            setattr(S, nome, valor)


def caso_6_cursor_com_folga_de_relogio():
    print('6) o cursor do delta recua alguns segundos (relogio do PC x nuvem)')
    # O cursor e gravado com o relogio DESTE PC; o updated_at vem do relogio da
    # nuvem. Ja vimos ~0,5 s de diferenca: uma alteracao feita logo depois de um
    # ciclo ficava com carimbo ANTERIOR ao cursor e nunca mais era baixada.
    cursor = '2026-10-21T12:29:58.300000+00:00'
    folga = S._desde_com_folga(cursor)
    checa(folga < cursor, f'o delta volta no tempo (veio {folga})')
    import datetime as _dt
    atraso = (_dt.datetime.fromisoformat(cursor)
              - _dt.datetime.fromisoformat(folga)).total_seconds()
    checa(atraso >= 60, f'folga suficiente para o desvio de relogio ({atraso:.0f}s)')
    checa(S._desde_com_folga('2026-10-21T12:29:58Z') <
          '2026-10-21T12:29:58+00:00', 'cursor com Z tambem e recuado')
    checa(S._desde_com_folga(None) is None, 'sem cursor continua None')
    checa(S._desde_com_folga('lixo') == 'lixo', 'cursor invalido nao derruba o ciclo')


def main():
    print('=' * 60)
    print('Nuvem só sobrescreve o local quando é MAIS NOVA')
    print('=' * 60)
    caso_1_comparacao_por_valor()
    caso_2_guarda_de_versao_no_sql()
    caso_3_conflito_falso_e_fechado()
    caso_4_regra_independe_do_provedor()
    caso_5_produto_do_site_chega_e_avisa_a_tela()
    caso_6_cursor_com_folga_de_relogio()
    print('-' * 60)
    if FALHOU:
        print('%d VERIFICAÇÃO(ÕES) FALHARAM' % len(FALHOU))
        for f in FALHOU:
            print('   - %s' % f)
        return 1
    print('TODAS AS VERIFICAÇÕES PASSARAM')
    return 0


if __name__ == '__main__':
    sys.exit(main())

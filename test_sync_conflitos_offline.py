#!/usr/bin/env python3
"""
Testes do sincronizador: conflito nunca é silencioso e nada se perde.

Roda sem banco e sem rede — as conexões e as chamadas HTTP são substituídas por
objetos de mentira que registram o que o sincronizador tentou fazer. É o que
precisa ser verdade para dois bancos locais (duas máquinas) não se atropelarem
quando um fica sem internet:

  1. DOWNLOAD: registro com alteração local pendente ou conflito aberto NÃO é
     sobrescrito pela nuvem;
  2. UPLOAD: quando o outro PC alterou o mesmo registro, o conflito é parqueado
     (resolvido = FALSE) e o log local continua pendente — nada é descartado;
  3. a lista de bloqueados junta os dois motivos (pendente + conflito).

Rodar: .venv\\Scripts\\python.exe test_sync_conflitos_offline.py
"""
import sys
import types
from datetime import datetime, timezone

sys.path.insert(0, '.')
import sincronizar_local_supabase as S  # noqa: E402


# ─────────────────────────── Dublês de conexão ───────────────────────────

class FakeCursor:
    """Cursor de mentira: devolve respostas roteirizadas e guarda os SQL."""

    def __init__(self, conn):
        self.conn = conn
        self.rowcount = 0

    # -- roteiro ---------------------------------------------------------
    # A fila de respostas é do CONN, não do cursor: o código cria um cursor por
    # consulta (`with conn.cursor() as cur`) e a ordem tem que ser a das
    # consultas, não a dos cursores.
    def proxima(self):
        return self.conn._respostas.pop(0) if self.conn._respostas else None

    # -- API do cursor ---------------------------------------------------
    def execute(self, sql, params=None):
        self.conn.sqls.append((' '.join(sql.split()), params))
        self.rowcount = 1
        self._ultimo = self.proxima()

    def executemany(self, sql, seq):
        for p in seq:
            self.execute(sql, p)

    def fetchone(self):
        return self._ultimo

    def fetchall(self):
        return self._ultimo or []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FakeConn:
    def __init__(self, respostas=None):
        self.sqls = []
        self.commits = 0
        self.rollbacks = 0
        self.cursor_factory = None
        self._respostas = respostas or []

    def cursor(self, cursor_factory=None):
        self.cursor_factory = cursor_factory
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


COLUNAS_PRODUTO = {
    'id': 'TEXT',
    'nome': 'TEXT',
    'estoque': 'NUMERIC',
    'preco': 'NUMERIC',
    'empresa_id': 'TEXT',
    'updated_at': 'TIMESTAMP WITH TIME ZONE',
}


def montar_sqls(conn):
    return [sql for sql, _ in conn.sqls]


def falhas(mensagem):
    # Sem emoji de propósito: o console do Windows (cp1252) não encoda todos.
    print(f"  [FALHOU] {mensagem}")
    return False


# ─────────────────────────────── Testes ───────────────────────────────

def teste_download_nao_sobrescreve_pendente():
    """A nuvem não pode apagar a alteração local que ainda não subiu."""
    print('1) download respeita alteração local pendente / conflito aberto')

    original = S.get_colunas_e_tipos_tabela
    S.get_colunas_e_tipos_tabela = lambda conn, tabela: dict(COLUNAS_PRODUTO)
    try:
        conn = FakeConn()
        rows = [
            {'id': 'P1', 'nome': 'coca cola', 'estoque': 33, 'empresa_id': 'E1',
             'updated_at': '2026-09-29T10:00:00+00:00'},
            {'id': 'P2', 'nome': 'agua', 'estoque': 10, 'empresa_id': 'E1',
             'updated_at': '2026-09-29T10:00:00+00:00'},
        ]
        importados, _aplicados = S.gravar_registros_locais(
            conn, 'produtos', rows,
            empresa_filtro='E1',
            bloqueados={'produtos': {'P1': 'conflito_aberto'}},
        )

        if importados != 1:
            return falhas(f'esperava 1 registro importado, veio {importados}')

        inserts = [s for s in montar_sqls(conn) if s.startswith('INSERT INTO "produtos"')]
        if len(inserts) != 1:
            return falhas(f'esperava 1 INSERT, veio {len(inserts)}: {inserts}')

        params = conn.sqls[[i for i, (s, _) in enumerate(conn.sqls)
                            if s.startswith('INSERT INTO "produtos"')][0]][1]
        if 'P1' in params:
            return falhas('o registro protegido P1 foi gravado mesmo assim!')
        if 'P2' not in params:
            return falhas('o registro liberado P2 não foi gravado')
    finally:
        S.get_colunas_e_tipos_tabela = original
    return True


def teste_lista_de_bloqueados():
    """A lista junta edição pendente (log) e conflito aberto."""
    print('2) lista de bloqueados soma pendentes + conflitos abertos')

    original_tem_log = S._tem_tabela_log
    S._tem_tabela_log = lambda conn: True
    try:
        conn = FakeConn()
        # 1ª consulta: _exodo_sync_log; 2ª: conflitos abertos.
        conn._respostas = [
            [('produtos', 'P1'), ('vendas_balcao', 'V9')],
            [('clientes', 'C3')],
        ]
        bloqueados = S.ids_bloqueados_no_download(conn)

        if bloqueados.get('produtos', {}).get('P1') != 'alteracao_local_pendente':
            return falhas(f"P1 deveria estar como pendente: {bloqueados}")
        if 'V9' not in bloqueados.get('vendas_balcao', {}):
            return falhas(f'V9 (pendente) não entrou: {bloqueados}')
        if 'C3' not in bloqueados.get('clientes', {}):
            return falhas(f'C3 (conflito aberto) não entrou: {bloqueados}')
    finally:
        S._tem_tabela_log = original_tem_log
    return True


def teste_conflito_parqueia_e_preserva_log():
    """Conflito vira pendência para o usuário; a edição local não é descartada."""
    print('3) conflito no upload é parqueado e o log local é preservado')

    registrados = []
    publicados = []

    originais = {
        'fetch_json': S.fetch_json,
        'get_supabase_colunas': S.get_supabase_colunas,
        'get_ultima_sync_tabela': S.get_ultima_sync_tabela,
        'coluna_timestamp_tabela': S.coluna_timestamp_tabela,
        'get_colunas_tabela': S.get_colunas_tabela,
        'registrar_conflito_pendente': S.registrar_conflito_pendente,
        'get_http_session': S.get_http_session,
    }

    class SessaoFalsa:
        def post(self, *a, **k):
            publicados.append(k.get('data') or (a[1] if len(a) > 1 else None))
            raise AssertionError('não deveria publicar em conflito')

        def delete(self, *a, **k):
            return types.SimpleNamespace(raise_for_status=lambda: None)

    # Contrato REAL: fetch_json devolve (dados, status). A consulta dos ids
    # pendentes na nuvem traz uma versão MAIS NOVA do que a local.
    S.fetch_json = lambda url, api_key: (
        [{'id': 'P1', 'nome': 'coca cola', 'estoque': 30, 'empresa_id': 'E1',
          'updated_at': '2099-01-01T00:00:00+00:00'}],
        200,
    )
    S.get_supabase_colunas = lambda url, key, tabela: set(COLUNAS_PRODUTO.keys())
    S.get_ultima_sync_tabela = lambda conn, tabela, empresa=None: '2026-09-01T00:00:00+00:00'
    S.coluna_timestamp_tabela = lambda conn, tabela: 'updated_at'
    S.get_colunas_tabela = lambda conn, tabela: list(COLUNAS_PRODUTO.keys())
    S.get_http_session = lambda: SessaoFalsa()

    def registrar_falso(conn, tabela, registro_id, locais, nuvem, empresa_id=None):
        registrados.append((tabela, registro_id, locais, nuvem))
        return True

    S.registrar_conflito_pendente = registrar_falso

    try:
        conn = FakeConn()
        # Ordem das consultas no upload_tabela:
        #  1. SELECT do _exodo_sync_log  -> 1 log pendente
        #  2. SELECT da linha local (RealDictCursor)
        conn._respostas = [
            [('log-1', 'P1', 'UPDATE')],
            [{'id': 'P1', 'nome': 'coca cola', 'estoque': 33, 'empresa_id': 'E1',
              'updated_at': '2026-09-28T00:00:00+00:00'}],
        ]
        enviados = S.upload_tabela(conn, 'produtos', 'https://x.supabase.co', 'chave', 'E1')

        if enviados != 0:
            return falhas(f'nada deveria ser enviado num conflito, veio {enviados}')
        if publicados:
            return falhas('publicou na nuvem durante um conflito')
        if len(registrados) != 1:
            return falhas(f'esperava 1 conflito registrado, veio {len(registrados)}')
        tabela, registro_id, locais, nuvem = registrados[0]
        if (tabela, registro_id) != ('produtos', 'P1'):
            return falhas(f'conflito registrado errado: {tabela}/{registro_id}')
        if locais.get('estoque') != 33 or nuvem.get('estoque') != 30:
            return falhas('as duas versões precisam ser guardadas para a decisão')

        deletes_log = [s for s in montar_sqls(conn) if s.startswith('DELETE FROM _exodo_sync_log')]
        if deletes_log:
            return falhas('o log local foi apagado: a edição do usuário ficava solta '
                          'e o download passava por cima dela')
        if not conn.sqls:
            return falhas('nenhuma consulta foi feita')
    finally:
        for nome, valor in originais.items():
            setattr(S, nome, valor)
    return True


def teste_numero_repetido_e_renumerado():
    """VND-0003 feito nos DOIS PCs: o segundo sobe renumerado, ninguém perde venda."""
    print('4) numero repetido entre maquinas e renumerado (no lote e no local)')

    original_fetch = S.fetch_json
    chamadas = []

    def fetch_falso(url, api_key):
        chamadas.append(url)
        if 'numero=in.' in url:
            # A nuvem já tem 'VND-0003' — de OUTRO registro (o outro PC).
            return ([{'id': 'OUTRO_PC', 'numero': 'VND-0003'}], 200)
        if 'order=numero.desc' in url:
            return ([{'numero': 'VND-0433'}, {'numero': 'VND-0012'}], 200)
        return ([], 200)

    S.fetch_json = fetch_falso
    try:
        conn = FakeConn()
        registros = [
            {'id': 'V3', 'numero': 'VND-0003', 'empresa_id': 'E1', 'valor_total': 10},
            {'id': 'V9', 'numero': 'VND-0444', 'empresa_id': 'E1', 'valor_total': 20},
        ]
        renomeados = S.renumerar_repetidos_do_lote(
            conn, 'vendas_balcao', registros, 'https://x.supabase.co', 'k', 'E1')

        if len(renomeados) != 1:
            return falhas(f'esperava 1 renumeracao, veio {renomeados}')
        antigo, novo, rid = renomeados[0]
        if (antigo, rid) != ('VND-0003', 'V3'):
            return falhas(f'renumerou o registro errado: {renomeados[0]}')
        if novo != 'VND-0434':
            return falhas(f'esperava VND-0434 (maior da nuvem + 1), veio {novo}')
        if registros[0]['numero'] != 'VND-0434':
            return falhas('o lote enviado continuou com o numero antigo')
        if registros[1]['numero'] != 'VND-0444':
            return falhas('mexeu no numero de um registro que NAO estava repetido')

        # UPDATE "vendas_balcao" SET numero = %s WHERE id = %s -> (novo, id)
        updates = [p for s, p in conn.sqls if s.startswith('UPDATE "vendas_balcao"')]
        if not updates:
            return falhas('a copia local nao foi corrigida (o PC reenviaria o numero antigo)')
        if updates[0] != ('VND-0434', 'V3'):
            return falhas(f'atualizou a linha local errada: {updates[0]}')
    finally:
        S.fetch_json = original_fetch
    return True


def teste_bloco_recusado_nao_derruba_os_bons():
    """Um registro ruim nao pode levar 500 vendas junto (nem sumir do log)."""
    print('5) bloco recusado: reenvia um a um e mantem o recusado pendente')

    import requests

    publicados = []

    class RespostaFalsa:
        def __init__(self, status=400, texto='numero duplicado'):
            self.status_code = status
            self.text = texto

        def raise_for_status(self):
            erro = requests.exceptions.HTTPError('recusado')
            erro.response = self
            raise erro

    class SessaoFalsa:
        def post(self, url, data=None, headers=None, timeout=None):
            import json as _json
            corpo = _json.loads(data)
            publicados.append(corpo)
            if len(corpo) > 1:
                return RespostaFalsa(400, 'bloco inteiro recusado')
            if corpo[0].get('id') == 'V2':
                return RespostaFalsa(400, 'dado recusado pela nuvem')
            return types.SimpleNamespace(raise_for_status=lambda: None)

    enviados, recusados = S._postar_lote(
        SessaoFalsa(), 'https://x.supabase.co/rest/v1/vendas_balcao', {},
        [{'id': 'V1', 'numero': 'VND-0001'},
         {'id': 'V2', 'numero': 'VND-0002'},
         {'id': 'V3', 'numero': 'VND-0003'}], 'vendas_balcao')

    if enviados != 2:
        return falhas(f'esperava 2 enviados, veio {enviados}')
    if recusados != {'V2'}:
        return falhas(f'esperava so V2 recusado, veio {recusados}')
    if len(publicados) != 4:
        return falhas(f'esperava 1 bloco + 3 individuais, veio {len(publicados)} POSTs')
    return True


def teste_log_do_recusado_nao_e_apagado():
    """O log do registro recusado fica: ele volta no proximo ciclo."""
    print('6) log do registro recusado continua pendente')

    import requests

    originais = {
        'fetch_json': S.fetch_json,
        'get_supabase_colunas': S.get_supabase_colunas,
        'get_colunas_tabela': S.get_colunas_tabela,
        'get_http_session': S.get_http_session,
        'coluna_timestamp_tabela': S.coluna_timestamp_tabela,
        'get_ultima_sync_tabela': S.get_ultima_sync_tabela,
    }
    colunas = {'id': 'TEXT', 'numero': 'TEXT', 'empresa_id': 'TEXT', 'valor_total': 'NUMERIC'}

    class RespostaFalsa:
        def __init__(self):
            self.status_code = 400
            self.text = 'dado recusado'

        def raise_for_status(self):
            erro = requests.exceptions.HTTPError('recusado')
            erro.response = self
            raise erro

    class SessaoFalsa:
        def post(self, url, data=None, headers=None, timeout=None):
            import json as _json
            corpo = _json.loads(data)
            if len(corpo) > 1 or corpo[0].get('id') == 'V2':
                return RespostaFalsa()
            return types.SimpleNamespace(raise_for_status=lambda: None)

        def delete(self, *a, **k):
            return types.SimpleNamespace(raise_for_status=lambda: None)

    S.fetch_json = lambda url, api_key: ([], 200)
    S.get_supabase_colunas = lambda url, key, tabela: set(colunas.keys())
    S.get_colunas_tabela = lambda conn, tabela: list(colunas.keys())
    S.coluna_timestamp_tabela = lambda conn, tabela: None
    S.get_ultima_sync_tabela = lambda conn, tabela, empresa=None: None
    S.get_http_session = lambda: SessaoFalsa()

    try:
        conn = FakeConn()
        conn._respostas = [
            [('log-1', 'V1', 'UPDATE'), ('log-2', 'V2', 'UPDATE')],
            [{'id': 'V1', 'numero': 'VND-0001', 'empresa_id': 'E1', 'valor_total': 1},
             {'id': 'V2', 'numero': 'VND-0002', 'empresa_id': 'E1', 'valor_total': 2}],
        ]
        enviados = S.upload_tabela(conn, 'vendas_balcao',
                                   'https://x.supabase.co', 'k', 'E1')
        if enviados != 1:
            return falhas(f'esperava 1 enviado, veio {enviados}')

        deletes = [p for s, p in conn.sqls if s.startswith('DELETE FROM _exodo_sync_log')]
        if not deletes:
            return falhas('nada foi limpo do log')
        restantes = deletes[0][0]
        if 'log-2' in restantes:
            return falhas('o log do registro recusado foi apagado: o dado nunca mais '
                          'seria tentado e a venda nao apareceria no outro PC')
        if 'log-1' not in restantes:
            return falhas(f'o log do registro que subiu deveria ser limpo: {restantes}')
    finally:
        for nome, valor in originais.items():
            setattr(S, nome, valor)
    return True


def teste_empresa_com_nuvem_desativada_pausa_o_ciclo_antes_da_rede():
    """A flag local precisa parar o worker antes de qualquer chamada Supabase."""
    print('7) empresa com nuvem desativada pausa o ciclo antes da rede')
    originais = {
        'obter_empresa_ativa': S.obter_empresa_ativa,
        'empresa_permite_sincronizacao_nuvem': S.empresa_permite_sincronizacao_nuvem,
        'testar_conexao_supabase': S.testar_conexao_supabase,
    }
    chamadas_rede = []
    estados = []
    try:
        S.obter_empresa_ativa = lambda conn: 'E1'
        S.empresa_permite_sincronizacao_nuvem = lambda conn, empresa: False
        S.testar_conexao_supabase = lambda url: chamadas_rede.append(url) or True
        resultado = S.executar_ciclo_sincronizacao(
            FakeConn(), 'https://x.supabase.co', 'k', on_state_change=estados.append
        )
        if resultado != (0, 0):
            return falhas(f'esperava ciclo pausado (0, 0), veio {resultado}')
        if chamadas_rede:
            return falhas('tentou conectar na nuvem mesmo com a empresa pausada')
        if estados != ['syncing', 'paused']:
            return falhas(f'estados inesperados: {estados}')
    finally:
        for nome, valor in originais.items():
            setattr(S, nome, valor)
    return True


def teste_flag_nuvem_por_empresa_e_lida_do_postgres():
    print('8) flag de nuvem por empresa vem da configuração local')
    conn_off = FakeConn(respostas=[({'nuvem_ativa': False},)])
    if S.empresa_permite_sincronizacao_nuvem(conn_off, 'E1'):
        return falhas('nuvem_ativa=false foi interpretado como ativa')

    conn_on = FakeConn(respostas=[('{"nuvemAtiva": true}',)])
    if not S.empresa_permite_sincronizacao_nuvem(conn_on, 'E2'):
        return falhas('nuvemAtiva=true foi interpretado como desativada')

    conn_default = FakeConn(respostas=[({},)])
    if not S.empresa_permite_sincronizacao_nuvem(conn_default, 'E3'):
        return falhas('empresa sem flag não manteve o padrão ativo')
    return True


def main():
    testes = [
        teste_download_nao_sobrescreve_pendente,
        teste_lista_de_bloqueados,
        teste_conflito_parqueia_e_preserva_log,
        teste_numero_repetido_e_renumerado,
        teste_bloco_recusado_nao_derruba_os_bons,
        teste_log_do_recusado_nao_e_apagado,
        teste_empresa_com_nuvem_desativada_pausa_o_ciclo_antes_da_rede,
        teste_flag_nuvem_por_empresa_e_lida_do_postgres,
    ]
    ok = 0
    for t in testes:
        try:
            passou = t()
        except Exception as e:
            import traceback
            traceback.print_exc()
            passou = falhas(f'exceção: {e}')
        print('  [ok]' if passou else '  [FALHOU]')
        ok += 1 if passou else 0
    print(f'\n{ok}/{len(testes)} testes passaram')
    return 0 if ok == len(testes) else 1


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""HTTP 401/402/403 é BLOQUEIO da nuvem, não falha transitória.

O 402 (exceed_egress_quota) significa que o Supabase recusou o projeto inteiro:
enquanto o dono nao resolver, toda requisicao volta 402. O ciclo antigo tratava
isso como "falha transiente" e repetia 40+ downloads e dezenas de uploads a cada
passada, inundando o log sem chance nenhuma de sucesso.

Aqui a nuvem entra em pausa (BLOQUEIO_SEGUNDOS) e o aviso sai uma vez so.
Este teste roda DOIS ciclos com tudo devolvendo 402 e prova que:
  - o aviso de bloqueio aparece exatamente 1 vez;
  - nenhuma linha "Falha transiente" e escrita;
  - o segundo ciclo nem faz requisicao (zero chamadas HTTP);
  - a fila de upload nao perde registro recusado (todos ficam como recusados).

Uso:  python test_bloqueio_nuvem.py      (sem banco, sem rede)
"""
import sys
import threading
from datetime import datetime, timedelta, timezone

import requests

import sincronizar_local_supabase as S

FALHOU = []


def checa(condicao, descricao):
    if condicao:
        print('  [ok] %s' % descricao)
    else:
        print('  [FALHOU] %s' % descricao)
        FALHOU.append(descricao)


# ─────────────────────────── fakes ───────────────────────────

class FakeCursor:
    def __init__(self, tabelas):
        self.tabelas = tabelas
        self.ultima = ''

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql, params=None):
        self.ultima = sql

    def fetchall(self):
        if 'information_schema.tables' in self.ultima:
            return [(t,) for t in self.tabelas]
        return []

    def fetchone(self):
        if 'COUNT(*)' in self.ultima:
            return (1,)          # tabela com dados locais
        return None

    def close(self):
        pass


class FakeConn:
    def __init__(self, tabelas):
        self._cursor = FakeCursor(tabelas)

    def cursor(self):
        return self._cursor

    def commit(self):
        pass

    def rollback(self):
        pass


class Resp402:
    """Resposta HTTP que o requests transforma em HTTPError."""
    status_code = 402
    text = '{"message":"exceed_egress_quota"}'

    def raise_for_status(self):
        raise requests.exceptions.HTTPError('402', response=self)


class SessaoFalsa:
    def __init__(self):
        self.chamadas = 0

    def post(self, *_a, **_k):
        self.chamadas += 1
        return Resp402()

    def close(self):
        pass


class SessaoQuebrada:
    """session.post que levanta o mesmo HTTPError direto (sem raise_for_status)."""
    def __init__(self):
        self.chamadas = 0

    def post(self, *_a, **_k):
        self.chamadas += 1
        e = requests.exceptions.HTTPError('402')
        e.response = Resp402()
        raise e

    def close(self):
        pass


def _voltar_pra_zero():
    """Deixa o módulo como estava antes do teste (pausa não vaza entre casos)."""
    S._bloqueio_nuvem['status'] = None
    S._bloqueio_nuvem['ate'] = None
    S._tabelas_404_cooldown.clear()


def instalar_mocks(lista_logs, chamadas_http):
    """Silencia o log e devolve 402 em toda chamada HTTP."""
    S.print_log = lambda msg, *_a, **_k: lista_logs.append(str(msg))

    def fetch_json_falso(*_a, **_k):
        chamadas_http.append(1)
        return None, 402
    S.fetch_json = fetch_json_falso

    S.carregar_meta_colunas = lambda conn: None
    S.garantir_tabela_controle = lambda conn: None
    S.obter_empresa_ativa = lambda conn: None
    S.empresa_permite_sincronizacao_nuvem = lambda conn, emp: True
    S.testar_conexao_supabase = lambda url: True
    S.testar_conexao_nuvem = lambda url: True
    S.atualizar_status_no_supabase = lambda *a, **k: None
    S.processar_comandos_no_supabase = lambda *a, **k: None
    S.garantir_base_local_completa = lambda *a, **k: None
    S.deve_limpar_outras_empresas = lambda *a, **k: False
    S.salvar_empresa_ativa_vista = lambda *a, **k: None
    S.ids_bloqueados_no_download = lambda conn: {}
    S.get_ultima_sync_tabela = lambda conn, tabela, emp=None: S._EPOCH
    S.salvar_ultima_sync_tabela = lambda *a, **k: None
    S.reportar_sync_status_supabase = lambda *a, **k: None
    S.tem_conflitos_pendentes = lambda conn: False
    S.upload_tabela = lambda *a, **k: 0   # o upload é testado à parte


TABELS_TESTE = ['produtos', 'vendas_balcao', 'nfces', 'clientes', 'caixas']


# ─────────────────────────── casos ───────────────────────────

def caso_1_pausa_expira():
    print('1) a pausa de 30 min expira sozinha')
    _voltar_pra_zero()
    S._marcar_bloqueio_nuvem(402, 'exceed_egress_quota')
    checa(S.nuvem_bloqueada(), 'logo após o 402 a nuvem entra em pausa')
    checa(S.motivo_bloqueio_nuvem() == 402, 'motivo_bloqueio_nuvem devolve o HTTP 402')
    S._bloqueio_nuvem['ate'] = datetime.now(timezone.utc) - timedelta(seconds=1)
    checa(not S.nuvem_bloqueada(), 'passada a janela, a sincronização volta a tentar')


def caso_2_fetch_marca_bloqueio():
    print('2) fetch_updates_tabela reconhece o 402 e NÃO vira "transiente"')
    _voltar_pra_zero()
    S.fetch_json = lambda *a, **k: (None, 402)
    tabela, rows, sucesso, is_404 = S.fetch_updates_tabela(
        'produtos', S._EPOCH, 'https://exemplo.supabase.co', 'key', None)
    checa(sucesso is False, 'a tabela veio como falha')
    checa(is_404 is False, 'não foi marcada como 404/cooldown de tabela')
    checa(S.nuvem_bloqueada(), 'a nuvem entrou em pausa por causa do 402')


def caso_3_poste_em_bloco():
    print('3) _postar_lote no modo bloco: 402 pausa tudo e não perde a fila')
    _voltar_pra_zero()
    logs = []
    S.print_log = lambda msg, *_a, **_k: logs.append(str(msg))
    sessao = SessaoQuebrada()
    registros = [{'id': f'R{i}'} for i in range(5)]
    enviados, recusados = S._postar_lote(sessao, 'http://x/produtos', {}, registros, 'produtos')
    checa(enviados == 0, 'nada foi marcado como enviado')
    checa(recusados == {'R0', 'R1', 'R2', 'R3', 'R4'},
          'os 5 registros ficam recusados (a fila local preserva tudo)')
    checa(sessao.chamadas == 1, f'1 chamada HTTP no modo bloco (fez {sessao.chamadas})')
    checa(S.nuvem_bloqueada(), 'nuvem em pausa')


def caso_4_poste_um_a_um():
    print('4) _postar_lote registro a registro: para no primeiro 402')
    _voltar_pra_zero()
    logs = []
    S.print_log = lambda msg, *_a, **_k: logs.append(str(msg))
    sessao = SessaoQuebrada()
    registros = [{'id': f'R{i}'} for i in range(5)]
    enviados, recusados = S._postar_lote(sessao, 'http://x/produtos', {}, registros, 'produtos')
    checa(enviados == 0, 'nada enviado')
    checa(recusados == {'R0', 'R1', 'R2', 'R3', 'R4'},
          'todos os 5 continuam pendentes, inclusive os nem tentados')
    checa(sessao.chamadas == 1,
          f'parou no primeiro 402 (fez {sessao.chamadas} de 5 chamadas)')
    checa(not any('recusado pela nuvem' in l for l in logs),
          'não spama "registro recusado pela nuvem" 5 vezes')


def caso_5_dois_ciclos():
    print('5) dois ciclos com tudo em 402: 1 aviso, zero retry, 0 requisição no 2º')
    _voltar_pra_zero()
    logs, chamadas = [], []
    estados = []
    instalar_mocks(logs, chamadas)
    S._colunas_e_tipos_cache = {t: {'updated_at': 'timestamp', 'empresa_id': 'text'}
                                for t in TABELS_TESTE}
    conn = FakeConn(TABELS_TESTE)

    S.executar_ciclo_sincronizacao(
        conn, 'https://exemplo.supabase.co', 'key',
        on_state_change=lambda e: estados.append(e))
    primeiro_ciclo = len(chamadas)
    S.executar_ciclo_sincronizacao(
        conn, 'https://exemplo.supabase.co', 'key',
        on_state_change=lambda e: estados.append(e))
    segundo_ciclo = len(chamadas) - primeiro_ciclo

    bloqueios = [l for l in logs if 'Nuvem bloqueada' in l]
    transientes = [l for l in logs if 'Falha transiente' in l]

    checa(len(bloqueios) == 1,
          f'o aviso de bloqueio saiu 1 vez nos 2 ciclos (saiu {len(bloqueios)})')
    checa(not transientes,
          f'nenhuma linha "Falha transiente" (saiu {len(transientes)})')
    checa(segundo_ciclo == 0,
          f'o 2º ciclo não fez nenhuma requisição (fez {segundo_ciclo})')
    checa(primeiro_ciclo > 0, f'o 1º ciclo sondou a nuvem ({primeiro_ciclo} chamadas)')
    checa(estados[-1] == 'offline',
          f'estado final recebido pelo app: {estados[-1]}')


def main():
    print('=' * 60)
    print('Bloqueio da nuvem (401/402/403) x falha transitória')
    print('=' * 60)
    caso_1_pausa_expira()
    caso_2_fetch_marca_bloqueio()
    caso_3_poste_em_bloco()
    caso_4_poste_um_a_um()
    caso_5_dois_ciclos()
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

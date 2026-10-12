#!/usr/bin/env python3
"""
Testes da reserva ATÔMICA dos comandos remotos (bridge_commands).

O defeito que estes testes prendem: o sincronizador buscava os comandos
`pendente` e só DEPOIS marcava como `processando`. Dois PCs rodando o ciclo
quase ao mesmo tempo (o caso normal de uma loja) viam o MESMO comando pendente
e os DOIS baixavam e aplicavam a atualização — a janela do atualizador "abria e
fechava" na máquina que não deveria atualizar.

A correção é o compare-and-swap: o PATCH só pega a linha que ainda está
`pendente`, e quem não consegue mudar o status não executa nada.

Rodar: .venv\\Scripts\\python.exe test_comandos_bridge.py
"""
import sys
import types

sys.path.insert(0, '.')
import sincronizar_local_supabase as S    # noqa: E402


def falhou(mensagem):
    print(f'  [FALHOU] {mensagem}')
    return False


class FakeResponse:
    def __init__(self, status_code=200, corpo=None):
        self.status_code = status_code
        self._corpo = corpo if corpo is not None else []
        self.text = str(self._corpo)

    def json(self):
        return self._corpo


class FakeRequests:
    """Roteia GET/PATCH por URL e guarda tudo que foi chamado."""

    def __init__(self, pendentes, reserve_ok=True, bridge_config=None):
        self.pendentes = pendentes
        self.reserve_ok = reserve_ok
        self.bridge_config = bridge_config or []
        self.patches = []      # (url, json, headers)
        self.gets = []

    def get(self, url, headers=None, timeout=None, stream=False):
        self.gets.append(url)
        if 'bridge_config' in url:
            return FakeResponse(200, self.bridge_config)
        if 'bridge_commands' in url:
            return FakeResponse(200, self.pendentes)
        # Um download de verdade nunca deve acontecer nestes testes.
        return FakeResponse(500, [])

    def patch(self, url, json=None, headers=None, timeout=None):
        self.patches.append((url, json or {}, headers or {}))
        if 'status=eq.pendente' in url:
            # A reserva: devolve a linha só quando o CAS ganha.
            if self.reserve_ok:
                return FakeResponse(200, [{'id': 'c1', 'status': 'processando'}])
            return FakeResponse(200, [])
        # A resposta final (não interessa o conteúdo).
        return FakeResponse(200, [])


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn
        self._ultimo = None
        self.rowcount = 0

    def execute(self, sql, params=None):
        self.conn.sqls.append((' '.join(str(sql).split()), params))
        self._ultimo = self.conn._proxima()

    def fetchone(self):
        return self._ultimo

    def fetchall(self):
        return self._ultimo or []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FakeConn:
    """Conexão local de mentira, com fila de respostas por consulta."""

    def __init__(self, respostas=None):
        self.sqls = []
        self.commits = 0
        self._respostas = respostas or []

    def _proxima(self):
        return self._respostas.pop(0) if self._respostas else None

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        pass


def _com_url(patches, trecho):
    return [p for p in patches if trecho in p[0]]


# ─────────────────────────────── Testes ───────────────────────────────

def teste_nao_executa_quando_outro_pc_reservou():
    """Se o PATCH de reserva não muda nada, este comando não é nosso."""
    print('1) comando já reservado por outro PC NÃO é executado')
    original_requests = S.requests
    original_exec = S.executar_atualizacao_completa
    executou = []
    S.requests = FakeRequests([{'id': 'c1', 'comando': 'update'}], reserve_ok=False)
    S.executar_atualizacao_completa = lambda *a, **k: executou.append(1) or (True, 'ok')
    try:
        S.processar_comandos_no_supabase(None, 'https://x.supabase.co', 'k')
        if executou:
            return falhou('executou a atualização sem ter reservado o comando')
        if _com_url(S.requests.patches, 'processor_pc=eq.'):
            return falhou('respondeu um comando que não reservou')
    finally:
        S.requests = original_requests
        S.executar_atualizacao_completa = original_exec
    return True


def teste_executa_uma_vez_quando_reserva():
    """Quem reserva, executa exatamente uma vez e reporta o resultado."""
    print('2) quem reserva o comando executa uma única vez')
    original_requests = S.requests
    original_exec = S.executar_atualizacao_completa
    executou = []
    S.requests = FakeRequests([{'id': 'c1', 'comando': 'update'}], reserve_ok=True)
    S.executar_atualizacao_completa = lambda *a, **k: executou.append(1) or (True, 'ok')
    try:
        S.processar_comandos_no_supabase(None, 'https://x.supabase.co', 'k')
        if len(executou) != 1:
            return falhou(f'deveria executar 1 vez, executou {len(executou)}')
        finais = _com_url(S.requests.patches, 'processor_pc=eq.')
        if not finais:
            return falhou('não reportou o resultado do comando')
        if finais[0][1].get('status') != 'concluido':
            return falhou(f'status final errado: {finais[0][1]}')
    finally:
        S.requests = original_requests
        S.executar_atualizacao_completa = original_exec
    return True


def teste_reserva_usa_compare_and_swap():
    """A reserva precisa filtrar status=pendente — é o que impede a corrida."""
    print('3) a reserva filtra status=eq.pendente (compare-and-swap)')
    original_requests = S.requests
    original_exec = S.executar_atualizacao_completa
    S.requests = FakeRequests([{'id': 'c1', 'comando': 'identify'}])
    S.executar_atualizacao_completa = lambda *a, **k: (True, 'ok')
    try:
        S.processar_comandos_no_supabase(None, 'https://x.supabase.co', 'k')
        reservas = _com_url(S.requests.patches, 'status=eq.pendente')
        if not reservas:
            return falhou('a reserva não usou o filtro de pendente (corrida de volta)')
        if 'id=eq.c1' not in reservas[0][0]:
            return falhou(f'reservou o comando errado: {reservas[0][0]}')
    finally:
        S.requests = original_requests
        S.executar_atualizacao_completa = original_exec
    return True


def teste_nome_do_pc_vai_codificado():
    """Nome de PC com caractere especial não pode quebrar o filtro do PostgREST."""
    print('4) o nome do PC vai URL-encoded no filtro')
    original_requests = S.requests
    original_platform = S.platform
    S.requests = FakeRequests([])
    S.platform = types.SimpleNamespace(node=lambda: 'PC CAIXA 1')
    try:
        S.processar_comandos_no_supabase(None, 'https://x.supabase.co', 'k')
        url = S.requests.gets[0] if S.requests.gets else ''
        if 'target_pc.eq.PC CAIXA 1' in url:
            return falhou('o nome foi colocado cru no filtro')
        if 'PC%20CAIXA%201' not in url:
            return falhou(f'nome não codificado: {url}')
    finally:
        S.requests = original_requests
        S.platform = original_platform
    return True


def teste_pula_quando_ja_esta_na_versao():
    """Máquina já na versão pedida NÃO baixa nem relança nada."""
    print('5) máquina já na versão pedida pula a troca de arquivos')
    original_requests = S.requests
    original_exists = S.os.path.exists
    S.requests = FakeRequests(
        [], bridge_config=[{'id': 'app_latest',
                            'download_url': 'https://x/app.exe',
                            'version': '1.0.17'}])
    # O executável "existe" e o marcador local diz que já aplicamos a 1.0.17.
    S.os.path.exists = lambda caminho: True
    conn = FakeConn(respostas=[('1.0.17',)])
    try:
        sucesso, resultado = S.executar_atualizacao_completa(
            'https://x.supabase.co', 'k', conn)
        if not sucesso:
            return falhou(f'deveria concluir com sucesso: {resultado}')
        if 'atualizado' not in resultado.lower():
            return falhou(f'mensagem inesperada: {resultado}')
        # Só a consulta ao bridge_config: nenhum download foi tentado.
        downloads = [u for u in S.requests.gets if 'bridge_config' not in u]
        if downloads:
            return falhou(f'baixou algo mesmo já estando atualizado: {downloads}')
    finally:
        S.requests = original_requests
        S.os.path.exists = original_exists
    return True


def teste_marca_versao_aplicada():
    """Depois de aplicar, a versão fica registrada localmente."""
    print('6) a versão aplicada é gravada no controle local')
    conn = FakeConn()
    S._marcar_versao_aplicada_local(conn, 'app_latest', '1.0.17')
    if not conn.sqls:
        return falhou('nada foi gravado')
    chave, valor = conn.sqls[0][1]
    if chave != 'versao_aplicada_app_latest' or valor != '1.0.17':
        return falhou(f'gravou errado: {conn.sqls[0][1]}')
    if conn.commits != 1:
        return falhou('não confirmou a transação')
    return True


def teste_ignora_comando_de_outro_cnpj():
    """Comando dirigido a um CNPJ não roda no emissor de outro CNPJ."""
    print('7) comando para outro CNPJ é ignorado')
    original_requests = S.requests
    original_cnpj = S.obter_cnpj_local
    original_exec = S.executar_atualizacao_completa
    executou = []
    S.requests = FakeRequests([{'id': 'c1', 'comando': 'update',
                                'extra_data': {'cnpj': '11.111.111/0001-11'}}])
    S.obter_cnpj_local = lambda conn: '22.222.222/0001-22'
    S.executar_atualizacao_completa = lambda *a, **k: executou.append(1) or (True, 'ok')
    try:
        S.processar_comandos_no_supabase(FakeConn(), 'https://x.supabase.co', 'k')
        if executou:
            return falhou('executou comando de outro CNPJ')
        if S.requests.patches:
            return falhou('reservou um comando que não era seu')
    finally:
        S.requests = original_requests
        S.obter_cnpj_local = original_cnpj
        S.executar_atualizacao_completa = original_exec
    return True


def teste_executa_comando_do_mesmo_cnpj():
    """O emissor do CNPJ alvo executa normalmente."""
    print('8) o emissor do CNPJ alvo executa o comando')
    original_requests = S.requests
    original_cnpj = S.obter_cnpj_local
    original_exec = S.executar_atualizacao_completa
    executou = []
    S.requests = FakeRequests([{'id': 'c1', 'comando': 'update',
                                'extra_data': {'cnpj': '22.222.222/0001-22'}}])
    S.obter_cnpj_local = lambda conn: '22.222.222/0001-22'
    S.executar_atualizacao_completa = lambda *a, **k: executou.append(1) or (True, 'ok')
    try:
        S.processar_comandos_no_supabase(FakeConn(), 'https://x.supabase.co', 'k')
        if len(executou) != 1:
            return falhou(f'deveria executar 1 vez, executou {len(executou)}')
    finally:
        S.requests = original_requests
        S.obter_cnpj_local = original_cnpj
        S.executar_atualizacao_completa = original_exec
    return True


def main():
    testes = [
        teste_nao_executa_quando_outro_pc_reservou,
        teste_executa_uma_vez_quando_reserva,
        teste_reserva_usa_compare_and_swap,
        teste_nome_do_pc_vai_codificado,
        teste_pula_quando_ja_esta_na_versao,
        teste_marca_versao_aplicada,
        teste_ignora_comando_de_outro_cnpj,
        teste_executa_comando_do_mesmo_cnpj,
    ]
    original_log = S.print_log
    S.print_log = lambda *a, **k: None
    ok = 0
    try:
        for t in testes:
            try:
                passou = t()
            except Exception:
                import traceback
                traceback.print_exc()
                passou = falhou('exceção')
            print('  [ok]' if passou else '  [FALHOU]')
            ok += 1 if passou else 0
    finally:
        S.print_log = original_log
    print(f'\n{ok}/{len(testes)} testes passaram')
    return 0 if ok == len(testes) else 1


if __name__ == '__main__':
    sys.exit(main())

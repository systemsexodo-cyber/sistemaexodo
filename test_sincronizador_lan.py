#!/usr/bin/env python3
"""
Testes da sincronização entre os PCs pela rede local.

Roda SEM banco e SEM rede: as conexões (local e do par) são objetos de mentira
que registram o SQL executado. É o que precisa ser verdade para os dois bancos
da mesma loja não se atropelarem:

  1. sem PAR_HOST a LAN fica desligada (o ciclo da nuvem roda sozinho);
  2. tabelas proibidas (usuarios, cache_dados...) NUNCA são copiadas;
  3. apagado do par não derruba alteração local pendente nem conflito aberto;
  4. no 1º contato a sincronização começa de AGORA (não puxa o histórico todo);
  5. no ciclo normal aplica os registros novos e avança o cursor;
  6. par fora do ar não levanta exceção (a nuvem continua funcionando);
  7. o par pode ser informado pelo NOME do computador: o nome é traduzido para
     o IPv4 dele a cada ciclo, e um IP que muda não derruba mais a LAN.

Rodar: .venv\\Scripts\\python.exe test_sincronizador_lan.py
"""
import sys
import types

sys.path.insert(0, '.')
import sincronizador_lan as L            # noqa: E402
import sincronizar_local_supabase as S    # noqa: E402

# `main()` troca `ids_bloqueados_no_download` por um stub (o ciclo não tem banco).
# Os testes que precisam provar o comportamento REAL dela usam esta referência,
# capturada antes de qualquer troca.
IDS_BLOQUEADOS_REAL = S.ids_bloqueados_no_download


# ─────────────────────────── Dublês de conexão ───────────────────────────

class FakeCursor:
    """Cursor de mentira: devolve respostas roteirizadas e guarda o SQL."""

    def __init__(self, conn):
        self.conn = conn
        self.rowcount = 0

    def execute(self, sql, params=None):
        self.conn.sqls.append((' '.join(str(sql).split()), params))
        self.rowcount = (self.conn._rowcounts.pop(0)
                         if self.conn._rowcounts else 1)
        self._ultimo = self.conn._proxima()

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
    """Conexão de mentira com fila de respostas (uma por consulta)."""

    def __init__(self, respostas=None, rowcounts=None):
        self.sqls = []
        self.commits = 0
        self.rollbacks = 0
        self._respostas = respostas or []
        self._rowcounts = rowcounts or []

    def _proxima(self):
        return self._respostas.pop(0) if self._respostas else None

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        pass


# ─────────────────────────────── Apoio ───────────────────────────────

CFG = {'host': '192.168.0.12', 'port': '5432', 'dbname': 'exodo_db',
       'user': 'exodo_user', 'password': 'x', 'nome': 'PC-2',
       'dias_tombstone': 30, 'inicial_completo': False}

COLUNAS_PRODUTO = [('id', 'text'), ('nome', 'text'), ('empresa_id', 'text'),
                   ('updated_at', 'timestamp with time zone')]


def falhou(mensagem):
    print(f'  [FALHOU] {mensagem}')
    return False


def sqls_de(conn, prefixo):
    return [p for s, p in conn.sqls if s.startswith(prefixo)]


def _params_da_leitura(conn_par):
    """Parâmetros do `SELECT *` montado para puxar do par (o 1º é `desde`)."""
    for s, p in conn_par.sqls:
        if s.startswith('SELECT * FROM'):
            return p
    return None


# ─────────────────────────────── Testes ───────────────────────────────

def teste_lan_desligada_sem_host():
    """Sem PAR_HOST nada acontece (instalação de 1 PC só)."""
    print('1) sem PAR_HOST a LAN fica desligada')
    if L.config_do_par({}) is not None:
        return falhou('config veio preenchida sem PAR_HOST')
    if L.config_do_par({'PAR_HOST': '', 'LAN_SYNC': 'true'}) is not None:
        return falhou('host vazio deveria desligar')
    if L.config_do_par({'PAR_HOST': '10.0.0.9', 'LAN_SYNC': 'false'}) is not None:
        return falhou('LAN_SYNC=false deveria desligar')
    return True


def teste_config_herda_credenciais_locais():
    """Sem PAR_DB_* a conexão do par usa as mesmas credenciais do banco local."""
    print('2) configuração herda DB_* quando PAR_DB_* não vem')
    cfg = L.config_do_par({
        'PAR_HOST': '192.168.0.12', 'DB_NAME': 'exodo_db',
        'DB_USER': 'exodo_user', 'DB_PASSWORD': 'segredo',
    })
    if cfg['dbname'] != 'exodo_db' or cfg['user'] != 'exodo_user':
        return falhou(f'não herdou DB_*: {cfg}')
    if cfg['password'] != 'segredo':
        return falhou('não herdou a senha local')
    if cfg['port'] != '5432' or cfg['nome'] != '192.168.0.12':
        return falhou(f'padrões errados: {cfg}')
    # PAR_DB_* tem prioridade quando existe
    cfg2 = L.config_do_par({
        'PAR_HOST': '192.168.0.12', 'PAR_DB_PASSWORD': 'outra',
        'PAR_NOME': 'PC-CAIXA-2', 'DB_PASSWORD': 'segredo',
    })
    if cfg2['password'] != 'outra' or cfg2['nome'] != 'PC-CAIXA-2':
        return falhou(f'PAR_DB_* não teve prioridade: {cfg2}')
    return True


def teste_tabelas_proibidas():
    """usuarios e as tabelas privadas do app ficam de fora da cópia."""
    print('3) tabelas proibidas nunca são copiadas entre os PCs')
    conn = FakeConn([[
        ('produtos',), ('vendas_balcao',), ('usuarios',), ('cache_dados',),
        ('exodo_sync_conflitos',), ('sync_status',), ('bridge_commands',),
        # `bridge_config` escapava da lista fechada e era copiada entre os PCs;
        # a regra por prefixo (`bridge_`) é o que impede isso.
        ('bridge_config',), ('bridge_status',),
    ]])
    tabelas = L._tabelas_para_lan(conn)
    if 'produtos' not in tabelas or 'vendas_balcao' not in tabelas:
        return falhou(f'tabelas de dados sumiram: {tabelas}')
    for proibida in ('usuarios', 'cache_dados', 'exodo_sync_conflitos',
                     'bridge_config', 'bridge_commands', 'bridge_status'):
        if proibida in tabelas:
            return falhou(f'{proibida} não deveria ser copiada')
    if not L._tabela_proibida('bridge_qualquer_coisa_nova'):
        return falhou('prefixo bridge_ deveria bloquear tabela nova')
    return True


def teste_apagados_respeitam_protegidos():
    """Apagado do par não derruba alteração pendente nem empresa alheia."""
    print('4) apagados do par respeitam protegidos e a empresa ativa')
    conn = FakeConn(rowcounts=[1])
    registros = [
        ('P1', 'E1', '2026-09-29T10:00:00+00:00'),   # protegido (pendente)
        ('P2', 'E1', '2026-09-29T10:01:00+00:00'),   # apaga
        ('P3', 'E9', '2026-09-29T10:02:00+00:00'),   # outra empresa: ignora
    ]
    apagados, protegidos = L._aplicar_apagados(
        conn, 'produtos', registros, {'produtos': {'P1': 'alteracao_local_pendente'}}, 'E1')
    if protegidos != 1:
        return falhou(f'esperava 1 protegido, veio {protegidos}')
    if apagados != 1:
        return falhou(f'esperava 1 apagado, veio {apagados}')
    params = sqls_de(conn, 'DELETE FROM')
    if not params:
        return falhou('nenhum DELETE foi montado')
    enviados = params[0][0]
    if enviados != ['P2']:
        return falhou(f'apagou os ids errados: {enviados}')
    # nunca registra um tombstone próprio: isto é réplica, não apagamento do usuário
    if not any("sync_mode = 'on'" in s for s, _ in conn.sqls):
        return falhou('o DELETE não rodou com exodo.sync_mode=on')
    return True


def teste_primeiro_contato_comeca_de_agora():
    """No 1º contato o cursor é fixado em AGORA e nada é puxado."""
    print('5) 1º contato grava o cursor de agora e não puxa histórico')
    chamadas = []
    original = S.gravar_registros_locais
    S.gravar_registros_locais = (
        lambda *a, **k: (chamadas.append(a), (0, []))[1])
    try:
        conn = FakeConn(respostas=[None, None])          # cursor upd, cursor del
        conn_par = FakeConn(respostas=[COLUNAS_PRODUTO])  # só a leitura de colunas
        contagem = L._puxar_tabela(
            conn, conn_par, 'produtos', CFG, 'PC-2', 'E1', {}, '2026-09-29T12:00:00+00:00')
        if chamadas:
            return falhou('puxou registros no primeiro contato')
        if contagem['recebidos']:
            return falhou(f'contagem deveria ser zero: {contagem}')
        inserts = sqls_de(conn, 'INSERT INTO _sync_controle')
        if not inserts:
            return falhou('o cursor não foi gravado')
        if inserts[0] != ('lan_produtos__PC-2', '2026-09-29T12:00:00+00:00'):
            return falhou(f'cursor errado: {inserts[0]}')
    finally:
        S.gravar_registros_locais = original
    return True


def teste_ciclo_aplica_e_avanca():
    """Ciclo normal: aplica o que mudou no par e avança o cursor."""
    print('6) ciclo normal aplica as mudanças e avança o cursor')
    aplicados = []
    original = S.gravar_registros_locais
    def _gravar(conn_, tabela, linhas, empresa_filtro=None, bloqueados=None):
        aplicados.append((tabela, linhas, empresa_filtro, bloqueados))
        return len(linhas), [str(l['id']) for l in linhas]

    S.gravar_registros_locais = _gravar
    try:
        conn = FakeConn(respostas=[
            ('2026-09-01T00:00:00+00:00',),          # cursor de updates
            ('2026-09-01T00:00:00+00:00',),          # cursor de apagados
        ])
        conn_par = FakeConn(respostas=[
            COLUNAS_PRODUTO,
            [{'id': 'P1', 'nome': 'coca', 'empresa_id': 'E1',
              'updated_at': '2026-09-29T11:00:00+00:00'}],
            (True,),                                  # tabela de apagados existe
            [],
        ])
        contagem = L._puxar_tabela(
            conn, conn_par, 'produtos', CFG, 'PC-2', 'E1', {}, '2026-09-29T12:00:00+00:00')
        if not aplicados:
            return falhou('nada foi aplicado')
        tabela, linhas, empresa_filtro, bloqueados = aplicados[0]
        if tabela != 'produtos' or empresa_filtro != 'E1':
            return falhou(f'aplicação errada: {aplicados[0]}')
        if contagem['recebidos'] != 1:
            return falhou(f'esperava 1 recebido, veio {contagem}')
        # Primeiro INSERT é o cursor dos registros novos, com o carimbo do
        # último registro aplicado (o do par).
        inserts = sqls_de(conn, 'INSERT INTO _sync_controle')
        if not inserts or inserts[0] != ('lan_produtos__PC-2',
                                         '2026-09-29T11:00:00+00:00'):
            return falhou(f'cursor não avançou: {inserts}')
    finally:
        S.gravar_registros_locais = original
    return True


def teste_ordem_deterministica():
    """A leitura das mudanças do par ordena por data E por id.

    Dentro de uma mesma transação o PostgreSQL dá o mesmo NOW() a várias
    linhas (o app grava em blocos de 100). Ordenar só pela data deixava a
    ordem das linhas empatadas indefinida; o desempate por id torna o
    resultado determinístico.
    """
    print('6.1) leitura das mudanças ordena por (data, id)')
    conn_par = FakeConn()
    L._buscar_mudancas_do_par(
        conn_par, 'produtos', 'updated_at', 'timestamp with time zone',
        '2026-01-01T00:00:00+00:00', 'E1', True, 2000, tem_id=True)
    sqls = [s for s, _ in conn_par.sqls]
    if not sqls:
        return falhou('nenhuma consulta foi montada')
    sql = sqls[0]
    if 'ORDER BY "updated_at" ASC, "id" ASC' not in sql:
        return falhou(f'ordem sem desempate por id: {sql}')

    # Tabela sem id: o desempate por id não pode ser acrescentado.
    conn_par2 = FakeConn()
    L._buscar_mudancas_do_par(
        conn_par2, 'config', 'updated_at', 'timestamp with time zone',
        '2026-01-01T00:00:00+00:00', None, False, 2000, tem_id=False)
    sql2 = [s for s, _ in conn_par2.sqls][0]
    if '"id" ASC' in sql2:
        return falhou(f'não deveria ordenar por id sem id: {sql2}')
    return True


def teste_par_fora_do_ar_nao_levanta():
    """Par desligado devolve erro no resumo, sem derrubar o ciclo."""
    print('7) par fora do ar devolve erro no resumo (não levanta exceção)')
    original_conn = L.conectar_no_par
    L.conectar_no_par = lambda cfg, timeout=None: (_ for _ in ()).throw(
        RuntimeError('connection refused'))
    try:
        conn = FakeConn()
        resumo = L.sincronizar_com_par(conn, CFG, tabelas=['produtos'])
        if resumo is None:
            return falhou('deveria devolver um resumo com erro')
        if not resumo['erro'] or 'sem conexão' not in resumo['erro']:
            return falhou(f'erro não foi registrado: {resumo}')
        if resumo['recebidos'] or resumo['tabelas']:
            return falhou(f'nada deveria ser sincronizado: {resumo}')
    finally:
        L.conectar_no_par = original_conn
    return True


def teste_tombstones_antigos_sao_removidos():
    """A retenção apaga só o que passou da janela configurada."""
    print('8) retenção remove apagados antigos')
    # 1ª consulta: to_regclass (a tabela existe); 2ª: o DELETE da retenção.
    conn = FakeConn(respostas=[(True,)], rowcounts=[1, 7])
    removidos = L.purgar_tombstones_antigos(conn, dias=15)
    if removidos != 7:
        return falhou(f'esperava 7 removidos, veio {removidos}')
    deletes = sqls_de(conn, 'DELETE FROM _exodo_deletados')
    if deletes[0] != ('15',):
        return falhou(f'janela errada: {deletes[0]}')
    return True


def teste_endereco_reconhece_ip_e_nome():
    """`_eh_ip` distingue endereço de nome (inclusive IPv6)."""
    print('10) _eh_ip separa IP de nome')
    for ip in ('192.168.0.12', '10.0.0.9', '::1', 'fe80::1'):
        if not L._eh_ip(ip):
            return falhou(f'{ip} deveria ser tratado como IP')
    for nome in ('PC-CAIXA-2', 'DESKTOP-CM5TIL7.local', '', '   '):
        if L._eh_ip(nome):
            return falhou(f'{nome!r} não deveria ser tratado como IP')
    return True


def teste_nome_do_par_e_resolvido_para_ipv4():
    """O nome do par vira o IPv4 dele; o cache evita consultar a cada ciclo."""
    print('11) nome do par é resolvido para IPv4 (e fica em cache)')
    # IP informado direto: nada a resolver.
    if L.resolver_host('192.168.0.12') != '192.168.0.12':
        return falhou('um IP não deveria passar pelo resolvedor')

    L._CACHE_IPS.clear()
    consultas = []
    original = L.socket.getaddrinfo

    def falso_getaddrinfo(nome, porta, familia=None, tipo=None):
        consultas.append((nome, familia))
        if nome.upper() == 'PC-CAIXA-2':
            return [(2, 1, 0, '', ('192.168.0.117', 0))]
        raise OSError('nao resolvido')

    L.socket.getaddrinfo = falso_getaddrinfo
    try:
        cfg = {'host': 'PC-CAIXA-2', 'port': '5432', 'dbname': 'd',
               'user': 'u', 'password': 'x'}
        ip = L.ip_do_par(cfg)
        if ip != '192.168.0.117':
            return falhou(f'resolveu errado: {ip}')
        # Só a IPv4 é pedida: o IPv6 link-local do Windows não serve para o banco.
        if not consultas or consultas[0][1] != L.socket.AF_INET:
            return falhou(f'não pediu AF_INET: {consultas}')
        # Segunda chamada usa o cache (nenhuma consulta nova).
        quantas = len(consultas)
        if L.ip_do_par(cfg) != '192.168.0.117' or len(consultas) != quantas:
            return falhou('o cache não foi usado')

        # Nome inexistente: devolve None (e o cache não guarda lixo).
        L._CACHE_IPS.clear()
        if L.ip_do_par({'host': 'PC-QUE-NAO-EXISTE'}) is not None:
            return falhou('nome inexistente deveria devolver None')
    finally:
        L.socket.getaddrinfo = original
        L._CACHE_IPS.clear()
    return True


def teste_conectar_no_par_usa_o_ip_resolvido():
    """A conexão recebe o IP resolvido (não o nome) — e falha clara sem resolver."""
    print('12) conectar_no_par conecta pelo IP resolvido do nome')
    L._CACHE_IPS.clear()
    original = L.psycopg2.connect
    chamadas = []
    L.psycopg2.connect = lambda **kw: chamadas.append(kw) or 'conexao'
    L._CACHE_IPS['pc-caixa-2'] = '192.168.0.117'
    try:
        cfg = {'host': 'PC-CAIXA-2', 'port': '5432', 'dbname': 'exodo_db',
               'user': 'exodo_user', 'password': 'x'}
        L.conectar_no_par(cfg)
        if not chamadas or chamadas[0]['host'] != '192.168.0.117':
            return falhou(f'conectou sem usar o IP: {chamadas}')
        if chamadas[0]['application_name'] != 'exodo-lan-par':
            return falhou(f'application_name errado: {chamadas[0]}')

        # Nome que não resolve: erro explicativo, sem tentar conectar.
        L._CACHE_IPS.clear()
        try:
            L.conectar_no_par({'host': 'PC-INEXISTENTE', 'port': '5432',
                               'dbname': 'd', 'user': 'u', 'password': 'x'})
            return falhou('deveria levantar erro para nome não resolvido')
        except RuntimeError as e:
            if 'não achei o computador' not in str(e):
                return falhou(f'mensagem pouco clara: {e}')
        if len(chamadas) != 1:
            return falhou('não deveria ter tentado conectar sem resolver')
    finally:
        L.psycopg2.connect = original
        L._CACHE_IPS.clear()
    return True


def teste_config_aceita_nome_do_par():
    """O .env pode trazer o NOME no PAR_HOST (o campo é livre)."""
    print('13) PAR_HOST aceita nome do computador')
    cfg = L.config_do_par({'PAR_HOST': 'PC-CAIXA-2', 'DB_NAME': 'exodo_db'})
    if not cfg or cfg['host'] != 'PC-CAIXA-2':
        return falhou(f'nome não foi aceito: {cfg}')
    if cfg['nome'] != 'PC-CAIXA-2':
        return falhou(f'rótulo padrão deveria ser o nome: {cfg}')
    return True


COLUNAS_EMPRESA = [('id', 'text'), ('razao_social', 'text'),
                   ('empresa_id', 'text'),
                   ('updated_at', 'timestamp with time zone')]


def teste_catalogo_de_empresas_passa_sem_filtro():
    """`empresas` e puxada SEM o filtro de empresa; as outras tabelas, com ele.

    Em `empresas` cada linha aponta para ela mesma (empresa_id = id). Filtrar por
    `empresa_id = empresa_ativa` faria cada PC baixar so a propria empresa — que
    e o "so aparece uma empresa" na tela de selecao.
    """
    print('14) cadastro de empresas passa sem o filtro de empresa ativa')
    original = S.gravar_registros_locais
    capturado = {}

    def falso_gravar(conn_, tabela, linhas, empresa_filtro=None, bloqueados=None):
        capturado['tabela'] = tabela
        capturado['empresa_filtro'] = empresa_filtro
        capturado['linhas'] = linhas
        return len(linhas), [str(l['id']) for l in linhas]

    S.gravar_registros_locais = falso_gravar
    try:
        # ── empresas: SEM filtro ────────────────────────────────────────────
        # 1a resposta = cursor de leitura; 2a = comparacao "ja esta igual?"
        # (SELECT * ... ANY) devolvendo vazio; 3a = cursor de apagados.
        conn = FakeConn(respostas=[('2026-09-01T00:00:00+00:00',),
                                   [],
                                   ('2026-09-01T00:00:00+00:00',)])
        conn_par = FakeConn(respostas=[
            COLUNAS_EMPRESA,
            [{'id': 'E2', 'razao_social': 'Outra empresa', 'empresa_id': 'E2',
              'updated_at': '2026-09-29T11:00:00+00:00'}],
            (False,),                                  # sem tabela de apagados
        ])
        L._puxar_tabela(conn, conn_par, 'empresas', CFG, 'PC-2', 'E1', {},
                        '2026-09-29T12:00:00+00:00')
        if capturado.get('empresa_filtro') is not None:
            return falhou('empresas ainda vai com filtro de empresa: %r'
                          % capturado.get('empresa_filtro'))
        sqls = [s for s, _ in conn_par.sqls if s.startswith('SELECT * FROM')]
        if not sqls:
            return falhou('nenhuma leitura foi montada')
        if 'empresa_id =' in sqls[0]:
            return falhou('a leitura de empresas ainda filtra empresa_id: %s'
                          % sqls[0])
        if capturado.get('linhas') != [
                {'id': 'E2', 'razao_social': 'Outra empresa',
                 'empresa_id': 'E2',
                 'updated_at': '2026-09-29T11:00:00+00:00'}]:
            return falhou('a linha de OUTRA empresa nao veio: %r'
                          % capturado.get('linhas'))
        # Le do ZERO: um cursor velho esconderia empresas antigas do par.
        params = _params_da_leitura(conn_par)
        if not params or params[0] != '1970-01-01T00:00:00+00:00':
            return falhou('empresas nao leu do inicio, leu desde: %r'
                          % (params[0] if params else None))
        # E nao grava cursor (senao o proximo ciclo ja esconderia o que faltava).
        # O cursor de APAGADOS (`lan_del_...`) e normal e continua valendo.
        chave_leitura = L._chave_cursor('empresas', 'PC-2')
        for _s, params in conn.sqls:
            if not _s.startswith('INSERT INTO _sync_controle'):
                continue
            chave = params[0] if params else ''
            if chave == chave_leitura:
                return falhou('a tabela empresas nao pode gravar cursor de leitura')

        # ── produtos: continua filtrado (a trava anti-mistura nao pode cair) ─
        capturado.clear()
        conn = FakeConn(respostas=[('2026-09-01T00:00:00+00:00',),
                                   ('2026-09-01T00:00:00+00:00',)])
        conn_par = FakeConn(respostas=[
            COLUNAS_PRODUTO,
            [{'id': 'P1', 'nome': 'coca', 'empresa_id': 'E1',
              'updated_at': '2026-09-29T11:00:00+00:00'}],
            (False,),
        ])
        L._puxar_tabela(conn, conn_par, 'produtos', CFG, 'PC-2', 'E1', {},
                        '2026-09-29T12:00:00+00:00')
        if capturado.get('empresa_filtro') != 'E1':
            return falhou('produtos perdeu o filtro de empresa: %r'
                          % capturado.get('empresa_filtro'))
        sqls = [s for s, _ in conn_par.sqls if s.startswith('SELECT * FROM')]
        if 'empresa_id = %s' not in sqls[0]:
            return falhou('a leitura de produtos deixou de filtrar: %s'
                          % sqls[0])
        # Produtos continua incremental pelo cursor.
        params = _params_da_leitura(conn_par)
        if not params or params[0] != '2026-09-01T00:00:00+00:00':
            return falhou('produtos nao leu do cursor: %r'
                          % (params[0] if params else None))
        if not sqls_de(conn, 'INSERT INTO _sync_controle'):
            return falhou('produtos deveria avancar o cursor')
    finally:
        S.gravar_registros_locais = original
    return True


def teste_apagado_de_outra_empresa_tambem_nao_filtrado():
    """O apagado do par nao e barrado pelo filtro em `empresas`."""
    print('15) apagados de empresas nao sao barrados pelo filtro de empresa')
    conn = FakeConn(rowcounts=[1])
    registros = [('E9', 'E9_QUALQUER', '2026-09-29T10:00:00+00:00')]

    # Empresas: apaga mesmo com empresa_ativa diferente (cada uma e dona de si).
    apagados, _ = L._aplicar_apagados(
        conn, 'empresas', registros, {}, 'E1')
    if apagados != 1:
        return falhou('o apagado da empresas foi barrado: %d' % apagados)

    # Produtos: continua protegido — dado de outra empresa nao pode ser apagado.
    conn2 = FakeConn(rowcounts=[1])
    apagados2, protegidos2 = L._aplicar_apagados(
        conn2, 'produtos', registros, {}, 'E1')
    if apagados2 != 0:
        return falhou('apagou produto de outra empresa: %d' % apagados2)
    if protegidos2 != 0:
        return falhou('protegidos nao e o contador certo aqui')
    params = sqls_de(conn2, 'DELETE FROM')
    if params:
        return falhou('nao deveria ter montado DELETE para outra empresa')
    return True


def teste_gravacao_aceita_empresas_de_qualquer_dono():
    """`gravar_registros_locais` nao rejeita linha de outra empresa em `empresas`."""
    print('16) gravacao local aceita o cadastro inteiro de empresas')
    original_colunas = S.get_colunas_e_tipos_tabela
    S.get_colunas_e_tipos_tabela = lambda conn, tabela: {
        'id': 'text', 'empresa_id': 'text', 'razao_social': 'text'}
    try:
        linhas = [{'id': 'E2', 'empresa_id': 'E2',
                   'razao_social': 'Outra empresa'}]

        importados, aplicados = S.gravar_registros_locais(
            FakeConn(), 'empresas', linhas, empresa_filtro='E1')
        if importados != 1:
            return falhou('cadastro de empresas rejeitou linha: %d' % importados)
        if aplicados != ['E2']:
            return falhou('a lista de aplicadas ficou errada: %r' % aplicados)

        # Tabela normal: a trava continua valendo.
        importados2, aplicados2 = S.gravar_registros_locais(
            FakeConn(), 'produtos', linhas, empresa_filtro='E1')
        if importados2 != 0:
            return falhou('produto de outra empresa foi gravado: %d'
                          % importados2)
        if aplicados2:
            return falhou('nada devia ter sido aplicado: %r' % aplicados2)
    finally:
        S.get_colunas_e_tipos_tabela = original_colunas
    return True


def teste_todas_as_cores_existem():
    """Toda cor `Colors.X` citada nos scripts existe na classe.

    Motivo: a LAN pedia `Colors.CYAN`, que não existia. O erro só aparecia no
    ciclo de verdade — e no `__init__` do tray, que usa CYAN na mensagem de
    LAN desligada. O argumento é avaliado ANTES do print_log, então nenhum
    monkeypatch de log escondia o defeito. Esta varredura estática impede que
    uma cor nova volte a escapar.
    """
    import re
    print('9) toda cor Colors.* usada nos scripts existe')
    faltando = set()
    for arq in ('sincronizador_lan.py', 'sincronizador_tray.py',
                'sincronizar_local_supabase.py'):
        try:
            with open(arq, encoding='utf-8') as f:
                texto = f.read()
        except Exception:
            continue
        for nome in re.findall(r'Colors\.([A-Z_]+)', texto):
            if not hasattr(S.Colors, nome):
                faltando.add(f'{arq}: Colors.{nome}')
    if faltando:
        return falhou(f'cores inexistentes: {sorted(faltando)}')
    return True


def teste_descartar_iguais_jsonb_e_dict_row():
    """`_descartar_iguais` tem de casar `jsonb` e linhas com cursor de dict.

    Motivo (bug REAL em producao): o catalogo de empresas e relido inteiro a
    cada ciclo. Com a comparacao errada, `[]` (lista) nunca casava com `'[]'`
    (texto) e toda empresa parecia alterada: o PC reescrevia as 4 empresas a
    cada 2,5 s, para sempre. Do jeito antigo, alem disso, `dict(zip(nomes,
    linha))` devolvia nome->nome quando a conexao usava RealDictCursor.

    Aqui: (a) linha identica some, (b) jsonb lista == jsonb texto, (c) mudanca
    real continua passando, (d) linhas de cursor com `keys` (RealDictRow).
    """
    print('17) descarte de linhas iguais (jsonb e cursor de dict)')

    class CursorDict(FakeCursor):
        """FakeCursor que devolve linhas parecidas com RealDictRow."""

        def fetchall(self):
            # As respostas ja vem como dicionarios (com keys()), que e
            # exatamente o que o psycopg2 devolve com RealDictCursor.
            return [dict(v) for v in (self._ultimo or [])]

    class ConnDict(FakeConn):
        def cursor(self, cursor_factory=None):
            return CursorDict(self)

    linha_do_par = {'id': 'E1', 'razao_social': 'Exodo Systems LTDA',
                    'telasPermitidas': ['clientes', 'produtos'],
                    'updated_at': '2026-10-03T10:00:00+00:00'}
    # No banco local o MESMO registro, mas com o jsonb vindo em texto: e assim
    # que ele volta do psycopg2 num lado e do outro.
    local = {'id': 'E1', 'razao_social': 'Exodo Systems LTDA',
             'telasPermitidas': '["clientes", "produtos"]',
             'updated_at': '2026-10-03T10:00:00+00:00'}

    conn = ConnDict(respostas=[[local]])
    if L._descartar_iguais(conn, 'empresas', [linha_do_par]):
        return falhou('linha identica (so o jsonb difere no tipo) '
                      'foi mantida: voltaria a reescrever a cada ciclo')

    # Agora o CONTEUDO muda: a linha tem de passar, senão a empresa nunca
    # atualiza no outro PC.
    conn = ConnDict(respostas=[[dict(local, razao_social='NOME NOVO')]])
    passou = L._descartar_iguais(conn, 'empresas', [linha_do_par])
    if [l['id'] for l in passou] != ['E1']:
        return falhou('alteracao real de empresa nao passou: %r' % passou)

    # So o updated_at local diferente conta como mudanca: e o que faz o ciclo
    # convergir (um write, e no seguinte ja bate).
    conn = ConnDict(respostas=[[dict(local, updated_at='2026-10-03T12:00:00+00:00')]])
    if len(L._descartar_iguais(conn, 'empresas', [linha_do_par])) != 1:
        return falhou('updated_at divergente deveria gerar uma gravacao '
                      'e nao mais que isso')
    return True


def teste_fila_nao_trava_a_lan():
    """A fila de pendencia nao trava a LAN; conflito aberto continua bloqueando.

    Bug REAL em producao (03/10): o item "coca cola" ficou com preco 24,00 num
    PC e 2,00 no outro, sem convergir. Motivo: a LAN usava
    `alteracao_local_pendente` como bloqueio. Essa fila so e limpa depois de um
    upload bem-sucedido - e com a nuvem em HTTP 402 ela nunca e limpa. Resultado:
    os dois PCs recusavam a versao um do outro para sempre.

    A fila nao e um veredito de "quem tem razao": contra a nuvem ela protege a
    edicao local (sobe antes de descer); contra outro PC os dois bancos sao
    pares e quem decide e o carimbo de data. Por isso `incluir_pendentes=False`
    na LAN - e por isso um conflito ABERTO (que o usuario ainda nao decidiu)
    continua bloqueando.
    """
    print('18) a fila de pendencia nao trava a LAN e o conflito aberto bloqueia')

    # (a) assinatura: a LAN NAO pode pedir as pendentes.
    vistos = []

    def _fake_bloqueados(conn, incluir_pendentes=True):
        vistos.append(incluir_pendentes)
        return {}

    original = S.ids_bloqueados_no_download
    original_conn = L.conectar_no_par
    try:
        S.ids_bloqueados_no_download = _fake_bloqueados
        # Sem isto o ciclo nem chega na lista de bloqueados: ele abre a
        # conexao com o par ANTES e devolve no primeiro erro.
        L.conectar_no_par = lambda cfg, timeout=None: FakeConn(respostas=[[]])
        conn_local = FakeConn(respostas=[[]])
        L.sincronizar_com_par(conn_local,
                              cfg={'host': '10.0.0.9', 'nome': 'PC-B',
                                   'port': 5432, 'user': 'u', 'password': 'p',
                                   'dbname': 'd', 'dias_tombstone': 30,
                                   'inicial_completo': False},
                              tabelas=[])
    finally:
        S.ids_bloqueados_no_download = original
        L.conectar_no_par = original_conn
    if vistos != [False]:
        return falhou(f'a LAN deveria pedir apenas conflitos abertos, '
                      f'pediu incluir_pendentes={vistos}')

    # (b) `incluir_pendentes=False` NAO pode esconder o conflito aberto: e o
    # unico motivo de bloqueio que sobra, e sem ele o app perderia a edicao
    # parqueada assim que o outro PC mandasse a versao dele.
    conn = FakeConn(respostas=[[('produtos', 'P1'), ('nfces', 'N9')]])
    bloqueados = IDS_BLOQUEADOS_REAL(conn, incluir_pendentes=False)
    if bloqueados != {'produtos': {'P1': 'conflito_aberto'},
                      'nfces': {'N9': 'conflito_aberto'}}:
        return falhou(f'conflito aberto nao bloqueou: {bloqueados}')

    # E a fila continua valendo contra a NUVEM (que é quem reescreve de cima):
    # com `incluir_pendentes` (padrão) a pendência aparece.
    respostas = [[(True,)], [('produtos', 'P1')], [('produtos', 'P2')]]
    original_cache = S._tem_tabela_log_cache
    S._tem_tabela_log_cache = None
    try:
        na_nuvem = IDS_BLOQUEADOS_REAL(
            FakeConn(respostas=respostas), incluir_pendentes=True)
    finally:
        S._tem_tabela_log_cache = original_cache
    if na_nuvem.get('produtos', {}).get('P1') != 'alteracao_local_pendente':
        return falhou(f'a nuvem precisa ver a pendencia: {na_nuvem}')
    if na_nuvem.get('produtos', {}).get('P2') != 'conflito_aberto':
        return falhou(f'a nuvem tambem precisa ver o conflito: {na_nuvem}')
    return True


def teste_cursor_nao_passa_por_cima_de_protegido():
    """Linha barrada (conflito aberto) segura o cursor — ela volta no próximo ciclo.

    Bug REAL em producao (03/10): o ciclo lia do par, a gravacao barrava a linha
    (conflito aberto) e o cursor era Advancedado até a última linha lida. O dado
    ficava "visto" para sempre: quando o usuário decidisse o conflito, aquele
    registro nunca mais seria lido e os dois bancos nunca convergiriam.

    Aqui o par manda DUAS linhas, a mais NOVA bloqueada e a mais VELHA aplicada.
    O cursor tem de parar na linha aplicada, não na última do lote.
    """
    print('19) linha protegida segura o cursor (ela volta no proximo ciclo)')

    def _gravar(conn_, tabela, linhas, empresa_filtro=None, bloqueados=None):
        # Só a linha antiga entrou; a nova estava em conflito aberto.
        aplicadas = [l for l in linhas if l['id'] == 'P_ANTIGO']
        return len(aplicadas), [str(l['id']) for l in aplicadas]

    original = S.gravar_registros_locais
    S.gravar_registros_locais = _gravar
    try:
        conn = FakeConn(respostas=[
            ('2026-09-01T00:00:00+00:00',),          # cursor de updates
            ('2026-09-01T00:00:00+00:00',),          # cursor de apagados
        ])
        conn_par = FakeConn(respostas=[
            COLUNAS_PRODUTO,
            [
                {'id': 'P_ANTIGO', 'nome': 'coca', 'empresa_id': 'E1',
                 'updated_at': '2026-09-29T11:00:00+00:00'},
                {'id': 'P_NOVO', 'nome': 'coca', 'empresa_id': 'E1',
                 'updated_at': '2026-09-29T23:59:00+00:00'},
            ],
            (True,),
            [],
        ])
        contagem = L._puxar_tabela(
            conn, conn_par, 'produtos', CFG, 'PC-2', 'E1', {}, '2026-09-29T12:00:00+00:00')
    finally:
        S.gravar_registros_locais = original

    if contagem['recebidos'] != 1:
        return falhou(f'esperava 1 recebido, veio {contagem}')
    inserts = sqls_de(conn, 'INSERT INTO _sync_controle')
    if not inserts:
        return falhou('o cursor nao foi gravado')
    _, valor = inserts[0]
    if valor == '2026-09-29T23:59:00+00:00':
        return falhou('o cursor passou por cima da linha protegida: '
                      'ela nunca mais seria lida')
    if valor != '2026-09-29T11:00:00+00:00':
        return falhou(f'cursor parou na linha errada: {valor!r}')

    # Controle: quando NADA foi aplicado, o cursor não se move (senão o dado
    # sumiria sem nunca ter sido gravado aqui).
    original = S.gravar_registros_locais
    S.gravar_registros_locais = (
        lambda *a, **k: (0, []))
    try:
        conn = FakeConn(respostas=[
            ('2026-09-01T00:00:00+00:00',),
            ('2026-09-01T00:00:00+00:00',),
        ])
        conn_par = FakeConn(respostas=[
            COLUNAS_PRODUTO,
            [{'id': 'P1', 'nome': 'coca', 'empresa_id': 'E1',
              'updated_at': '2026-09-29T11:00:00+00:00'}],
            (True,),
            [],
        ])
        L._puxar_tabela(
            conn, conn_par, 'produtos', CFG, 'PC-2', 'E1', {}, '2026-09-29T12:00:00+00:00')
    finally:
        S.gravar_registros_locais = original
    if sqls_de(conn, 'INSERT INTO _sync_controle'):
        return falhou('o cursor avancou sem nenhum registro gravado')
    return True


def main():
    testes = [
        teste_lan_desligada_sem_host,
        teste_config_herda_credenciais_locais,
        teste_tabelas_proibidas,
        teste_apagados_respeitam_protegidos,
        teste_primeiro_contato_comeca_de_agora,
        teste_ciclo_aplica_e_avanca,
        teste_ordem_deterministica,
        teste_par_fora_do_ar_nao_levanta,
        teste_tombstones_antigos_sao_removidos,
        teste_endereco_reconhece_ip_e_nome,
        teste_nome_do_par_e_resolvido_para_ipv4,
        teste_conectar_no_par_usa_o_ip_resolvido,
        teste_config_aceita_nome_do_par,
        teste_catalogo_de_empresas_passa_sem_filtro,
        teste_apagado_de_outra_empresa_tambem_nao_filtrado,
        teste_gravacao_aceita_empresas_de_qualquer_dono,
        teste_todas_as_cores_existem,
        teste_descartar_iguais_jsonb_e_dict_row,
        teste_fila_nao_trava_a_lan,
        teste_cursor_nao_passa_por_cima_de_protegido,
    ]

    # Silencia o log do sincronizador durante os testes.
    original_log = S.print_log
    S.print_log = lambda *a, **k: None
    # O ciclo chama duas consultas de apoio; nos testes elas não têm banco.
    originais = {
        'obter_empresa_ativa': S.obter_empresa_ativa,
        'ids_bloqueados_no_download': S.ids_bloqueados_no_download,
        'garantir_tabela_controle': S.garantir_tabela_controle,
    }
    S.obter_empresa_ativa = lambda conn: 'E1'
    # A LAN chama com `incluir_pendentes=False`; o stub precisa aceitar.
    S.ids_bloqueados_no_download = lambda conn, incluir_pendentes=True: {}
    S.garantir_tabela_controle = lambda conn: None

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
        for nome, valor in originais.items():
            setattr(S, nome, valor)

    print(f'\n{ok}/{len(testes)} testes passaram')
    return 0 if ok == len(testes) else 1


if __name__ == '__main__':
    sys.exit(main())

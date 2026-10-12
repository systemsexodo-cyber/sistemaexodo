"""Sincronização DIRETA entre os PCs na rede local (par no PostgreSQL).

Por que existe: o sincronizador da nuvem leva tudo para o Supabase e traz de
volta. Isso funciona, mas quando a internet cai os PCs da MESMA loja param de
se ver, mesmo estando na mesma rede. Este módulo faz os bancos locais
conversarem direto:

  - abre uma conexão no PostgreSQL DO OUTRO PC (LAN) e lê o que mudou desde a
    última visita, pela coluna de timestamp da tabela;
  - lê também os APAGADOS do outro PC (`_exodo_deletados`), senão a linha
    apagada lá continuaria viva aqui (e seria reenviada — a "ressurreição");
  - aplica aqui com as MESMAS travas do download da nuvem: filtro de empresa e
    "nunca sobrescrever alteração local pendente nem conflito aberto". Isso é
    feito reusando `S.gravar_registros_locais` + `S.ids_bloqueados_no_download`;
  - a NUVEM continua sendo a fonte de verdade: nada é enviado daqui para o
    outro PC; cada um PUXA o que o outro tem. Com os dois rodando, os bancos
    convergem, e as linhas aplicadas aqui não entram na fila da nuvem (são
    réplica — quem envia a original é o PC de origem).

Configuração no `.env` (do lado de cada PC):

    PAR_HOST=PC-CAIXA-2           # NOME do OUTRO PC (recomendado) ou o IP dele
    PAR_PORT=5432                 # padrão 5432
    PAR_DB_NAME=exodo_db          # padrão: DB_NAME
    PAR_DB_USER=exodo_user        # padrão: DB_USER
    PAR_DB_PASSWORD=...           # padrão: DB_PASSWORD
    PAR_NOME=PC-CAIXA-2           # rótulo do par (no cursor e no log)
    LAN_SYNC=true                 # liga/desliga (padrão: ligado quando há PAR_HOST)
    LAN_DIAS_TOMBSTONE=30         # retenção dos apagados (padrão 30 dias)
    LAN_INICIAL_COMPLETO=false    # true = no 1º contato puxa o histórico inteiro

O PostgreSQL do outro PC precisa aceitar conexão da rede local
(`listen_addresses` + `pg_hba.conf`). Ver `scripts/configurar_lan_postgres.ps1`.

Rodar um ciclo só, para diagnóstico:

    .venv\\Scripts\\python.exe sincronizador_lan.py
"""

import json
import os
import socket
import sys
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import RealDictCursor

import sincronizar_local_supabase as S

# ─────────────────────────────────────────────────────────────────────────────
# Regras fixas
# ─────────────────────────────────────────────────────────────────────────────

# Tabelas que NUNCA podem ser copiadas entre PCs.
#
# `usuarios` é o caso mais importante: as senhas existem SÓ no banco local e a
# própria sincronização da nuvem já exclui essa tabela do download. Copiar
# usuários de um PC para o outro espalharia credencial pela rede.
TABELAS_PROIBIDAS = {
    'usuarios',
    'cache_dados',
    'exodo_sync_conflitos',
    'exodo_config',
    'sync_status',
    'configuracoes_locais',
    'sync_logs',
}

# Prefixos que NUNCA podem ser copiados. Existe além da lista exata porque
# uma lista fechada envelhece: `bridge_config` (a distribuição de versões do
# app) escapou por não estar escrita aqui e era copiada de um PC para o outro.
PREFIXOS_PROIBIDOS = ('bridge_',)


def _tabela_proibida(nome):
    """A tabela pode ser copiada entre os PCs?"""
    if nome in TABELAS_PROIBIDAS:
        return True
    return any(str(nome).startswith(p) for p in PREFIXOS_PROIBIDOS)

# Colunas de data, na ordem de preferência (mesma ordem do sincronizador).
COLUNAS_DE_DATA = ('updated_at', 'created_at', 'criado_em', 'data_alteracao',
                   'data_venda', 'data')

LOTE_PADRAO = 2000
DIAS_TOMBSTONE_PADRAO = 30
TIMEOUT_CONEXAO_S = 5

# Quanto esperar ao traduzir o NOME do par para IP. Curto de propósito: o
# ciclo da LAN roda em paralelo com o da nuvem e não pode travar esperando DNS.
TIMEOUT_RESOLVE_S = 4

# Cache nome -> IP, para não consultar o resolvedor a cada 2 segundos. O IP do
# par muda raramente; quando muda, a conexão falha, o cache é descartado e a
# próxima tentativa resolve de novo — é o que faz a LAN sobreviver ao DHCP.
_CACHE_IPS = {}


# ─────────────────────────────────────────────────────────────────────────────
# Configuração
# ─────────────────────────────────────────────────────────────────────────────

def _ligado(valor, padrao=False):
    """Interpreta um valor de .env como booleano."""
    if valor is None or str(valor).strip() == '':
        return padrao
    return str(valor).strip().lower() in ('1', 'true', 'sim', 'yes', 'on')


def config_do_par(env=None):
    """Config do outro PC, lida do .env.

    Devolve `None` quando a sincronização LAN não está ligada ou não há
    `PAR_HOST` configurado — nesse caso o chamador simplesmente ignora a LAN e
    o ciclo da nuvem roda como sempre.
    """
    env = env if env is not None else os.environ
    host = (env.get('PAR_HOST') or '').strip()
    if not host:
        return None
    if not _ligado(env.get('LAN_SYNC'), padrao=True):
        return None
    try:
        dias = int(str(env.get('LAN_DIAS_TOMBSTONE') or DIAS_TOMBSTONE_PADRAO).strip())
    except Exception:
        dias = DIAS_TOMBSTONE_PADRAO
    return {
        'host': host,
        'port': (env.get('PAR_PORT') or '5432').strip(),
        'dbname': (env.get('PAR_DB_NAME') or env.get('DB_NAME') or '').strip(),
        'user': (env.get('PAR_DB_USER') or env.get('DB_USER') or '').strip(),
        'password': env.get('PAR_DB_PASSWORD') or env.get('DB_PASSWORD') or '',
        'nome': (env.get('PAR_NOME') or host).strip(),
        'dias_tombstone': dias,
        'inicial_completo': _ligado(env.get('LAN_INICIAL_COMPLETO'), padrao=False),
    }


def _eh_ip(host):
    """O endereço informado já é um IP (IPv4 ou IPv6)?"""
    texto = str(host or '').strip()
    if not texto:
        return False
    try:
        socket.inet_pton(socket.AF_INET, texto)
        return True
    except OSError:
        pass
    try:
        socket.inet_pton(socket.AF_INET6, texto)
        return True
    except OSError:
        return False


def resolver_host(host, timeout=TIMEOUT_RESOLVE_S):
    """Traduz o NOME do par para o IPv4 dele na rede local.

    Configurar a LAN pelo NOME (e não pelo IP) é o que a mantém de pé: o IP da
    loja vem por DHCP e muda sozinho. O nome acompanha a máquina.

    Prefere SEMPRE o IPv4: o Windows costuma anunciar o nome também em IPv6
    link-local (`fe80::...`), que só existe no link e não serve para o banco.
    Devolve o próprio `host` quando ele já é um IP, ou `None` quando o nome não
    é encontrado.
    """
    texto = str(host or '').strip()
    if not texto:
        return None
    if _eh_ip(texto):
        return texto
    try:
        infos = socket.getaddrinfo(texto, None, socket.AF_INET,
                                   socket.SOCK_STREAM)
    except OSError:
        return None
    for info in infos:
        endereco = info[4][0] if len(info) > 4 else None
        if endereco:
            return endereco
    return None


def ip_do_par(cfg, timeout=TIMEOUT_RESOLVE_S):
    """IP atual do par, resolvendo o nome (com cache) quando for preciso."""
    host = cfg['host']
    if _eh_ip(host):
        return host
    chave = host.lower()
    if chave in _CACHE_IPS:
        return _CACHE_IPS[chave]
    ip = resolver_host(host, timeout=timeout)
    if ip:
        _CACHE_IPS[chave] = ip
    return ip


def conectar_no_par(cfg, timeout=TIMEOUT_CONEXAO_S):
    """Abre a conexão no PostgreSQL do OUTRO PC (pela rede local).

    O nome é resolvido a CADA ciclo (com cache curto): é assim que a LAN
    continua funcionando quando o DHCP troca o endereço do outro PC.
    """
    ip = ip_do_par(cfg)
    if not ip:
        raise RuntimeError(
            f'não achei o computador "{cfg["host"]}" na rede local '
            '(confira o nome exato ou informe o IP)'
        )
    return psycopg2.connect(
        host=ip, port=cfg['port'], dbname=cfg['dbname'],
        user=cfg['user'], password=cfg['password'],
        connect_timeout=timeout,
        application_name='exodo-lan-par',
    )


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _ident(nome):
    """Nome de tabela entre aspas duplas, do jeito que o PostgreSQL aceita."""
    return '"' + str(nome).replace('"', '""') + '"'


def _texto_ts(valor):
    """Converte um carimbo de data em texto (formato do cursor)."""
    if valor is None:
        return None
    if isinstance(valor, datetime):
        if valor.tzinfo is not None:
            return valor.astimezone(timezone.utc).isoformat()
        return valor.isoformat()
    return str(valor)


def _chave_cursor(tabela, par, apagados=False):
    """Chave em `_sync_controle` do cursor deste par para esta tabela.

    É por PAR (e não global) porque cada PC tem o seu próprio ponto de parada.
    """
    prefixo = 'lan_del' if apagados else 'lan'
    return f'{prefixo}_{tabela}__{par}'


def _ler_cursor(conn, chave, padrao=None):
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT valor FROM _sync_controle WHERE chave=%s', (chave,))
            linha = cur.fetchone()
        return linha[0] if linha else padrao
    except Exception:
        return padrao


def _salvar_cursor(conn, chave, valor):
    with conn.cursor() as cur:
        cur.execute(
            'INSERT INTO _sync_controle (chave, valor) VALUES (%s, %s) '
            'ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor',
            (chave, valor),
        )
    conn.commit()


def _agora_do_par(conn_par):
    """`NOW()` do OUTRO banco, para os cursores usarem o mesmo relógio."""
    try:
        with conn_par.cursor() as cur:
            cur.execute('SELECT NOW()')
            return _texto_ts(cur.fetchone()[0])
    except Exception:
        return datetime.now(timezone.utc).isoformat()


def tabela_tem_apagados(conn):
    """A tabela de apagados existe neste banco?"""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT to_regclass('public._exodo_deletados')")
            return cur.fetchone()[0] is not None
    except Exception:
        return False


def _tabelas_para_lan(conn):
    """Tabelas de dados que fazem sentido copiar entre os PCs."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema='public'
              AND table_type='BASE TABLE'
              AND LEFT(table_name, 1) <> '_'
              AND LEFT(table_name, 3) <> 'vw_'
              AND LEFT(table_name, 5) <> 'view_'
              AND POSITION('_bkp_' IN table_name) = 0
              AND table_name NOT LIKE '%_bkp_%'
            ORDER BY table_name
        """)
        return [r[0] for r in cur.fetchall() if not _tabela_proibida(r[0])]


def _colunas_do_par(conn_par, tabela):
    """{coluna: tipo} da tabela NO PAR (o schema de lá manda na leitura)."""
    try:
        with conn_par.cursor() as cur:
            cur.execute("""
                SELECT column_name, data_type FROM information_schema.columns
                WHERE table_schema='public' AND table_name=%s
            """, (tabela,))
            return {r[0]: (r[1] or '').upper() for r in cur.fetchall()}
    except Exception:
        return {}


def _coluna_de_data(colunas):
    """Primeira coluna de data disponível (mesma ordem do sincronizador)."""
    for col in COLUNAS_DE_DATA:
        if col in colunas:
            return col
    return None


def _buscar_mudancas_do_par(conn_par, tabela, coluna, tipo, desde,
                            empresa_ativa, tem_empresa, lote, tem_id=True):
    """Lê no par os registros mexidos depois de `desde`.

    A ordenação é por (coluna de data, id) para ser DETERMINÍSTICA: dentro de
    uma mesma transação o PostgreSQL dá o mesmo NOW() a várias linhas (o app
    grava em blocos de 100), então ordenar só pela data deixava a ordem das
    linhas empatadas indefinida.
    """
    eh_tempo = ('TIMESTAMP' in tipo) or ('DATE' in tipo)
    comparacao = f'{_ident(coluna)} > %s::timestamptz' if eh_tempo else f'{_ident(coluna)} > %s'
    onde = [comparacao]
    params = [desde]
    if empresa_ativa and tem_empresa:
        onde.append('empresa_id = %s')
        params.append(str(empresa_ativa))
    ordem = f'{_ident(coluna)} ASC'
    if tem_id:
        ordem += ', "id" ASC'
    sql = (f'SELECT * FROM {_ident(tabela)} WHERE ' + ' AND '.join(onde) +
           f' ORDER BY {ordem} LIMIT {int(lote)}')
    with conn_par.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, tuple(params))
        return [dict(r) for r in cur.fetchall()]


def _buscar_apagados_do_par(conn_par, tabela, desde, lote):
    """Lê no par os apagados desta tabela depois de `desde`."""
    with conn_par.cursor() as cur:
        cur.execute(
            'SELECT registro_id, empresa_id, deletado_em FROM _exodo_deletados '
            'WHERE tabela = %s AND deletado_em > %s::timestamptz '
            'ORDER BY deletado_em ASC LIMIT %s',
            (tabela, desde, int(lote)),
        )
        return cur.fetchall()


def _aplicar_apagados(conn, tabela, registros, bloqueados, empresa_ativa):
    """Apaga no banco local o que o PAR apagou. Nunca apaga linha protegida.

    Protegido = tem alteração local ainda não enviada ou conflito aberto — é a
    mesma regra do download da nuvem: o que o usuário mexeu aqui vence.

    Roda com `exodo.sync_mode = 'on'` para não registrar um novo apagado nem
    reenviar o DELETE para a nuvem (quem manda o DELETE original é o PC de
    origem; isto aqui é réplica).
    """
    ids = []
    protegidos = 0
    do_par = bloqueados.get(tabela) or {}
    for registro_id, empresa_id, _deletado_em in registros:
        if str(registro_id) in do_par:
            protegidos += 1
            continue
        if (empresa_ativa and empresa_id and
                str(empresa_id) != str(empresa_ativa) and
                tabela not in S.TABELAS_SEM_FILTRO_DE_EMPRESA):
            continue
        ids.append(str(registro_id))
    if not ids:
        return 0, protegidos
    with conn.cursor() as cur:
        cur.execute("SET LOCAL exodo.sync_mode = 'on'")
        cur.execute(f'DELETE FROM {_ident(tabela)} WHERE id = ANY(%s)', (ids,))
        apagados = cur.rowcount or 0
    conn.commit()
    return apagados, protegidos


# Canal que o APP (Flutter) escuta para recarregar a tela na hora. É separado
# do `exodo_sync_event` (que acorda o ciclo da nuvem) de propósito: assim o app
# só é acordado quando a REDE LOCAL traz dado novo — as gravações do próprio
# usuário já atualizam a tela em memória e não precisam de recarga.
CANAL_UI = 'exodo_ui_event'


def _notificar_ui(conn, tabela):
    """Avisa o app que esta tabela mudou no banco local (para a tela atualizar).

    Sem isto, a LAN gravava no PostgreSQL mas o app só enxergava o dado ao sair
    e entrar de novo (a tela vivia da memória carregada na abertura).
    """
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT pg_notify(%s, %s)', (CANAL_UI, str(tabela)))
        conn.commit()
    except Exception as e:
        S.print_log(f'[LAN] Aviso à interface falhou ({tabela}): {e}',
                    S.Colors.YELLOW)


def purgar_tombstones_antigos(conn, dias=DIAS_TOMBSTONE_PADRAO):
    """Apaga apagados antigos, para a tabela não crescer para sempre.

    A retenção só é segura se o OUTRO PC sincronizar dentro da janela. Com o
    padrão de 30 dias, um PC que passar mais de um mês desligado perderá os
    apagados desse período — por isso o valor é configurável.
    """
    if not tabela_tem_apagados(conn):
        return 0
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM _exodo_deletados "
                "WHERE deletado_em < NOW() - (%s || ' days')::interval",
                (str(int(dias)),),
            )
            removidos = cur.rowcount or 0
        conn.commit()
        return removidos
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        S.print_log(f'[LAN] Não foi possível limpar apagados antigos: {e}',
                    S.Colors.YELLOW)
        return 0


# ─────────────────────────────────────────────────────────────────────────────
# Ciclo
# ─────────────────────────────────────────────────────────────────────────────

def _normalizar_para_comparacao(valor):
    """Deixa dois valores iguaisarem de verdade na comparação.

    `jsonb` volta do psycopg2 como objeto Python (lista/dict) num lado e como
    texto JSON no outro, dependendo de como o registro chegou ate aqui. Sem
    normalizar dos dois ladoS, uma lista vazia `[]` nunca casaria com a string
    `'[]'` - e toda empresa pareceria alterada a cada ciclo (o laço de
    reescrita que voltou a aparecer em producao).
    """
    if isinstance(valor, (dict, list, tuple)):
        return json.dumps(valor if not isinstance(valor, tuple) else list(valor),
                          sort_keys=True, default=str)
    return valor


def _descartar_iguais(conn, tabela, linhas):
    """Tira da lista as linhas que sao IDENTICAS as que ja estao aqui.

    `empresas` e relida inteira a cada ciclo (sem cursor), porque e ela que
    define quantas empresas aparecem na tela de selecao. Sem esta comparacao o
    PC reescreve as mesmas linhas para sempre: cada UPDATE dispara o trigger,
    a linha entra na fila de envio, e o ciclo seguinte a reencontra como
    "alteracao local pendente" — um laco de escrita que nunca para.
    """
    if not linhas or not isinstance(linhas[0], dict):
        return linhas
    ids = [str(l.get('id')) for l in linhas if l.get('id') is not None]
    if not ids:
        return linhas
    try:
        with conn.cursor() as cur:
            cur.execute(f'SELECT * FROM "{tabela}" WHERE id = ANY(%s)', (ids,))
            nomes = [d[0] for d in (getattr(cur, 'description', None) or ())]
            existentes = {}
            for registro in cur.fetchall():
                # A conexao pode ser de tupla (padrao) OU RealDictCursor. Com
                # dict, `dict(zip(nomes, linha))` devolveria nome->nome e TODA
                # linha pareceria diferente - foi o que mantive o laco de
                # reescrita de empresas funcionando em producao.
                if hasattr(registro, 'keys'):
                    linha_local = dict(registro)
                elif nomes:
                    linha_local = dict(zip(nomes, registro))
                else:
                    continue
                existentes[str(linha_local.get('id'))] = linha_local
    except Exception:
        return linhas          # sem comparacao, mas sem perder dado
    if not existentes:
        return linhas

    diferentes = []
    for linha in linhas:
        atual = existentes.get(str(linha.get('id')))
        if atual is None:
            diferentes.append(linha)
            continue
        mudou = False
        for col, valor in linha.items():
            if col not in atual:
                continue
            atual_v = _normalizar_para_comparacao(atual[col])
            valor = _normalizar_para_comparacao(valor)
            if atual_v != valor:
                mudou = True
                break
        if mudou:
            diferentes.append(linha)
    return diferentes


def _puxar_tabela(conn, conn_par, tabela, cfg, par, empresa_ativa, bloqueados, agora):
    """Traz de UMA tabela o que o par mudou e aplica aqui. Devolve contadores."""
    contagem = {'recebidos': 0, 'apagados': 0, 'protegidos': 0, 'cursor': False}
    colunas = _colunas_do_par(conn_par, tabela)
    if not colunas:
        return contagem
    # Tabelas como `empresas` apontam para elas mesmas (empresa_id = id). Filtrar
    # por `empresa_id = empresa_ativa` aqui esconderia as demais empresas: cada PC
    # so baixaria a que esta ativa nele — da o sintoma "so aparece uma empresa".
    # O catalogo de empresas e lido SEM o filtro; tudo o mais continua filtrado.
    tem_empresa = ('empresa_id' in colunas and
                   tabela not in S.TABELAS_SEM_FILTRO_DE_EMPRESA)

    # ── Registros novos/alterados ────────────────────────────────────────────
    coluna = _coluna_de_data(colunas)
    chave = _chave_cursor(tabela, par)
    cursor = _ler_cursor(conn, chave)
    # O cadastro de empresas e pequeno e decisivo (e ele que define quantas
    # empresas aparecem na tela de selecao): e puxado SEMPRE por inteiro, sem
    # cursor. Um cursor recem-criado ou velho esconderia as empresas ja
    # cadastradas no par — que e o defeito que se esta corrigindo.
    por_inteiro = tabela in S.TABELAS_SEM_FILTRO_DE_EMPRESA
    if cursor is None and not por_inteiro and not (
            cfg['inicial_completo'] and coluna):
        # 1º contato: sincroniza a partir de AGORA. O histórico já foi (ou será)
        # alinhado pela nuvem; puxar tudo daria um download gigante de graça.
        # (Com LAN_INICIAL_COMPLETO=true e coluna de data, puxa o histórico.)
        _salvar_cursor(conn, chave, agora)
        contagem['cursor'] = True
    elif coluna is not None:
        tipo = colunas.get(coluna, '')
        desde = ('1970-01-01T00:00:00+00:00' if por_inteiro
                 else cursor or '1970-01-01T00:00:00+00:00')
        linhas = _buscar_mudancas_do_par(
            conn_par, tabela, coluna, tipo, desde, empresa_ativa,
            tem_empresa, LOTE_PADRAO, tem_id=('id' in colunas))
        if por_inteiro:
            linhas = _descartar_iguais(conn, tabela, linhas)
        if linhas:
            recebidos, aplicados = S.gravar_registros_locais(
                conn, tabela, linhas,
                # `None` nas tabelas sem filtro de empresa (ver
                # TABELAS_SEM_FILTRO_DE_EMPRESA): senao a gravação rejeitaria as
                # demais empresas mesmo tendo lido todas aqui.
                empresa_filtro=empresa_ativa if tem_empresa else None,
                bloqueados=bloqueados,
            )
            contagem['recebidos'] = recebidos
            # Sem cursor para a tabela de empresas: ela re-lê do zero a cada
            # ciclo, então uma empresa cadastrada antes do cursor nunca fica de fora.
            if not por_inteiro:
                # O cursor para no ÚLTIMO registro que foi realmente gravado — e
                # não no último que veio do par. Se passasse por cima de uma linha
                # barrada (conflito aberto), a alteração dela nunca mais seria
                # lida: os dois bancos ficariam divergentes para sempre, porque
                # cada PC já teria "visto" o dado e decidido que acabou.
                aplicadas = {str(i) for i in (aplicados or [])}
                ultimo = None
                for linha in reversed(linhas):
                    if str(linha.get('id')) in aplicadas:
                        ultimo = _texto_ts(linha.get(coluna))
                        break
                if ultimo:
                    _salvar_cursor(conn, chave, ultimo)
                    contagem['cursor'] = True

    # ── Apagados ─────────────────────────────────────────────────────────────
    chave_del = _chave_cursor(tabela, par, apagados=True)
    cursor_del = _ler_cursor(conn, chave_del)
    if cursor_del is None:
        _salvar_cursor(conn, chave_del, agora)
        return contagem
    if not tabela_tem_apagados(conn_par):
        return contagem
    apagados = _buscar_apagados_do_par(conn_par, tabela, cursor_del, LOTE_PADRAO)
    if apagados:
        quantos, protegidos = _aplicar_apagados(
            conn, tabela, apagados, bloqueados, empresa_ativa)
        contagem['apagados'] += quantos
        contagem['protegidos'] += protegidos
        ultimo = _texto_ts(apagados[-1][2])
        if ultimo:
            _salvar_cursor(conn, chave_del, ultimo)
    return contagem


def sincronizar_com_par(conn, cfg=None, tabelas=None):
    """Puxa do PC da rede local tudo o que ele tem de novo (e os apagados).

    Nunca levanta exceção: devolve um resumo. Assim uma LAN fora do ar não
    derruba o ciclo da nuvem, que continua sendo o caminho principal.

    Resumo devolvido:
        {'par', 'tabelas', 'recebidos', 'apagados', 'protegidos', 'tombstones',
         'erro'}
    """
    cfg = cfg if cfg is not None else config_do_par()
    if not cfg:
        return None
    resumo = {'par': cfg['nome'], 'tabelas': 0, 'recebidos': 0, 'apagados': 0,
              'protegidos': 0, 'tombstones': 0, 'erro': None}

    conn_par = None
    try:
        S.garantir_tabela_controle(conn)
        conn_par = conectar_no_par(cfg)
    except Exception as e:
        # Se o nome deixou de resolver, joga o cache fora: o endereço do par
        # pode ter mudado, e a próxima tentativa precisa procurar de novo.
        _CACHE_IPS.pop(str(cfg['host']).lower(), None)
        resumo['erro'] = (f'sem conexão com o par {cfg["host"]}:{cfg["port"]} '
                          f'({e})')
        S.print_log(f'[LAN] {resumo["erro"]}', S.Colors.YELLOW)
        return resumo

    try:
        tabelas = list(tabelas) if tabelas else _tabelas_para_lan(conn)
        par = cfg['nome']
        empresa_ativa = S.obter_empresa_ativa(conn)
        # `incluir_pendentes=False`: a fila de pendencias protege a edicao local
        # contra a copia VELHA da nuvem. Contra o par (outro PC) ela nao vale:
        # com a nuvem em 402 a fila nunca e limpa, e os dois PCs passavam a
        # recusar a versao um do outro indefinidamente. Conflito aberto segue
        # bloqueando (Quem decidiu foi o usuario; a fila nao e um veredito).
        bloqueados = S.ids_bloqueados_no_download(conn, incluir_pendentes=False)
        agora = _agora_do_par(conn_par)

        for tabela in tabelas:
            try:
                contagem = _puxar_tabela(
                    conn, conn_par, tabela, cfg, par,
                    empresa_ativa, bloqueados, agora)
                resumo['tabelas'] += 1
                resumo['recebidos'] += contagem['recebidos']
                resumo['apagados'] += contagem['apagados']
                resumo['protegidos'] += contagem['protegidos']
                # Avisa o app para atualizar a tela AGORA (o dado acabou de
                # chegar pela rede local).
                if contagem['recebidos'] or contagem['apagados']:
                    _notificar_ui(conn, tabela)
            except Exception as e:
                try:
                    conn.rollback()
                except Exception:
                    pass
                S.print_log(f'[LAN] {tabela}: falha ao puxar do par — {e}',
                            S.Colors.YELLOW)

        resumo['tombstones'] = purgar_tombstones_antigos(conn, cfg['dias_tombstone'])

        if resumo['recebidos'] or resumo['apagados'] or resumo['protegidos']:
            S.print_log(
                f'[LAN] Par {par}: {resumo["recebidos"]} recebido(s), '
                f'{resumo["apagados"]} apagado(s)'
                + (f', {resumo["protegidos"]} protegido(s) (alteração local '
                   'pendente/conflito)' if resumo['protegidos'] else '') + '.',
                S.Colors.CYAN,
            )
        elif resumo['tabelas']:
            S.print_log(f'[LAN] Par {par}: nada novo (bancos em dia).',
                        S.Colors.GREEN)
    except Exception as e:
        resumo['erro'] = str(e)
        S.print_log(f'[LAN] Erro no ciclo com o par: {e}', S.Colors.RED)
    finally:
        if conn_par is not None:
            try:
                conn_par.close()
            except Exception:
                pass
    return resumo


def main():
    """Um ciclo só, para diagnóstico (útil para testar a rede sem o tray)."""
    from dotenv import load_dotenv
    base = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(base, '.env'))

    cfg = config_do_par()
    if not cfg:
        print('[LAN] Desligada. Defina PAR_HOST (nome ou IP do outro PC) no .env '
              'para ativar.')
        return 1

    ip = ip_do_par(cfg) or '?'
    print(f'[LAN] Par: {cfg["nome"]} ({cfg["host"]} -> {ip}:{cfg["port"]}/'
          f'{cfg["dbname"]})')
    try:
        conn = psycopg2.connect(
            host=os.getenv('DB_HOST', 'localhost'),
            port=os.getenv('DB_PORT', '5432'),
            dbname=os.getenv('DB_NAME'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            connect_timeout=5,
        )
    except Exception as e:
        print(f'[LAN] Não conectou no banco LOCAL: {e}')
        return 2
    try:
        resumo = sincronizar_com_par(conn, cfg)
        print(f'[LAN] Resumo: {resumo}')
    finally:
        conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())

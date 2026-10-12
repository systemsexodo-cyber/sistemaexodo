#!/usr/bin/env python3
"""
Sincronizador Bidirecional Otimizado: PostgreSQL Local <-> Supabase

UPLOAD:   Registros com _sincronizado_nuvem=FALSE → envia ao Supabase → marca TRUE
DOWNLOAD: Registros no Supabase atualizados após última sync → upsert local → marca TRUE
"""
import argparse
import json
import os
import platform
import re
import select
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
import uuid

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from dotenv import load_dotenv
import requests

# ─── Cooldown para tabelas ausentes no Supabase (404) ──────────────────
# Tabelas que retornam 404 são marcadas com timestamp e ignoradas por
# COOLDOWN_SEGUNDOS segundos, evitando loops infinitos de retry.
_tabelas_404_cooldown = {}  # nome_tabela -> datetime da última falha
COOLDOWN_SEGUNDOS = 1800  # 30 minutos

def _em_cooldown(tabela):
    """Verifica se a tabela está em cooldown (recentemente falhou com 404)."""
    if tabela not in _tabelas_404_cooldown:
        return False
    elapsed = (datetime.now(timezone.utc) - _tabelas_404_cooldown[tabela]).total_seconds()
    if elapsed > COOLDOWN_SEGUNDOS:
        del _tabelas_404_cooldown[tabela]
        return False
    return True

def _marcar_cooldown(tabela):
    """Marca a tabela para ser ignorada nos próximos ciclos."""
    _tabelas_404_cooldown[tabela] = datetime.now(timezone.utc)
    print_log(f"[SYNC] ⏸️ Tabela '{tabela}' marcada em cooldown por {COOLDOWN_SEGUNDOS}s (ausente no Supabase)", Colors.CYAN)


# ─── Bloqueio da nuvem (401 / 402 / 403) ───────────────────────────────
# HTTP 402 é o projeto bloqueado por COTA ("exceed_egress_quota"): enquanto o
# dono não mudar o plano, TODA requisição volta 402. O ciclo tratava isso como
# "falha transiente" e repetia 40+ downloads e dezenas de uploads a cada
# passada — log cheio, CPU ociosa e nenhuma chance de sucesso.
#
# Aqui a nuvem entra em PAUSA por BLOQUEIO_SEGUNDOS e o aviso sai uma vez só.
# Os dados locais continuam valendo e a fila de envio fica intacta: quando a
# nuvem voltar, tudo o que ficou pendente sobe.
BLOQUEIO_STATUS = frozenset({401, 402, 403})
BLOQUEIO_SEGUNDOS = 1800  # 30 minutos
_bloqueio_nuvem = {'status': None, 'ate': None}


def _marcar_bloqueio_nuvem(status, detalhe=''):
    """Pausa a nuvem por BLOQUEIO_SEGUNDOS. Avisa UMA vez por bloqueio."""
    agora = datetime.now(timezone.utc)
    ja_pausada = _bloqueio_nuvem['ate'] is not None and _bloqueio_nuvem['ate'] > agora
    _bloqueio_nuvem['status'] = status
    _bloqueio_nuvem['ate'] = agora + timedelta(seconds=BLOQUEIO_SEGUNDOS)
    if not ja_pausada:
        sufixo = f" - {detalhe}" if detalhe else ''
        print_log(
            f"[SYNC] ⛔ Nuvem bloqueada (HTTP {status}){sufixo}: sincronização em pausa "
            f"por {BLOQUEIO_SEGUNDOS // 60} min. O sistema continua funcionando com os "
            "dados locais e a rede entre os PCs; a fila de envio fica preservada.",
            Colors.RED,
        )


def nuvem_bloqueada():
    """True enquanto a pausa por 401/402/403 estiver valendo."""
    ate = _bloqueio_nuvem['ate']
    if ate is None:
        return False
    if datetime.now(timezone.utc) >= ate:
        _bloqueio_nuvem['ate'] = None
        _bloqueio_nuvem['status'] = None
        return False
    return True


def motivo_bloqueio_nuvem():
    """HTTP do bloqueio atual (ou None). Usado nas mensagens de log."""
    return _bloqueio_nuvem['status'] if nuvem_bloqueada() else None

# Redirecionar stdout/stderr se forem None (evita crashes no PyInstaller --noconsole)
if sys.stdout is None:
    class DummyWriter:
        def write(self, *args, **kwargs): pass
        def flush(self, *args, **kwargs): pass
    sys.stdout = DummyWriter()
if sys.stderr is None:
    class DummyWriter:
        def write(self, *args, **kwargs): pass
        def flush(self, *args, **kwargs): pass
    sys.stderr = DummyWriter()

VERSION = "1.0.14"


# ─────────────────────────────────────────────────────────────────────────────
# Erros do ciclo (reportados ao portal / monitor de sincronização)
# ─────────────────────────────────────────────────────────────────────────────
# O monitor da nuvem só sabe o que o cliente conta. Antes, falha de upload ou
# de download só aparecia no log local do PC: a máquina ficava "online e sem
# erro" no portal enquanto nada sincronizava. Agora os erros do ciclo são
# acumulados e enviados no fim dele (sync_status.ultimo_erro + sync_logs).
_erros_do_ciclo = []

def registrar_erro_do_ciclo(mensagem):
    """Guarda o erro para reportar ao portal no fim do ciclo (limitado)."""
    texto = str(mensagem).strip()
    if not texto:
        return
    if texto in _erros_do_ciclo:
        return
    if len(_erros_do_ciclo) < 15:
        _erros_do_ciclo.append(texto[:180])


class Colors:
    GREEN   = '\033[92m'
    RED     = '\033[91m'
    YELLOW  = '\033[93m'
    BLUE    = '\033[94m'
    CYAN    = '\033[96m'
    MAGENTA = '\033[95m'
    RESET   = '\033[0m'
    BOLD    = '\033[1m'


def print_log(msg, color=Colors.RESET):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    # Nunca deixar print_log quebrar o ciclo por problemas de encoding do console
    try:
        print(f"[{timestamp}] {color}{msg}{Colors.RESET}")
    except Exception:
        try:
            print(f"[{timestamp}] {msg}")
        except Exception:
            pass
    try:
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        log_path = os.path.join(base_dir, "sincronizador.log")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] {msg}\n")
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# Controle de última sincronização
# ─────────────────────────────────────────────────────────────────────────────

def garantir_tabela_controle(conn):
    """Cria a tabela de controle de sincronização se não existir."""
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS _sync_controle (
                chave TEXT PRIMARY KEY,
                valor TEXT
            )
        """)
    conn.commit()


# ─────────────────────────────────────────────────────────────────────────────
# Empresa ativa (ponte com o app desktop) e cursores POR EMPRESA
# ─────────────────────────────────────────────────────────────────────────────
# O app desktop grava a empresa ABERTA na tabela local `cache_dados`, chave
# `exodo_empresa_ativa`. Com essa chave preenchida, o sincronizador importa
# SOMENTE os registros dessa empresa — é o que mantém a base local contendo
# apenas os dados da empresa que está em uso no app.
#
# Cada empresa tem o SEU cursor de sincronização (`sync_<tabela>__<empresa>`).
# Sem isso, ao abrir outra empresa o cursor global (já avançado) esconderia os
# registros antigos dela e a base local ficaria incompleta.
CHAVE_CACHE_EMPRESA_ATIVA = 'exodo_empresa_ativa'
CHAVE_CTRL_ULTIMA_EMPRESA = 'ultima_empresa_ativa'
# DESLIGADA por padrao: a base local mantem os dados de TODAS as empresas.
# So volta a apagar as outras empresas se esta chave for explicitamente
# ligada (`true`/`1`/`sim`/`on`) em `_sync_controle`.
CHAVE_CTRL_LIMPAR_OUTRAS  = 'limpar_outras_empresas_local'

# Valores que LIGAM a limpeza da base local (opt-in).
_VALORES_LIGADOS = ('1', 'true', 'sim', 'on', 'yes')

# Tabelas que NÃO pertencem a uma empresa só (cadastro/autenticação). Nunca
# podem ser filtradas/limpas por `empresa_id`: a lista de empresas e de
# usuários é global para o app inteiro.
TABELAS_GLOBAIS = {'empresas', 'usuarios'}

_EPOCH = "1970-01-01T00:00:00+00:00"


def ler_cache_dados(conn, chave):
    """Lê uma chave da tabela local cache_dados (aceita texto puro ou JSON)."""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT valor_json FROM cache_dados WHERE chave=%s", (chave,))
            row = cur.fetchone()
        if not row or row[0] is None:
            return None
        valor = row[0]
        texto = valor if isinstance(valor, str) else str(valor)
        texto = texto.strip()
        if not texto:
            return None
        try:
            decodificado = json.loads(texto)
            if isinstance(decodificado, str):
                texto = decodificado
            elif isinstance(decodificado, dict):
                texto = decodificado.get('empresaId') or decodificado.get('id') or ''
            elif decodificado is None:
                return None
            elif isinstance(decodificado, (int, float)):
                texto = str(decodificado)
        except Exception:
            pass
        texto = texto.strip().strip('"')
        return texto or None
    except Exception:
        # cache_dados pode não existir em instalações antigas
        return None


def obter_empresa_ativa(conn):
    """Empresa aberta no app, ou None quando a ponte ainda não foi preenchida.

    Com None o sincronizador mantém o comportamento antigo (baixa todas as
    empresas), para não quebrar instalações que ainda não têm o app novo.
    """
    return ler_cache_dados(conn, CHAVE_CACHE_EMPRESA_ATIVA)


def empresa_permite_sincronizacao_nuvem(conn, empresa_id):
    """Retorna a flag de sincronização da empresa salva localmente."""
    if not empresa_id:
        return True
    try:
        with conn.cursor() as cur:
            cur.execute(
                'SELECT configuracoes FROM empresas WHERE id = %s LIMIT 1',
                (empresa_id,),
            )
            row = cur.fetchone()
        if not row or row[0] is None:
            return True
        configuracoes = row[0]
        if isinstance(configuracoes, str):
            configuracoes = json.loads(configuracoes)
        if not isinstance(configuracoes, dict):
            return True
        valor = configuracoes.get(
            'nuvem_ativa',
            configuracoes.get('nuvemAtiva', configuracoes.get('cloud_sync_ativa', True)),
        )
        if isinstance(valor, str):
            return valor.strip().lower() not in ('false', '0', 'off', 'nao', 'não')
        return valor is not False
    except Exception as e:
        print_log(f"[EMPRESA] Não foi possível confirmar a flag da nuvem ({empresa_id}): {e}. Sincronização pausada por segurança.", Colors.YELLOW)
        return False


def _chave_sync_tabela(table_name, empresa_id=None):
    """Nome da chave de cursor: por empresa quando houver, global se não."""
    return f"sync_{table_name}__{empresa_id}" if empresa_id else f"sync_{table_name}"


def get_ultima_sync_tabela(conn, table_name, empresa_id=None):
    """Retorna o timestamp da última sincronização da tabela ou epoch se nunca rodou."""
    chave = _chave_sync_tabela(table_name, empresa_id)
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM _sync_controle WHERE chave=%s", (chave,))
        row = cur.fetchone()
    if row:
        return row[0]
    if empresa_id:
        # Primeira vez que esta empresa é aberta pelo app: baixa ela inteira.
        return _EPOCH
    # Se não houver timestamp específico para a tabela, tenta buscar a global antiga
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM _sync_controle WHERE chave='ultima_sincronizacao'")
        row = cur.fetchone()
    if row:
        return row[0]
    return _EPOCH


def salvar_ultima_sync_tabela(conn, table_name, timestamp_iso, empresa_id=None):
    """Salva o timestamp da sincronização (por empresa, quando houver)."""
    chave = _chave_sync_tabela(table_name, empresa_id)
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO _sync_controle (chave, valor)
            VALUES (%s, %s)
            ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor
        """, (chave, timestamp_iso))
    conn.commit()


def limpeza_da_base_local_habilitada(conn):
    """A limpeza da base local é OPT-IN (desligada por padrão).

    Antes ela era ligada por padrão: a cada troca de empresa o sincronizador
    apagava da base LOCAL as linhas das outras empresas. O efeito colateral era
    grave — ao voltar para a empresa anterior, o cursor dela (que é por empresa)
    já estava avançado, então o sincronizador só baixava o que mudou depois
    dele e a base local ficava incompleta. O sintoma é exatamente "entro na
    mesma empresa e os dados não carregam".

    Agora a base local mantém os dados de TODAS as empresas. A limpeza só roda
    se for pedida explicitamente: `_sync_controle.limpar_outras_empresas_local
    = true`.
    """
    valor = ler_cache_dados(conn, CHAVE_CTRL_LIMPAR_OUTRAS)
    if valor is None:
        return False
    return str(valor).strip().lower() in _VALORES_LIGADOS


def garantir_base_local_completa(conn, empresa_ativa, tabelas):
    """Ao ABRIR outra empresa no app, refaz o download COMPLETO dela.

    O cursor é por empresa e só avança. Isso está correto enquanto a base local
    não perde linhas — mas QUALQUER linha ausente (base limpa, linha criada só
    aqui e nunca encontrada na nuvem, restauração parcial) ficava ausente para
    sempre, porque o cursor já tinha passado por ela. Era isso que fazia os
    dados não carregarem ao voltar para a mesma empresa.

    Aqui, sempre que a empresa aberta no app MUDA, o cursor das tabelas dela
    volta para a epoch: o passo 3 baixa a empresa inteira de novo e a base local
    fica completa. Não apaga nada.
    """
    if not empresa_ativa:
        return 0
    if not empresa_ativa_mudou(conn, empresa_ativa):
        return 0

    total = 0
    for tabela in tabelas:
        try:
            if get_ultima_sync_tabela(conn, tabela, empresa_ativa) == _EPOCH:
                continue
            salvar_ultima_sync_tabela(conn, tabela, _EPOCH, empresa_ativa)
            total += 1
        except Exception as e:
            print_log(f"[EMPRESA] {tabela}: falha ao resetar o cursor ({e})",
                      Colors.YELLOW)
    if total:
        print_log(f"[EMPRESA] Empresa ativa {empresa_ativa}: download completo "
                  f"forçado em {total} tabela(s) para completar a base local.",
                  Colors.GREEN)
    return total


def deve_limpar_outras_empresas(conn, empresa_ativa, ja_limpou_nesta_execucao):
    """A base local precisa ser limpa das outras empresas agora?

    Por padrão NÃO: a base local mantém os dados de todas as empresas (ver
    [limpeza_da_base_local_habilitada]). Quando a limpeza é ligada na mão, roda
    no PRIMEIRO ciclo de cada execução e sempre que a empresa aberta mudar —
    não roda em todo ciclo para não ficar apagando à toa.
    """
    if not empresa_ativa:
        return False
    if not limpeza_da_base_local_habilitada(conn):
        return False
    if not ja_limpou_nesta_execucao:
        return True
    return empresa_ativa_mudou(conn, empresa_ativa)


def empresa_ativa_mudou(conn, empresa_ativa):
    """A empresa aberta no app é diferente da última vista por este sincronizador?"""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT valor FROM _sync_controle WHERE chave=%s",
                        (CHAVE_CTRL_ULTIMA_EMPRESA,))
            row = cur.fetchone()
        return (row[0] if row else None) != empresa_ativa
    except Exception:
        return False


def salvar_empresa_ativa_vista(conn, empresa_ativa):
    """Registra qual empresa o sincronizador está tratando agora."""
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO _sync_controle (chave, valor)
                VALUES (%s, %s)
                ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor
            """, (CHAVE_CTRL_ULTIMA_EMPRESA, empresa_ativa))
        conn.commit()
    except Exception as e:
        print_log(f"[EMPRESA] Não foi possível registrar a empresa ativa: {e}", Colors.YELLOW)


# ─────────────────────────────────────────────────────────────────────────────
# Caches Globais e Conectividade HTTP
# ─────────────────────────────────────────────────────────────────────────────

_supabase_schema_cache = None
_colunas_e_tipos_cache = {}
_http_session = None

def get_http_session():
    """Garante uma única sessão HTTP persistente com Keep-Alive e pooling de conexões."""
    global _http_session
    if _http_session is None:
        _http_session = requests.Session()
        # Pool com capacidade para suportar até 20 conexões paralelas de threads
        adapter = requests.adapters.HTTPAdapter(pool_connections=20, pool_maxsize=20)
        _http_session.mount('http://', adapter)
        _http_session.mount('https://', adapter)
    return _http_session


# Prioridades de Sincronização: 1=Alta, 2=Média, 3=Baixa
TABELA_PRIORIDADES = {
    'empresas': 0,  # SEMPRE primeiro: pedidos/vendas referenciam empresa_id (evita falhas de FK)
    'vendas_balcao': 1,
    'pedidos': 1,
    'servicos_realizados': 1,
    'orcamentos': 1,
    'aberturas_caixa': 1,
    'fechamentos_caixa': 1,
    'sangrias_caixa': 1,
    'suprimentos_caixa': 1,
    'ordens_servico': 1,
    'nfces': 1,
    'nfes': 1,
    'estoque_historico': 3,
    'produto_historico': 3,
    'imagens': 3,
    'exodo_sync_conflitos': 3
}

def get_tabela_prioridade(table_name):
    return TABELA_PRIORIDADES.get(table_name, 2)


def testar_conexao_supabase(supabase_url):
    """Verifica de forma rápida e silenciosa se o Supabase está acessível."""
    try:
        session = get_http_session()
        # HEAD request leve com timeout tolerante de 5 segundos
        session.head(supabase_url.rstrip('/'), timeout=5.0)
        return True
    except Exception:
        return False


def tem_conflitos_pendentes(conn):
    """Verifica se há conflitos não resolvidos na tabela de conflitos."""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM exodo_sync_conflitos WHERE resolvido = FALSE LIMIT 1")
            return cur.fetchone() is not None
    except Exception:
        return False


def obter_qtd_conflitos_pendentes(conn):
    """Retorna a quantidade de conflitos não resolvidos."""
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM exodo_sync_conflitos WHERE resolvido = FALSE")
            return cur.fetchone()[0]
    except Exception:
        return 0


_tem_tabela_conflitos_cache = None


def _garantir_tabela_conflitos(conn):
    """Garante a existência da tabela de conflitos (uma vez por processo).

    Ela é o ÚNICO lugar onde uma edição local que perdeu a disputa fica
    guardada. Sem ela o sincronizador não tinha onde parquear o conflito e
    acabava descartando a edição do usuário em silêncio.
    """
    global _tem_tabela_conflitos_cache
    if _tem_tabela_conflitos_cache is not None:
        return _tem_tabela_conflitos_cache
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS public.exodo_sync_conflitos (
                    id TEXT PRIMARY KEY,
                    tabela TEXT NOT NULL,
                    registro_id TEXT NOT NULL,
                    dados_locais JSONB,
                    dados_nuvem JSONB,
                    resolvido BOOLEAN NOT NULL DEFAULT FALSE,
                    empresa_id TEXT,
                    criado_em TIMESTAMPTZ DEFAULT NOW(),
                    visto_em TIMESTAMPTZ DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_exodo_conflitos_pendentes
                    ON public.exodo_sync_conflitos (tabela, registro_id)
                    WHERE resolvido = FALSE
            """)
        conn.commit()
        _tem_tabela_conflitos_cache = True
    except Exception as e:
        conn.rollback()
        print_log(f"[CONFLITO] Não foi possível garantir a tabela de conflitos: {e}", Colors.RED)
        _tem_tabela_conflitos_cache = False
    return _tem_tabela_conflitos_cache


def registrar_conflito_pendente(conn, tabela, registro_id, dados_locais, dados_nuvem, empresa_id=None):
    """Parqueia uma disputa NOVA para o usuário decidir (resolvido = FALSE).

    Antes esta gravação entrava com `resolvido = TRUE`: o conflito existia no
    banco, mas nunca aparecia para ninguém (a contagem do app ficava em 0) e a
    edição local era jogada fora sem aviso.

    É idempotente por (tabela, registro_id): a cada ciclo só ATUALIZA a versão
    da nuvem do conflito que já está aberto, em vez de empilhar uma linha nova.
    """
    if not _garantir_tabela_conflitos(conn):
        return False
    try:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL exodo.sync_mode = 'off'")
            cur.execute(
                """
                UPDATE exodo_sync_conflitos
                   SET dados_locais = %s,
                       dados_nuvem  = %s,
                       visto_em     = NOW()
                 WHERE tabela = %s AND registro_id = %s AND resolvido = FALSE
                """,
                (_json_para_conflito(dados_locais), _json_para_conflito(dados_nuvem),
                 tabela, str(registro_id)),
            )
            if cur.rowcount:
                conn.commit()
                return False  # já estava aberto: não é novidade para o usuário
            cur.execute(
                """
                INSERT INTO exodo_sync_conflitos
                    (id, tabela, registro_id, dados_locais, dados_nuvem, resolvido, empresa_id,
                     criado_em, visto_em)
                VALUES (%s, %s, %s, %s, %s, FALSE, %s, NOW(), NOW())
                """,
                (str(uuid.uuid4()), tabela, str(registro_id),
                 _json_para_conflito(dados_locais), _json_para_conflito(dados_nuvem),
                 (dados_locais or {}).get('empresa_id', empresa_id) or ''),
            )
        conn.commit()
        return True
    except Exception as e:
        conn.rollback()
        print_log(f"[CONFLITO] Erro ao parquear conflito de {tabela}/{registro_id}: {e}", Colors.RED)
        return False


def _json_para_conflito(dados):
    """Serializa um registro para jsonb (aceita dict, lista, texto ou None)."""
    if dados is None:
        return None
    if isinstance(dados, str):
        return dados
    return json.dumps(dados, default=str)


def ids_bloqueados_no_download(conn, incluir_pendentes=True):
    """Ids que NÃO podem ser sobrescritos pelo que vem da nuvem.

    Dois motivos:

      1. `exodo_sync_conflitos` aberto — o usuário ainda não decidiu qual
         versão vale. O download passa por cima do conflito e a decisão vira
         impossível (era o que fazia a edição parqueada desaparecer do local
         no ciclo seguinte).
      2. edição local ainda na fila (`_exodo_sync_log`) — subir primeiro,
         baixar depois. Sem isso, um ciclo com upload falhando apagava a
         alteração pendente do usuário com a cópia velha da nuvem.

    `incluir_pendentes=False` devolve SÓ os conflitos abertos. A LAN usa esse
    modo: contra outro PC não existe "sobe para a nuvem antes de descer" —
    os dois bancos são pares. E, com a nuvem bloqueada (HTTP 402), a fila de
    pendências nunca é limpa (ela só apaga depois de um upload bem-sucedido),
    então usar esse motivo na LAN travava os dois PCs para sempre, cada um
    recusando a versão do outro. Na LAN quem decide é o carimbo de data.

    Devolve {tabela: {id: motivo}}.
    """
    bloqueados = {}
    try:
        with conn.cursor() as cur:
            if incluir_pendentes and _tem_tabela_log(conn):
                cur.execute("SELECT table_name, record_id FROM _exodo_sync_log")
                for tabela, record_id in cur.fetchall():
                    if record_id:
                        bloqueados.setdefault(tabela, {})[str(record_id)] = 'alteracao_local_pendente'
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT tabela, registro_id FROM exodo_sync_conflitos WHERE resolvido = FALSE"
                )
                for tabela, registro_id in cur.fetchall():
                    bloqueados.setdefault(tabela, {})[str(registro_id)] = 'conflito_aberto'
        except Exception:
            pass  # tabela de conflitos ainda não existe: nada a bloquear
    except Exception as e:
        print_log(f"[DOWNLOAD] Não foi possível montar a lista de bloqueados: {e}", Colors.YELLOW)
    return bloqueados


def carregar_meta_colunas(conn):
    """Carrega os metadados de colunas de todas as tabelas na inicialização (evita queries N+1)."""
    global _colunas_e_tipos_cache
    if _colunas_e_tipos_cache:
        return  # Já carregado
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT table_name, column_name, data_type 
                FROM information_schema.columns
                WHERE table_schema='public'
            """)
            rows = cur.fetchall()
        
        cache = {}
        for table_name, column_name, data_type in rows:
            if table_name not in cache:
                cache[table_name] = {}
            cache[table_name][column_name] = data_type.upper()
        _colunas_e_tipos_cache = cache
        print_log(f"Metadados de colunas locais carregados em cache para {len(cache)} tabelas.", Colors.GREEN)
    except Exception as e:
        print_log(f"Erro ao carregar metadados das colunas locais: {e}", Colors.RED)


def get_supabase_colunas(supabase_url, api_key, table_name):
    """Retorna o conjunto de colunas de uma tabela no Supabase usando OpenAPI (com cache duradouro)."""
    global _supabase_schema_cache
    if _supabase_schema_cache is None:
        try:
            url = f"{supabase_url.rstrip('/')}/rest/v1/"
            headers = {
                'Accept':        'application/json',
                'apikey':        api_key,
                'Authorization': f'Bearer {api_key}',
            }
            session = get_http_session()
            response = session.get(url, headers=headers, timeout=15)
            response.raise_for_status()
            _supabase_schema_cache = response.json().get('definitions', {})
        except Exception as e:
            print_log(f"Erro ao obter definicoes OpenAPI do Supabase: {e}", Colors.RED)
            return None

    table_def = _supabase_schema_cache.get(table_name)
    if table_def:
        return set(table_def.get('properties', {}).keys())
    return None


def fetch_json(url, api_key):
    """Executa requisições GET usando a sessão Keep-Alive configurada.
    Retorna (dados, status_code) onde dados é None em caso de erro.
    """
    headers = {
        'Accept':        'application/json',
        'apikey':        api_key,
        'Authorization': f'Bearer {api_key}',
    }
    session = get_http_session()
    try:
        response = session.get(url, headers=headers, timeout=30)
        if response.status_code == 404:
            return None, 404
        response.raise_for_status()
        return response.json(), response.status_code
    except requests.exceptions.HTTPError as e:
        print_log(f"HTTP {e.response.status_code}: {e.response.text}", Colors.RED)
        return None, e.response.status_code
    except Exception as e:
        print_log(f"Erro de conexao: {e}", Colors.RED)
        return None, 0


def get_colunas_e_tipos_tabela(conn, table_name):
    """Retorna dicionário de colunas e tipos usando o cache global local."""
    global _colunas_e_tipos_cache
    if table_name in _colunas_e_tipos_cache:
        return _colunas_e_tipos_cache[table_name]
    
    # Fallback seguro caso a inicialização do cache falhe
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT column_name, data_type FROM information_schema.columns
                WHERE table_schema='public' AND table_name=%s
            """, (table_name,))
            return {r[0]: r[1].upper() for r in cur.fetchall()}
    except Exception:
        return {}


def get_colunas_tabela(conn, table_name):
    """Retorna as colunas existentes na tabela local."""
    return set(get_colunas_e_tipos_tabela(conn, table_name).keys())


def tabela_tem_coluna_updated_at(conn, table_name):
    colunas = get_colunas_tabela(conn, table_name)
    return 'updated_at' in colunas or 'criado_em' in colunas or 'created_at' in colunas


def coluna_timestamp_tabela(conn, table_name):
    """Retorna a coluna de timestamp disponível na tabela."""
    colunas = get_colunas_tabela(conn, table_name)
    for col in ('updated_at', 'created_at', 'criado_em', 'data_alteracao', 'data_venda', 'data'):
        if col in colunas:
            return col
    return None
# ─────────────────────────────────────────────────────────────────────────────
# NUMERAÇÃO ENTRE MÁQUINAS (o caso "VND-0003 nos dois PCs")
#
# O número é gerado localmente (maior número + 1). A nuvem NÃO recusa número
# repetido — conferido na base real: `numero_venda` está zerado em 438 das 441
# vendas, ou seja, não há restrição de unicidade nessas colunas. Dois PCs
# offline subiam "VND-0003" os dois, sem erro e sem aviso, e a loja ficava com
# duas vendas diferentes com o mesmo número.
#
# Como a nuvem não recusa, quem confere é o sincronizador: antes de enviar, se o
# número já pertence a OUTRO registro na nuvem, o registro que está subindo é
# renumerado para o próximo número livre — no lote e no banco local (senão o
# local reenviaria o número antigo em todo ciclo). Nenhuma venda é descartada.
# ─────────────────────────────────────────────────────────────────────────────

# Só estas tabelas têm numeração sequencial de verdade (VND-/PED-). Outras
# tabelas também têm coluna `numero`, mas é número de documento, não sequência.
TABELAS_COM_NUMERACAO = {'vendas_balcao', 'pedidos'}

# Prefixo + sequência. Além de VND-/PED-, aceita o prefixo pelo caixa
# (CX1-0003, CX2-0003): com nome por máquina cada caixa tem a PRÓPRIA sequência,
# então a comparação de "número repetido" passa a ser sempre dentro do mesmo
# prefixo e dois caixas nunca se atropelam.
_RE_NUMERO_SEQUENCIAL = re.compile(r'^([A-Z][A-Z0-9]{0,7})-(\d+)$')


def analisar_numero_sequencial(texto):
    """'VND-0003' -> ('VND', 3). Devolve None quando não segue o padrão."""
    m = _RE_NUMERO_SEQUENCIAL.match(str(texto or '').strip().upper())
    if not m:
        return None
    return m.group(1), int(m.group(2))


def formatar_numero_sequencial(prefixo, numero):
    return f"{prefixo}-{int(numero):04d}"


def _ids_por_numero_na_nuvem(supabase_url, api_key, table_name, numeros, empresa_filtro=None):
    """{numero: id_do_dono} para os números informados, consultando a nuvem."""
    donos = {}
    numeros = [n for n in numeros if n]
    if not numeros:
        return donos
    base = supabase_url.rstrip('/')
    tabela = urllib.parse.quote(table_name, safe='')
    for i in range(0, len(numeros), 50):
        lote = numeros[i:i + 50]
        lista = ",".join(f'"{n}"' for n in lote)
        url = f"{base}/rest/v1/{tabela}?select=id,numero&numero=in.({lista})"
        if empresa_filtro:
            url += f"&empresa_id=eq.{empresa_filtro}"
        dados, _status = fetch_json(url, api_key)
        for row in (dados or []):
            if isinstance(row, dict) and row.get('numero'):
                donos[str(row['numero'])] = str(row.get('id') or '')
    return donos


def _maior_numero_na_nuvem(supabase_url, api_key, table_name, prefixo, empresa_filtro=None):
    """Maior número com o prefixo informado já publicado na nuvem (0 se não houver)."""
    base = supabase_url.rstrip('/')
    tabela = urllib.parse.quote(table_name, safe='')
    url = f"{base}/rest/v1/{tabela}?select=numero&order=numero.desc&limit=2000"
    if empresa_filtro:
        url += f"&empresa_id=eq.{empresa_filtro}"
    dados, _status = fetch_json(url, api_key)
    maior = 0
    for row in (dados or []):
        if isinstance(row, dict):
            analisado = analisar_numero_sequencial(row.get('numero'))
            if analisado and analisado[0] == prefixo and analisado[1] > maior:
                maior = analisado[1]
    return maior


def _gravar_numero_no_local(conn, table_name, registro_id, numero):
    """Atualiza o número da cópia local sem disparar o gatilho de sincronização."""
    try:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL exodo.sync_mode = 'off'")
            cur.execute(f'UPDATE "{table_name}" SET numero = %s WHERE id = %s',
                        (numero, registro_id))
        conn.commit()
        return True
    except Exception as e:
        conn.rollback()
        print_log(f"[NUMERACAO] Nao foi possivel gravar o novo numero em "
                  f"{table_name}/{registro_id}: {e}", Colors.YELLOW)
        return False


def renumerar_repetidos_do_lote(conn, table_name, registros, supabase_url, api_key,
                                empresa_filtro=None):
    """Troca o número dos registros cujo número já é de OUTRO registro na nuvem.

    Devolve [(numero_antigo, numero_novo, registro_id), ...].
    """
    if table_name not in TABELAS_COM_NUMERACAO or not registros:
        return []

    candidatos = {}
    for registro in registros:
        analisado = analisar_numero_sequencial(registro.get('numero'))
        if analisado and registro.get('id'):
            candidatos[str(registro['id'])] = analisado
    if not candidatos:
        return []

    numeros = [formatar_numero_sequencial(p, n) for p, n in candidatos.values()]
    donos = _ids_por_numero_na_nuvem(supabase_url, api_key, table_name, numeros, empresa_filtro)
    if not donos:
        # Nuvem não respondeu: melhor não renumerar às cegas.
        return []

    renomeados = []
    reservados = set()
    maiores = {}
    for registro in registros:
        rid = str(registro.get('id'))
        if rid not in candidatos:
            continue
        prefixo, numero_antigo = candidatos[rid]
        texto = formatar_numero_sequencial(prefixo, numero_antigo)
        dono = donos.get(texto)
        if not dono or dono == rid:
            continue  # livre, ou é o próprio registro que já está na nuvem
        if prefixo not in maiores:
            maiores[prefixo] = _maior_numero_na_nuvem(
                supabase_url, api_key, table_name, prefixo, empresa_filtro)
        novo = maiores[prefixo] + 1
        while (formatar_numero_sequencial(prefixo, novo) in donos
               or formatar_numero_sequencial(prefixo, novo) in reservados):
            novo += 1
        maiores[prefixo] = novo
        reservados.add(formatar_numero_sequencial(prefixo, novo))
        registro['numero'] = formatar_numero_sequencial(prefixo, novo)
        renomeados.append((texto, registro['numero'], rid))
        print_log(
            f"[NUMERACAO] '{table_name}' id {rid}: o numero {texto} ja e de OUTRO registro "
            f"na nuvem (venda feita em outro PC, provavelmente sem internet). Vai subir como "
            f"{registro['numero']} - a venda NAO se perde e a copia local tambem foi corrigida.",
            Colors.YELLOW,
        )
        _gravar_numero_no_local(conn, table_name, rid, registro['numero'])
    return renomeados


def _postar_lote(session, url, headers, chunk, table_name):
    """Envia um bloco; se a nuvem recusar o bloco inteiro, reenvia um a um.

    Devolve (enviados, ids_recusados).

    Antes, um único registro problemático fazia o POST dos 500 falhar inteiro
    (`raise_for_status`) e o ciclo abortava: as outras 499 vendas ficavam presas
    no log, tentando de novo a cada ciclo e falhando de novo — nunca apareciam
    no outro PC. Agora o bloco bom passa e só o registro ruim é retido (o log
    dele é preservado, então ele volta no próximo ciclo).
    """
    try:
        resposta = session.post(url, data=json.dumps(chunk, default=str),
                                headers=headers, timeout=30)
        resposta.raise_for_status()
        return len(chunk), set()
    except requests.exceptions.HTTPError as e_bloco:
        status = e_bloco.response.status_code if e_bloco.response is not None else 0
        detalhe = (e_bloco.response.text if e_bloco.response is not None else '')[:300]
        if status in BLOQUEIO_STATUS:
            # Nuvem bloqueada (cota/permissão): nao adianta tentar um a um.
            _marcar_bloqueio_nuvem(status, detalhe)
            return 0, {str(r.get('id') or '') for r in chunk}
        print_log(f"[UPLOAD] {table_name}: bloco de {len(chunk)} recusado (HTTP {status}) - "
                  f"{detalhe}. Reenviando um a um para nao perder os bons.", Colors.YELLOW)
    except Exception as e_bloco:
        print_log(f"[UPLOAD] {table_name}: bloco de {len(chunk)} falhou - {e_bloco}. "
                  "Reenviando um a um.", Colors.YELLOW)

    enviados = 0
    recusados = set()
    for posicao, registro in enumerate(chunk):
        rid = str(registro.get('id') or '')
        try:
            resposta = session.post(url, data=json.dumps([registro], default=str),
                                    headers=headers, timeout=30)
            resposta.raise_for_status()
            enviados += 1
        except requests.exceptions.HTTPError as e_um:
            status = e_um.response.status_code if e_um.response is not None else 0
            if status == 404:
                continue  # tabela ausente na nuvem: o cooldown cuida disso
            detalhe = (e_um.response.text if e_um.response is not None else '')[:200]
            recusados.add(rid)
            if status in BLOQUEIO_STATUS:
                # A nuvem recusou o projeto inteiro (cota/permissão). Para de
                # repetir: marca o resto do lote como recusado para que a fila
                # local continue PENDENTE (nada se perde) e deixa o aviso por
                # conta de _marcar_bloqueio_nuvem (uma vez só).
                recusados.update(str(r.get('id') or '') for r in chunk[posicao + 1:])
                _marcar_bloqueio_nuvem(status, detalhe)
                break
            print_log(f"[UPLOAD] {table_name}: registro {rid} recusado pela nuvem "
                      f"(HTTP {status}) - {detalhe}", Colors.RED)
            registrar_erro_do_ciclo(f"upload {table_name}: registro {rid} HTTP {status}")
        except Exception as e_um:
            recusados.add(rid)
            print_log(f"[UPLOAD] {table_name}: registro {rid} falhou - {e_um}", Colors.RED)
    return enviados, recusados


def upload_tabela(conn, table_name, supabase_url, api_key, empresa_filtro=None):
    """Envia dados modificados locais de uma tabela para a nuvem."""
    # Tabelas que sao somente leitura (down-only) para o cliente:
    # Apenas limpamos os logs locais correspondentes para nao gerar falhas de RLS
    if table_name == 'empresas':
        try:
            with conn.cursor() as cur:
                cur.execute('DELETE FROM _exodo_sync_log WHERE table_name = %s', (table_name,))
            conn.commit()
        except Exception as e_clear:
            conn.rollback()
            print_log(f"[UPLOAD] Erro ao limpar logs de '{table_name}': {e_clear}", Colors.YELLOW)
        return 0

    try:
        # Busca logs pendentes na fila local
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, record_id, operation
                FROM _exodo_sync_log
                WHERE table_name = %s
                ORDER BY id ASC
            """, (table_name,))
            logs = cur.fetchall()

        if not logs:
            return 0

        log_ids_to_delete = []
        # Ids que a nuvem recusou enviar: o log deles NÃO é apagado, então eles
        # voltam no próximo ciclo em vez de sumirem para sempre.
        ids_falhos_no_envio = set()
        registros_to_upload = []
        identical_ids = set()
        # Ids com conflito ABERTO: o log deles é preservado (a edição local fica
        # pendente até o usuário decidir no app).
        conflito_ids = set()
        
        supabase_cols = get_supabase_colunas(supabase_url, api_key, table_name)
        
        # Agrupar IDs para buscar no banco em um único SELECT (Evita N+1 consultas)
        record_ids = [log[1] for log in logs if log[2] != 'DELETE']
        rows_dict = {}
        
        if record_ids:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                unique_ids = list(set(record_ids))
                if len(unique_ids) == 1:
                    cur.execute(f'SELECT * FROM "{table_name}" WHERE id = %s', (unique_ids[0],))
                else:
                    cur.execute(f'SELECT * FROM "{table_name}" WHERE id IN %s', (tuple(unique_ids),))
                for row in cur.fetchall():
                    rows_dict[row['id']] = dict(row)

        # DETECÇÃO DE CONFLITOS (Apenas para tabelas normais de dados)
        nuvem_dict = {}
        if record_ids and table_name != 'exodo_sync_conflitos':
            try:
                valid_ids = [rid for rid in record_ids if rid]
                if valid_ids:
                    # Chunks de IDs para evitar URLs gigantes
                    for j in range(0, len(valid_ids), 100):
                        chunk_ids = valid_ids[j:j+100]
                        ids_str = ",".join([f'"{rid}"' for rid in chunk_ids])
                        url_check = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}?id=in.({ids_str})"
                        # `fetch_json` devolve (dados, status). Antes o retorno era
                        # usado COMO SE fosse a lista: o `for` iterava a tupla, o
                        # `rn.get` estourava e o `except` abaixo engolia o erro —
                        # ou seja, a checagem de conflito NUNCA rodava e o último
                        # PC a sincronizar sobrescrevia o outro sem registro.
                        rows_nuvem, _status_check = fetch_json(url_check, api_key)
                        if rows_nuvem:
                            for rn in rows_nuvem:
                                if isinstance(rn, dict):
                                    nuvem_dict[rn.get('id')] = rn
            except Exception as e_check:
                print_log(f"[CONFLITO] {table_name}: erro ao buscar registros para checagem - {e_check}", Colors.YELLOW)

        # Tratar conflitos e identificar registros idênticos
        if nuvem_dict:
            # Mesma chave de cursor usada no download (por empresa, quando há
            # empresa ativa publicada pelo app) para o julgamento de conflito
            # ficar coerente com o que foi baixado.
            last_sync_time = get_ultima_sync_tabela(conn, table_name, empresa_filtro)
            col_ts = coluna_timestamp_tabela(conn, table_name)
            cols_to_check = supabase_cols if supabase_cols else set(get_colunas_tabela(conn, table_name))
            
            for log_id, record_id, op in logs:
                if op != 'DELETE' and record_id in nuvem_dict:
                    row_local = rows_dict.get(record_id)
                    row_nuvem = nuvem_dict.get(record_id)
                    if row_local and row_nuvem:
                        conflito = False
                        if col_ts:
                            ts_nuvem_str = row_nuvem.get(col_ts)
                            dt_nuvem = None
                            if ts_nuvem_str:
                                if ts_nuvem_str.endswith('Z'):
                                    ts_nuvem_str = ts_nuvem_str[:-1] + '+00:00'
                                try:
                                    dt_nuvem = datetime.fromisoformat(ts_nuvem_str)
                                    if dt_nuvem.tzinfo is None:
                                        dt_nuvem = dt_nuvem.replace(tzinfo=timezone.utc)
                                except:
                                    pass
                            
                            dt_last = None
                            if last_sync_time:
                                if last_sync_time.endswith('Z'):
                                    last_sync_time = last_sync_time[:-1] + '+00:00'
                                try:
                                    dt_last = datetime.fromisoformat(last_sync_time)
                                    if dt_last.tzinfo is None:
                                        dt_last = dt_last.replace(tzinfo=timezone.utc)
                                except:
                                    pass
                                    
                            if dt_nuvem and dt_last and dt_nuvem > dt_last:
                                conflito = True
                        else:
                            conflito = True
                            
                        # Verificar se campos de dados reais são diferentes
                        diferente = False
                        ignore_cols = {'updated_at', 'created_at', 'criado_em', 'atualizado_em', '_sincronizado_nuvem'}
                        for col in cols_to_check:
                            if col in ignore_cols:
                                continue
                            val_l = row_local.get(col)
                            val_n = row_nuvem.get(col)
                            if isinstance(val_l, (dict, list)) or isinstance(val_n, (dict, list)):
                                try:
                                    l_str = json.dumps(val_l, sort_keys=True, default=str)
                                    n_str = json.dumps(val_n, sort_keys=True, default=str)
                                    if l_str != n_str:
                                        diferente = True
                                        break
                                except:
                                    if val_l != val_n:
                                        diferente = True
                                        break
                            else:
                                if str(val_l) != str(val_n):
                                    diferente = True
                                    break
                                    
                        if conflito and diferente:
                            # PARQUEADO: a edição local NÃO é descartada nem deixa a
                            # nuvem ser sobrescrita. Fica em exodo_sync_conflitos
                            # (resolvido = FALSE) esperando a decisão do usuário, e a
                            # linha CONTINUA marcada como pendente em
                            # _exodo_sync_log — é isso que impede o download de
                            # passar por cima dela (ver ids_bloqueados_no_download).
                            novo = registrar_conflito_pendente(
                                conn, table_name, record_id, row_local, row_nuvem,
                                empresa_filtro,
                            )
                            conflito_ids.add(record_id)
                            identical_ids.add(record_id)  # <-- Impede que o dado local sobrescreva a nuvem
                            if novo:
                                print_log(
                                    f"[CONFLITO] '{table_name}' id '{record_id}': você alterou aqui e outro PC "
                                    "alterou na nuvem. As DUAS versões foram guardadas — decida no app "
                                    "(Sincronia → Corrigir Conflitos). Nada foi perdido.",
                                    Colors.YELLOW,
                                )
                            else:
                                print_log(
                                    f"[CONFLITO] '{table_name}' id '{record_id}': conflito ainda aberto, "
                                    "aguardando decisão no app.",
                                    Colors.YELLOW,
                                )
                        elif not diferente:
                            # Registro idêntico: Otimização de Outbox (pula upload desnecessário)
                            identical_ids.add(record_id)
                            print_log(f"[OUTBOX] {table_name}: registro ID {record_id} e identico na nuvem, pulando upload.", Colors.GREEN)

        # 1. Processar DELETES em lote (bulk delete) de 100 items
        deletes_to_process = [log[1] for log in logs if log[2] == 'DELETE']
        if deletes_to_process:
            for i in range(0, len(deletes_to_process), 100):
                chunk = deletes_to_process[i:i+100]
                ids_formatted = ",".join(chunk)
                try:
                    url = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}?id=in.({ids_formatted})"
                    headers = {
                        'apikey': api_key,
                        'Authorization': f'Bearer {api_key}',
                        'Prefer': 'return=minimal'
                    }
                    session = get_http_session()
                    response = session.delete(url, headers=headers, timeout=15)
                    response.raise_for_status()
                except Exception as e_del:
                    print_log(f"[UPLOAD] {table_name}: erro ao deletar na nuvem lote {i//100 + 1} - {e_del}", Colors.YELLOW)

        # 2. Processar INSERTS/UPDATES
        for log_id, record_id, op in logs:
            if op != 'DELETE' and record_id not in identical_ids:
                row = rows_dict.get(record_id)
                if row:
                    row_dict = row

                    # ⛔ TRAVA DE EMPRESA: se a tabela tem empresa_id, verificar
                    # que o registro pertence à empresa ativa antes de enviar para
                    # a nuvem. Isso impede que dados de uma empresa contaminem o
                    # espaço de outra empresa na nuvem.
                    if empresa_filtro and 'empresa_id' in row_dict:
                        empresa_do_registro = str(row_dict.get('empresa_id') or '')
                        if empresa_do_registro and empresa_do_registro != str(empresa_filtro):
                            print_log(
                                f"[UPLOAD] 🚨 ALARME: registro bloqueado em '{table_name}' "
                                f"(id={record_id}): empresa_id='{empresa_do_registro}' "
                                f"difere da empresa ativa='{empresa_filtro}'. "
                                "Upload cancelado para este registro.",
                                Colors.RED
                            )
                            log_ids_to_delete.append(log_id)  # Limpar log inválido
                            continue

                    if supabase_cols is not None:
                        # Mantem apenas colunas que de fato existem no Supabase
                        row_dict = {k: v for k, v in row_dict.items() if k in supabase_cols}
                    else:
                        # Fallback caso a API schema falhe
                        COLUNAS_APENAS_LOCAL = {
                            'criado_em', 'atualizado_em', 'ultimo_acesso',
                            'dados_usuario', 'dados_app', 'telefone', 'perfil',
                            'email_confirmado', 'ativo', 'sync'
                        }
                        for col_local in COLUNAS_APENAS_LOCAL:
                            row_dict.pop(col_local, None)
                    for k, v in row_dict.items():
                        if isinstance(v, datetime):
                            row_dict[k] = v.isoformat()
                    registros_to_upload.append(row_dict)
            if record_id in conflito_ids:
                # Log preservado de propósito: mantém a edição local como
                # pendente (bloqueada no download) até a decisão no app.
                continue
            log_ids_to_delete.append(log_id)
                
        if registros_to_upload:
            # Número repetido entre PCs (venda feita offline nos dois): renumera
            # ANTES de enviar, no lote e na cópia local.
            renumerados = renumerar_repetidos_do_lote(
                conn, table_name, registros_to_upload, supabase_url, api_key, empresa_filtro)
            if renumerados:
                print_log(f"[UPLOAD] {table_name}: {len(renumerados)} numero(s) repetido(s) "
                          "foram renumerados para nao duplicar entre os PCs.", Colors.YELLOW)

        enviados = 0
        if registros_to_upload:
            print_log(f"[UPLOAD] {table_name}: {len(registros_to_upload)} registro(s) para enviar")
            url = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}"
            headers = {
                'apikey': api_key,
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json',
                'Prefer': 'resolution=merge-duplicates'
            }
            session = get_http_session()
            
            # Enviar em lotes menores para evitar estouro de timeout (57014) no Supabase
            chunk_size = 500
            for i in range(0, len(registros_to_upload), chunk_size):
                chunk = registros_to_upload[i:i+chunk_size]
                enviados_bloco, recusados_bloco = _postar_lote(
                    session, url, headers, chunk, table_name)
                enviados += enviados_bloco
                ids_falhos_no_envio.update(recusados_bloco)
            
        if ids_falhos_no_envio:
            # Registro recusado pela nuvem continua pendente: sem isso o log era
            # apagado junto com os que subiram e o dado nunca mais era tentado.
            pendentes_que_falharam = {
                log_id for log_id, record_id, op in logs
                if op != 'DELETE' and str(record_id) in ids_falhos_no_envio
            }
            if pendentes_que_falharam:
                log_ids_to_delete = [i for i in log_ids_to_delete
                                     if i not in pendentes_que_falharam]
                print_log(f"[UPLOAD] {table_name}: {len(pendentes_que_falharam)} registro(s) "
                          "recusado(s) ficam pendentes para o proximo ciclo (nada foi perdido).",
                          Colors.YELLOW)

        if log_ids_to_delete:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM _exodo_sync_log WHERE id = ANY(%s)", (log_ids_to_delete,))
            conn.commit()
            
        if enviados > 0:
            print_log(f"[UPLOAD] {table_name}: {enviados} registro(s) enviados OK", Colors.GREEN)
        return enviados
        
    except requests.exceptions.HTTPError as e:
        conn.rollback()
        status = e.response.status_code if e.response is not None else 0
        if status == 404:
            if table_name not in _tabelas_404_cooldown:
                _marcar_cooldown(table_name)
            return 0
        print_log(f"[UPLOAD] {table_name}: erro no envio HTTP {status} - {e.response.text}", Colors.RED)
        registrar_erro_do_ciclo(f"upload {table_name}: HTTP {status}")
        return 0
    except Exception as e:
        conn.rollback()
        print_log(f"[UPLOAD] {table_name}: erro no envio - {e}", Colors.RED)
        registrar_erro_do_ciclo(f"upload {table_name}: {e}")
        return 0


# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD: Supabase → Local
# ─────────────────────────────────────────────────────────────────────────────

def _sanitizar_win1252(val):
    """Substitui caracteres Unicode incompátíveis com WIN1252 para evitar erros de encoding.
    
    O banco local pode estar em codificação WIN1252, mas o Supabase retorna dados UTF-8
    com caracteres como → (\u2192) e ❌ (\u274c) que não existem no WIN1252.
    """
    if isinstance(val, dict):
        return {k: _sanitizar_win1252(v) for k, v in val.items()}
    if isinstance(val, list):
        return [_sanitizar_win1252(item) for item in val]
    if not isinstance(val, str):
        return val
    try:
        # Tentar codificar em latin-1; se funcionar, está ok
        val.encode('latin-1')
        return val
    except (UnicodeEncodeError, UnicodeDecodeError):
        # Substituir caracteres problemáticos por equivalentes ASCII próximos
        substituicoes = {
            '\u2192': '->',    # → (seta)
            '\u2190': '<-',    # ← (seta)
            '\u2191': '^',     # ↑ (seta)
            '\u2193': 'v',     # ↓ (seta)
            '\u274c': 'X',     # ❌ (cross mark)
            '\u2705': 'OK',    # ✅ (check mark)
            '\u26a0': '!',     # ⚠ (warning)
            '\u2139': 'i',     # ℹ (info)
            '\u2022': '*',     # • (bullet)
            '\u2026': '...',   # … (ellipsis)
            '\u00a0': ' ',     # non-breaking space
            '\u200b': '',      # zero-width space
            '\u200d': '',      # zero-width joiner
            '\u200e': '',      # LTR mark
            '\u200f': '',      # RTL mark
            '\ufeff': '',      # BOM
        }
        for orig, repl in substituicoes.items():
            val = val.replace(orig, repl)
        # Fallback: codificar em latin-1 com substituição de qualquer caractere restante
        try:
            return val.encode('latin-1', errors='replace').decode('latin-1')
        except Exception:
            return val


def _serializar_valor_com_tipo(val, col_type):
    """Converte valores para tipos compatíveis com PostgreSQL com base no tipo da coluna."""
    if val is None:
        return None

    # Sanitizar strings para encoding WIN1252 do banco local
    if isinstance(val, str):
        val = _sanitizar_win1252(val)

    # Strings vazias em colunas nao-textuais quebram o INSERT no PostgreSQL.
    # Converte para NULL, mantendo vazios em colunas de texto.
    if isinstance(val, str) and val.strip() == '' and 'TEXT' not in col_type and 'CHAR' not in col_type and 'JSON' not in col_type:
        return None
        
    if 'JSON' in col_type:
        # Sanitizar recursivamente dict/list para remover chars WIN1252-incompativeis
        val = _sanitizar_win1252(val)
        if isinstance(val, (dict, list)):
            return Json(val)
        if isinstance(val, str):
            try:
                parsed = json.loads(val)
                parsed = _sanitizar_win1252(parsed)
                return Json(parsed)
            except Exception:
                return Json(val)
        return Json(val)
        
    if 'TIMESTAMP' in col_type or 'DATE' in col_type:
        if isinstance(val, (int, float)):
            try:
                ts = val / 1000.0 if val > 9999999999.0 else val
                return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
            except Exception:
                pass
        if isinstance(val, str):
            val_clean = val.strip('\'"')
            if val_clean.isdigit():
                if len(val_clean) == 13:
                    try:
                        return datetime.fromtimestamp(int(val_clean) / 1000.0, tz=timezone.utc).isoformat()
                    except Exception:
                        pass
                elif len(val_clean) == 10:
                    try:
                        return datetime.fromtimestamp(int(val_clean), tz=timezone.utc).isoformat()
                    except Exception:
                        pass
        return val

    return val


def fetch_updates_tabela(table_name, desde_timestamp, supabase_url, api_key, empresa_filtro=None):
    """Consulta dados novos na nuvem para uma tabela (executada concorrentemente).

    Quando `empresa_filtro` vem preenchido (empresa aberta no app) e a tabela
    tem a coluna empresa_id, baixa SOMENTE os registros dessa empresa.
    """
    if table_name.startswith('vw_') or table_name.startswith('view_'):
        return table_name, None, True

    global _colunas_e_tipos_cache
    colunas = _colunas_e_tipos_cache.get(table_name, {})

    # Filtro por empresa: só faz sentido em tabelas que são por empresa.
    # SEGURANÇA: se empresa_filtro está definida mas o cache de colunas não foi
    # carregado ainda (colunas vazio), NÃO baixamos dados — seria arriscado baixar
    # tudo sem o filtro. A próxima rodada do ciclo já terá o cache populado.
    filtro_empresa = ''
    if empresa_filtro:
        if 'empresa_id' in colunas:
            filtro_empresa = f"&empresa_id=eq.{urllib.parse.quote(str(empresa_filtro), safe='')}"
        elif not colunas:
            # Cache ainda não carregado para esta tabela: adiar download para
            # evitar baixar dados de TODAS as empresas sem filtro.
            print_log(
                f"[DOWNLOAD] {table_name}: cache de colunas vazio e empresa_filtro definida. "
                "Adiando download até o cache ser carregado (próximo ciclo).",
                Colors.YELLOW
            )
            return table_name, None, False, False
        # else: tabela sem empresa_id (ex.: 'empresas'), baixa normalmente sem filtro.

    col_ts = None
    for col in ('updated_at', 'created_at', 'criado_em', 'data_alteracao', 'data_venda', 'data'):
        if col in colunas:
            col_ts = col
            break

    # Paginação: buscar todos os registros em blocos de 1000
    all_rows = []
    offset = 0
    BATCH_SIZE = 1000
    
    while True:
        if col_ts:
            ts_encoded = urllib.parse.quote(desde_timestamp)
            params = (f"select=*&{col_ts}=gte.{ts_encoded}{filtro_empresa}"
                      f"&order={col_ts}.asc&limit={BATCH_SIZE}&offset={offset}")
        else:
            params = f"select=*{filtro_empresa}&limit={BATCH_SIZE}&offset={offset}"

        url = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}?{params}"
        rows, status_code = fetch_json(url, api_key)
        
        if rows is None:
            if offset == 0:
                # status_code 404 = tabela não existe no Supabase (cooldown)
                # status_code 0 = erro de rede/transitório (não marca cooldown)
                # 401/402/403 = nuvem bloqueada (cota/permissão): pausa tudo
                if status_code == 404:
                    return table_name, None, False, True   # is_404=True
                if status_code in BLOQUEIO_STATUS:
                    _marcar_bloqueio_nuvem(status_code)
                return table_name, None, False, False       # is_404=False
            break
        
        all_rows.extend(rows)
        
        if len(rows) < BATCH_SIZE:
            break
        offset += BATCH_SIZE
    
    return table_name, all_rows, True, False


# Tabelas em que o registro PERTENCE À PRÓPRIA empresa: o cadastro de empresas.
#
# Ali a coluna `empresa_id` guarda o MESMO id do registro (cada empresa aponta
# para ela mesma), entao filtrar por `empresa_id = empresa_ativa` esconderia as
# demais: cada PC so enxergaria a empresa que esta ativa nele — que e exatamente
# o sintoma "so aparece uma empresa" na tela de selecao. Nestas tabelas o filtro
# de empresa e dispensado na leitura E na gravacao. As demais tabelas seguem
# filtradas: dado de uma empresa nunca pode entrar no banco de outra.
TABELAS_SEM_FILTRO_DE_EMPRESA = frozenset({'empresas'})


def gravar_registros_locais(conn, table_name, rows, empresa_filtro=None, bloqueados=None):
    """Persiste no banco de dados local os dados baixados do Supabase.

    Se `empresa_filtro` for fornecido e a tabela tiver a coluna empresa_id,
    rejeita silenciosamente qualquer registro cujo empresa_id não coincida —
    isso garante que dados de empresas diferentes nunca se misturem no banco local.

    `bloqueados` ({tabela: {id: motivo}}, ver `ids_bloqueados_no_download`)
    protege o que NÃO pode ser sobrescrito pela nuvem: edição local ainda não
    enviada e conflito aberto esperando decisão. Sem essa trava, o download
    apagava a alteração do usuário antes de ela subir.

    Devolve `(importados, aplicados)`, onde `aplicados` é a lista dos ids que
    CHEGARAM a ser gravados (e não foram barrados). A LAN usa essa lista para não
    avançar o cursor por cima de uma linha protegida: se o cursor passasse, a
    alteração que ficou de fora nunca mais seria lida e o registro divergiria
    entre os dois PCs para sempre.
    """
    colunas_e_tipos = get_colunas_e_tipos_tabela(conn, table_name)
    colunas_local = set(colunas_e_tipos.keys())
    tabela_tem_empresa_id = 'empresa_id' in colunas_local

    importados = 0
    rejeitados_empresa = 0
    protegidos = 0
    aplicados = []
    ids_protegidos = (bloqueados or {}).get(table_name, {})
    # Ver se este cadastro de empresas e dos que NAO devem ser filtrados (ver
    # TABELAS_SEM_FILTRO_DE_EMPRESA). Sem isto, so a empresa ativa chegaria.
    aplicar_filtro_empresa = bool(empresa_filtro) and table_name not in TABELAS_SEM_FILTRO_DE_EMPRESA
    try:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL exodo.sync_mode = 'on'")
            for row in rows:
                row_filtrado = {k: v for k, v in row.items() if k in colunas_local}
                if not row_filtrado or 'id' not in row_filtrado:
                    continue

                # 🔒 TRAVA ANTI-SOBRESCRITA: este registro tem alteração local
                # pendente ou conflito aberto. A versão do banco local é a que
                # o usuário está vendo — a nuvem não pode passar por cima dela.
                if str(row_filtrado.get('id')) in ids_protegidos:
                    protegidos += 1
                    continue

                # ⛔ TRAVA DE EMPRESA (nível de gravação local): se a tabela tem
                # empresa_id e há uma empresa ativa definida, rejeitar qualquer
                # registro de outra empresa. Sem isso, dados de empresas diferentes
                # poderiam ser gravados no banco local e aparecer na tela errada.
                if aplicar_filtro_empresa and tabela_tem_empresa_id:
                    empresa_do_registro = str(row_filtrado.get('empresa_id') or '')
                    if empresa_do_registro and empresa_do_registro != str(empresa_filtro):
                        rejeitados_empresa += 1
                        continue

                colunas = list(row_filtrado.keys())
                valores = [_serializar_valor_com_tipo(row_filtrado[k], colunas_e_tipos.get(k, 'TEXT')) for k in colunas]
                cols_sql = ', '.join([f'"{c}"' for c in colunas])
                vals_sql = ', '.join(['%s'] * len(valores))
                upd_sql  = ', '.join([f'"{c}"=EXCLUDED."{c}"' for c in colunas if c != 'id'])
                # 🔒 TRAVA NO CONFLITO DE ID: o ON CONFLICT casa pela chave primária
                # `id`, que NÃO inclui a empresa. Sem o WHERE, um id igual em outra
                # empresa (ex.: produto "Diversos", ids curtos, timestamp colidente)
                # atualizaria a linha existente e ela trocaria de dono. O WHERE faz o
                # UPDATE do conflito só quando o dono atual é o mesmo que está chegando.
                guarda_empresa = (
                    ' WHERE "%s"."empresa_id" = EXCLUDED."empresa_id"' % table_name
                    if tabela_tem_empresa_id else ''
                )
                sql = f"""
                    INSERT INTO "{table_name}" ({cols_sql})
                    VALUES ({vals_sql})
                    ON CONFLICT (id) DO UPDATE SET {upd_sql}{guarda_empresa}
                """
                cur.execute(sql, valores)
                importados += 1
                aplicados.append(str(row_filtrado.get('id')))
        conn.commit()
        if rejeitados_empresa > 0:
            print_log(
                f"[DOWNLOAD] 🚨 ALARME: {rejeitados_empresa} registro(s) de OUTRAS empresas "
                f"rejeitados ao gravar em '{table_name}' (empresa_filtro='{empresa_filtro}'). "
                "A nuvem pode conter dados misturados — verifique o Supabase.",
                Colors.RED
            )
    except Exception as e_batch:
        conn.rollback()
        print_log(f"[DOWNLOAD] {table_name}: erro na transação em lote ({e_batch}). Iniciando modo resiliente...", Colors.YELLOW)
        importados = 0
        for row in rows:
            row_filtrado = {k: v for k, v in row.items() if k in colunas_local}
            if not row_filtrado or 'id' not in row_filtrado:
                continue

            # 🔒 TRAVA ANTI-SOBRESCRITA (modo resiliente): igual à do modo em lote.
            if str(row_filtrado.get('id')) in ids_protegidos:
                protegidos += 1
                continue

            # ⛔ TRAVA DE EMPRESA (modo resiliente): mesma verificação do modo em lote.
            if aplicar_filtro_empresa and tabela_tem_empresa_id:
                empresa_do_registro = str(row_filtrado.get('empresa_id') or '')
                if empresa_do_registro and empresa_do_registro != str(empresa_filtro):
                    rejeitados_empresa += 1
                    continue

            colunas = list(row_filtrado.keys())
            valores = [_serializar_valor_com_tipo(row_filtrado[k], colunas_e_tipos.get(k, 'TEXT')) for k in colunas]
            cols_sql = ', '.join([f'"{c}"' for c in colunas])
            vals_sql = ', '.join(['%s'] * len(valores))
            upd_sql  = ', '.join([f'"{c}"=EXCLUDED."{c}"' for c in colunas if c != 'id'])
            # 🔒 TRAVA NO CONFLITO DE ID (modo resiliente): igual à do modo em lote.
            guarda_empresa = (
                ' WHERE "%s"."empresa_id" = EXCLUDED."empresa_id"' % table_name
                if tabela_tem_empresa_id else ''
            )
            sql = f"""
                INSERT INTO "{table_name}" ({cols_sql})
                VALUES ({vals_sql})
                ON CONFLICT (id) DO UPDATE SET {upd_sql}{guarda_empresa}
            """
            try:
                with conn.cursor() as cur:
                    cur.execute("SET LOCAL exodo.sync_mode = 'on'")
                    cur.execute(sql, valores)
                conn.commit()
                importados += 1
                aplicados.append(str(row_filtrado.get('id')))
            except Exception as e_row:
                conn.rollback()
                print_log(f"[DOWNLOAD] {table_name} (Registro {row_filtrado.get('id')}): falha - {e_row}", Colors.RED)

    if rejeitados_empresa > 0:
        print_log(
            f"[DOWNLOAD] 🚨 ALARME: {rejeitados_empresa} registro(s) de OUTRAS empresas "
            f"rejeitados (modo resiliente) em '{table_name}' (empresa_filtro='{empresa_filtro}'). "
            "A nuvem pode conter dados misturados — verifique o Supabase.",
            Colors.RED
        )

    if protegidos > 0:
        print_log(
            f"[DOWNLOAD] {table_name}: {protegidos} registro(s) NÃO sobrescrito(s) — "
            "têm alteração local pendente ou conflito aberto (a versão local vale).",
            Colors.YELLOW,
        )

    if importados > 0:
        print_log(f"[DOWNLOAD] {table_name}: {importados} registro(s) recebidos da nuvem", Colors.GREEN)
        
    return importados, aplicados


def download_tabela(conn, table_name, supabase_url, api_key, desde_timestamp, empresa_filtro=None):
    """Baixa registros (wrapper síncrono legado para compatibilidade com outras chamadas)."""
    carregar_meta_colunas(conn)
    _, rows, sucesso, _ = fetch_updates_tabela(table_name, desde_timestamp, supabase_url, api_key, empresa_filtro)
    if not sucesso:
        return 0, False
    if not rows:
        return 0, True
    
    importados, _aplicados = gravar_registros_locais(
        conn, table_name, rows, empresa_filtro=empresa_filtro,
        bloqueados=ids_bloqueados_no_download(conn),
    )
    return importados, True


# Vira True depois da primeira limpeza desta execução do sincronizador.
_limpou_outras_empresas_nesta_execucao = False

_tem_tabela_log_cache = None


def _tem_tabela_log(conn):
    """A tabela de log do trigger existe? (cacheado por processo)"""
    global _tem_tabela_log_cache
    if _tem_tabela_log_cache is None:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_name = '_exodo_sync_log'
                    )
                """)
                _tem_tabela_log_cache = bool(cur.fetchone()[0])
        except Exception:
            _tem_tabela_log_cache = False
    return _tem_tabela_log_cache


def remover_dados_de_outras_empresas(conn, empresa_ativa, tabelas):
    """Apaga da base LOCAL as linhas das OUTRAS empresas.

    É o que faz a base local conter SOMENTE a empresa aberta no app.

    Seguranças:
      - roda com `exodo.sync_mode = 'on'`, então o trigger `log_sync_event` NÃO
        registra estes DELETEs e o sincronizador nunca os propaga para a nuvem
        (a nuvem não é tocada em nenhuma hipótese);
      - NUNCA apaga registro com alteração PENDENTE de envio (linha em
        `_exodo_sync_log`): o que ainda não subiu para a nuvem fica onde está;
      - respeita `_sincronizado_nuvem` quando a tabela tiver essa coluna;
      - tabelas sem a coluna empresa_id são ignoradas;
      - está DESLIGADA por padrão; para ligar,
        `_sync_controle['limpar_outras_empresas_local'] = true`.

    Nada se perde de vez: quando a outra empresa for aberta no app, o cursor
    dela (que é por empresa) é novo, então ela é baixada inteira de volta.
    """
    if not limpeza_da_base_local_habilitada(conn):
        print_log("[EMPRESA] Limpeza local das outras empresas está DESLIGADA "
                  "(padrão): a base local mantém os dados de todas as empresas. "
                  f"Para ligar: _sync_controle.{CHAVE_CTRL_LIMPAR_OUTRAS} = true.",
                  Colors.CYAN)
        return 0

    tem_log = _tem_tabela_log(conn)
    total_geral = 0
    for tabela in tabelas:
        # ⛔ TABELAS GLOBAIS: `empresas` e `usuarios` NÃO pertencem a uma empresa
        # só. Como `empresas` tem a coluna `empresa_id`, elas caíam aqui e o
        # DELETE `empresa_id IS DISTINCT FROM <ativa>` levava embora da base
        # local as empresas que não apontam para a empresa aberta — inclusive
        # as que têm `empresa_id` NULL. Era isso que fazia a lista de empresas
        # do app voltar com 2 linhas enquanto a nuvem tem 4, a cada ciclo.
        # (A nuvem nunca foi tocada: esses DELETEs não entram no log.)
        if tabela in TABELAS_GLOBAIS:
            continue
        colunas = _colunas_e_tipos_cache.get(tabela) or {}
        if 'empresa_id' not in colunas:
            continue
        where = "empresa_id IS DISTINCT FROM %s"
        params = [empresa_ativa]
        if '_sincronizado_nuvem' in colunas:
            where += " AND _sincronizado_nuvem IS NOT FALSE"
        if tem_log and 'id' in colunas:
            where += (" AND id NOT IN (SELECT record_id FROM _exodo_sync_log "
                      "WHERE table_name = %s)")
            params.append(tabela)
        try:
            with conn.cursor() as cur:
                cur.execute("SET exodo.sync_mode = 'on'")
                cur.execute(f'DELETE FROM "{tabela}" WHERE {where}', tuple(params))
                removidas = cur.rowcount
            conn.commit()
        except Exception as e:
            conn.rollback()
            print_log(f"[EMPRESA] {tabela}: falha ao limpar outras empresas ({e})", Colors.RED)
            continue
        if removidas:
            total_geral += removidas
            print_log(f"[EMPRESA] {tabela}: {removidas} linha(s) de OUTRAS empresas "
                      f"removidas da base local (somente local).", Colors.YELLOW)

    if total_geral:
        print_log(f"[EMPRESA] Base local agora contém somente a empresa ativa "
                  f"({total_geral} linha(s) de outras empresas removidas).", Colors.GREEN)
    else:
        print_log("[EMPRESA] Base local já continha somente a empresa ativa.", Colors.GREEN)
    return total_geral


# ─────────────────────────────────────────────────────────────────────────────
# Ciclo Otimizado Unificado e Bloqueio Reativo (LISTEN/NOTIFY)
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Agente de Status e Comandos Remotos (Supabase)
# ─────────────────────────────────────────────────────────────────────────────

def obter_cnpj_local(conn):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT cnpj FROM public.empresas LIMIT 1")
            row = cur.fetchone()
            if row:
                return row[0]
    except Exception as e:
        print_log(f"[SYNC] Erro ao obter CNPJ local: {e}", Colors.RED)
    return ""

def is_bridge_running():
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq ExodoNfceBridge.exe", "/NH"],
            capture_output=True, text=True, timeout=5,
            creationflags=0x08000000  # CREATE_NO_WINDOW
        )
        return "exodonfcebridge.exe" in result.stdout.lower()
    except Exception:
        return False

def atualizar_status_no_supabase(conn, supabase_url, api_key):
    try:
        pc_name = platform.node()
        cnpj = obter_cnpj_local(conn)
        versao_win = f"{platform.system()} {platform.release()} (v{platform.version()})"
        
        headers = {
            "Authorization": f"Bearer {api_key}",
            "apikey": api_key,
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates"
        }
        
        payload = {
            "id": pc_name,
            "pc_name": pc_name,
            "online": True,
            "ultimo_cnpj": cnpj,
            "versao_windows": versao_win,
            "versao_software": VERSION,  # Versao do sincronizador/sistema
            "ultima_atualizacao": datetime.now(timezone.utc).isoformat(),
            "configuracoes": {
                "bridge_running": is_bridge_running()
            }
        }
        
        url = f"{supabase_url.rstrip('/')}/rest/v1/bridge_status"
        requests.post(url, json=payload, headers=headers, timeout=10)
    except Exception as e:
        print_log(f"[SYNC] Erro ao atualizar status no Supabase: {e}", Colors.RED)

def reportar_sync_status_supabase(conn, supabase_url, api_key, enviados=0, recebidos=0, erro=None):
    """Reporta o status de sync no Supabase (sync_status + sync_logs) para o portal.
    Atualiza o status de cada empresa local para que o portal mostre o sync real,
    mesmo quando o app Flutter nao esta aberto."""
    try:
        pc_name = platform.node()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "apikey": api_key,
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates"
        }
        agora_iso = datetime.now(timezone.utc).isoformat()

        # Listar empresas locais (o sincronizador baixa dados de todas)
        empresas = []
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT id, cnpj FROM public.empresas")
                empresas = cur.fetchall()
        except Exception as e:
            print_log(f"[SYNC] Erro ao listar empresas locais: {e}", Colors.RED)

        if not empresas:
            return

        # 1. Atualizar sync_status (upsert por empresa_id)
        for emp_id, cnpj in empresas:
            try:
                payload = {
                    "empresa_id": str(emp_id),
                    "pc_name": pc_name,
                    "ultima_sincronizacao": agora_iso,
                    "ultimo_erro": erro if erro else "",
                    "ultimo_erro_data": agora_iso if erro else None,
                    "fila_pendente": 0,
                    "versao_app": VERSION,
                    "online": True,
                    "online_data": agora_iso,
                    "updated_at": agora_iso,
                }
                url = f"{supabase_url.rstrip('/')}/rest/v1/sync_status"
                r = requests.post(url, json=payload, headers=headers, timeout=10)
                if r.status_code not in (200, 201, 204):
                    print_log(f"[SYNC] sync_status empresa {str(emp_id)[:8]}: HTTP {r.status_code}", Colors.YELLOW)
            except Exception as e:
                print_log(f"[SYNC] Erro ao atualizar sync_status {str(emp_id)[:8]}: {e}", Colors.RED)

        # 2. Registrar evento em sync_logs somente quando houver movimento ou erro
        if (enviados + recebidos) > 0 or erro:
            for emp_id, cnpj in empresas:
                try:
                    evento = 'erro_sync' if erro else 'sync_ok'
                    if erro:
                        detalhes = f"Erro no sincronizador: {erro[:300]}"
                    else:
                        detalhes = f"Sincronizador: {recebidos} recebidos, {enviados} enviados"
                    payload = {
                        "empresa_id": str(emp_id),
                        "pc_name": pc_name,
                        "evento": evento,
                        "detalhes": detalhes,
                        "erro": erro if erro else "",
                        "created_at": agora_iso,
                    }
                    url = f"{supabase_url.rstrip('/')}/rest/v1/sync_logs"
                    requests.post(url, json=payload, headers=headers, timeout=10)
                except Exception as e:
                    print_log(f"[SYNC] Erro ao registrar sync_logs {str(emp_id)[:8]}: {e}", Colors.RED)
    except Exception as e:
        print_log(f"[SYNC] Erro ao reportar status no Supabase: {e}", Colors.RED)


def _versao_aplicada_local(conn, cfg_id):
    """Versão que ESTE PC já aplicou para uma config do bridge_config.

    Fica em `_sync_controle` (tabela local, NUNCA sincronizada): não serve o
    valor da nuvem, serve saber o que esta máquina realmente trocou.
    """
    if conn is None:
        return None
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT valor FROM _sync_controle WHERE chave=%s",
                        (f'versao_aplicada_{cfg_id}',))
            linha = cur.fetchone()
        return linha[0] if linha else None
    except Exception:
        return None


def _marcar_versao_aplicada_local(conn, cfg_id, versao):
    """Registra que esta máquina foi para `versao`."""
    if conn is None or not versao:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO _sync_controle (chave, valor) VALUES (%s, %s) "
                "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
                (f'versao_aplicada_{cfg_id}', str(versao)),
            )
        conn.commit()
    except Exception as e:
        print_log(f"[CMD] Não consegui gravar a versão aplicada de {cfg_id}: {e}",
                  Colors.YELLOW)
        try:
            conn.rollback()
        except Exception:
            pass


def executar_atualizacao_completa(supabase_url, api_key, conn=None):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "apikey": api_key
    }
    
    url = f"{supabase_url.rstrip('/')}/rest/v1/bridge_config"
    try:
        r = requests.get(url, headers=headers, timeout=20)
        if r.status_code != 200:
            return False, f"Erro ao consultar bridge_config: {r.status_code}"
            
        configs = r.json()
        downloads = {}
        for item in configs:
            cfg_id = item.get("id")
            download_url = item.get("download_url")
            version = item.get("version")
            if download_url:
                downloads[cfg_id] = (download_url, version)
                
        if not downloads:
            return False, "Nenhuma URL de download encontrada na tabela bridge_config."
            
        base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
        
        # Mapeamento do id da config para o nome do executável local
        file_map = {
            "app_latest": "sistema_exodo_novo.exe",
            "latest": "ExodoNfceBridge.exe",
            "sync_latest": "SincronizadorNuvem.exe"
        }
        
        baixados = []
        aplicadas = []   # [(cfg_id, ver)] efetivamente baixados
        pulados = []     # arquivos que já estavam na versão pedida
        for cfg_id, (url_dl, ver) in downloads.items():
            local_filename = file_map.get(cfg_id)
            if not local_filename:
                continue
                
            local_path = os.path.join(base_dir, local_filename)

            # Nada a fazer quando ESTA máquina já está na versão pedida. Sem
            # esta trava, um comando emitido para todos matava e relançava o
            # app numa máquina já atualizada — a janela "abria e fechava".
            if (ver and os.path.exists(local_path)
                    and _versao_aplicada_local(conn, cfg_id) == str(ver)):
                pulados.append(f'{local_filename} v{ver}')
                print_log(f"[CMD] {local_filename} já está na versão {ver}; pulando.",
                          Colors.CYAN)
                continue

            new_path = local_path + ".new"
            
            print_log(f"[CMD] Baixando {local_filename} versao {ver} de: {url_dl}", Colors.BLUE)
            r_dl = requests.get(url_dl, stream=True, timeout=120)
            if r_dl.status_code == 200:
                with open(new_path, "wb") as f:
                    for chunk in r_dl.iter_content(chunk_size=8192):
                        f.write(chunk)
                baixados.append(local_filename)
                aplicadas.append((cfg_id, ver))
            else:
                print_log(f"[CMD] Falha ao baixar {local_filename}: {r_dl.status_code}", Colors.RED)
                
        if not baixados:
            if pulados:
                return True, ("Já estava atualizado — nada a fazer ("
                              + ', '.join(pulados) + ").")
            return False, "Nenhum executavel foi baixado com sucesso."
            
        # Gravar o BAT de substituição
        # Usar VBScript em vez de .bat para NÃO abrir janela CMD visível.
        # O .bat com 'start ""' cria uma janela preta no cliente.
        vbs_path = os.path.join(base_dir, "update_exodo_system.vbs")
        
        vbs_lines = [
            'Set sh = CreateObject("WScript.Shell")',
            'WScript.Sleep 3000',
        ]
        
        # Matar processos antigos
        for proc in ['sistema_exodo_novo.exe', 'ExodoNfceBridge.exe', 
                      'ExodoNfceBridgeWatchdog.exe', 'SincronizadorNuvem.exe', 'python.exe']:
            vbs_lines.append(f'sh.Run "cmd /c taskkill /F /IM {proc}", 0, False')
        
        vbs_lines.append('WScript.Sleep 1500')
        
        # Mover arquivos baixados
        for filename in baixados:
            vbs_lines.append(f'sh.Run "cmd /c if exist \"{filename}.new\" move /Y \"{filename}.new\" \"{filename}\"", 0, True')
        
        # Reiniciar serviços (2º arg = 0 → sem janela)
        if 'ExodoNfceBridgeWatchdog.exe' in baixados:
            vbs_lines.append('sh.Run "cmd /c if exist \"ExodoNfceBridgeWatchdog.exe\" start /b \"\" \"ExodoNfceBridgeWatchdog.exe\"", 0, False')
        elif 'ExodoNfceBridge.exe' in baixados:
            vbs_lines.append('sh.Run "cmd /c if exist \"ExodoNfceBridge.exe\" start /b \"\" \"ExodoNfceBridge.exe\" --silent", 0, False')
        if 'SincronizadorNuvem.exe' in baixados:
            vbs_lines.append('sh.Run "cmd /c if exist \"SincronizadorNuvem.exe\" start /b \"\" \"SincronizadorNuvem.exe\"", 0, False')
        if 'sistema_exodo_novo.exe' in baixados:
            vbs_lines.append('sh.Run "cmd /c if exist \"sistema_exodo_novo.exe\" start /b \"\" \"sistema_exodo_novo.exe\"", 0, False')
        
        # Auto-deletar
        vbs_lines.append('WScript.Sleep 500')
        vbs_lines.append('Set fso = CreateObject("Scripting.FileSystemObject")')
        vbs_lines.append('fso.DeleteFile WScript.ScriptFullName')
        
        with open(vbs_path, "w", encoding="utf-8") as f:
            f.write("\r\n".join(vbs_lines))
            
        # Marcar as versões baixadas ANTES de disparar a troca: é o que evita
        # re-baixar/relançar a mesma versão no próximo comando.
        for cfg_id, ver in aplicadas:
            _marcar_versao_aplicada_local(conn, cfg_id, ver)

        # Disparar VBScript (roda tudo escondido, sem janela CMD)
        print_log(f"[CMD] Executando script de swap (VBScript) e fechando: {vbs_path}", Colors.BLUE)
        subprocess.Popen(['wscript.exe', vbs_path],
                         creationflags=0x08000000 if os.name == 'nt' else 0,
                         close_fds=True)
        
        # Usar um thread separado para fechar o synchronizador após o delay do BAT
        def self_exit():
            time.sleep(1)
            os._exit(0)
            
        import threading
        threading.Thread(target=self_exit).start()
        
        return True, f"Arquivos baixados: {', '.join(baixados)}. Aplicando swap e reiniciando."
    except Exception as e:
        return False, f"Erro durante atualizacao: {e}"

def processar_comandos_no_supabase(conn, supabase_url, api_key):
    pc_name = platform.node()
    pc_query = urllib.parse.quote(str(pc_name), safe='')
    headers = {
        "Authorization": f"Bearer {api_key}",
        "apikey": api_key,
        "Content-Type": "application/json"
    }
    
    # Buscar comandos pendentes para este PC ou sem target definido
    url_get = f"{supabase_url.rstrip('/')}/rest/v1/bridge_commands?status=eq.pendente&or=(target_pc.eq.{pc_query},target_pc.is.null)"
    
    try:
        r = requests.get(url_get, headers=headers, timeout=10)
        if r.status_code != 200:
            return
        
        comandos = r.json()
        for cmd in comandos:
            cmd_id = cmd.get("id")
            comando = cmd.get("comando")

            # Comando dirigido a um CNPJ ("Enviar direto pelo CNPJ"): só o PC
            # cujo emissor tem esse CNPJ pode executar. Sem isto, o comando
            # (que vai sem target_pc) disparava em toda a rede local — de novo
            # a atualização abrindo na máquina errada.
            try:
                extra = cmd.get('extra_data') or {}
                if isinstance(extra, str):
                    extra = json.loads(extra)
            except Exception:
                extra = {}
            cnpj_alvo = re.sub(r'\D', '', str(extra.get('cnpj') or ''))
            if cnpj_alvo and conn is not None:
                try:
                    cnpj_local = re.sub(r'\D', '',
                                        str(obter_cnpj_local(conn) or ''))
                except Exception:
                    cnpj_local = ''
                if cnpj_local != cnpj_alvo:
                    print_log(
                        f"[CMD] '{comando}' é para o CNPJ {cnpj_alvo}; este PC "
                        f"não é esse emissor — ignorando.", Colors.YELLOW)
                    continue
            
            print_log(f"[CMD] Recebido comando '{comando}' do Supabase!", Colors.BLUE)
            
            # Reivindicar o comando com COMPARE-AND-SWAP: só quem consegue
            # mudar 'pendente' -> 'processando' executa. Sem o filtro
            # status=eq.pendente, dois PCs que lessem a lista no mesmo
            # instante executavam o MESMO comando — era isso que fazia a
            # atualização "abrir e fechar" na máquina errada.
            url_claim = (f"{supabase_url.rstrip('/')}/rest/v1/bridge_commands"
                         f"?id=eq.{cmd_id}&status=eq.pendente")
            try:
                r_claim = requests.patch(
                    url_claim,
                    json={"status": "processando", "processor_pc": pc_name},
                    headers={**headers, "Prefer": "return=representation"},
                    timeout=10,
                )
                reservado = (r_claim.status_code in (200, 201, 204)
                             and bool(r_claim.json()))
            except Exception as e:
                reservado = False
                print_log(f"[CMD] Falha ao reservar o comando {cmd_id}: {e}",
                          Colors.YELLOW)
            if not reservado:
                # Outro PC chegou antes: este comando não é nosso.
                print_log("[CMD] Comando já reservado por outro PC — ignorando.",
                          Colors.YELLOW)
                continue

            # Daqui pra baixo o comando é nosso: a resposta final só pode
            # mexer na reserva DESTE PC.
            url_patch = (f"{supabase_url.rstrip('/')}/rest/v1/bridge_commands"
                         f"?id=eq.{cmd_id}&processor_pc=eq.{pc_query}")
            
            resultado = ""
            sucesso = False
            
            try:
                if comando == "restart":
                    print_log("[CMD] Reiniciando Bridge...", Colors.BLUE)
                    subprocess.run(["taskkill", "/F", "/IM", "ExodoNfceBridge.exe"], creationflags=0x08000000)
                    subprocess.run(["taskkill", "/F", "/IM", "ExodoNfceBridgeWatchdog.exe"], creationflags=0x08000000)
                    time.sleep(1)
                    
                    base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
                    watchdog_path = os.path.join(base_dir, "ExodoNfceBridgeWatchdog.exe")
                    if os.path.exists(watchdog_path):
                        subprocess.Popen([watchdog_path], creationflags=0x08000000 | 0x00000008)
                    else:
                        bridge_path = os.path.join(base_dir, "ExodoNfceBridge.exe")
                        if os.path.exists(bridge_path):
                            subprocess.Popen([bridge_path], creationflags=0x08000000 | 0x00000008)
                    resultado = "Bridge reiniciado com sucesso"
                    sucesso = True
                    
                elif comando == "update":
                    print_log("[CMD] Iniciando atualizacao do sistema via Supabase...", Colors.BLUE)
                    sucesso, resultado = executar_atualizacao_completa(
                        supabase_url, api_key, conn)
                    
                elif comando == "identify":
                    resultado = f"PC identificado: {pc_name}"
                    sucesso = True
                else:
                    resultado = f"Comando desconhecido: {comando}"
                    sucesso = False
            except Exception as e:
                resultado = f"Erro ao executar comando: {e}"
                sucesso = False
                
            # Atualizar resultado no Supabase (só a nossa reserva)
            try:
                requests.patch(url_patch, json={
                    "status": "concluido" if sucesso else "erro",
                    "resultado": resultado,
                    "sucesso": sucesso
                }, headers=headers, timeout=10)
            except Exception as e:
                print_log(f"[CMD] Falha ao reportar o resultado: {e}",
                          Colors.YELLOW)
            
    except Exception as e:
        print_log(f"[SYNC] Erro ao processar comandos: {e}", Colors.RED)

def executar_ciclo_sincronizacao(conn, supabase_url, api_key, on_state_change=None):
    """Executa o ciclo completo de sincronização utilizando downloads concorrentes em threads."""
    global _erros_do_ciclo
    _erros_do_ciclo = []

    if on_state_change:
        on_state_change('syncing')

    empresa_ativa = obter_empresa_ativa(conn)
    if empresa_ativa and not empresa_permite_sincronizacao_nuvem(conn, empresa_ativa):
        print_log(f"[EMPRESA] Nuvem desativada para {empresa_ativa}; ciclo pausado. Os dados locais e a fila foram preservados.", Colors.YELLOW)
        if on_state_change:
            on_state_change('paused')
        return 0, 0

    # Monitor de Conexão Inteligente: Testar conectividade antes de iniciar chamadas lentas à nuvem
    if not testar_conexao_supabase(supabase_url):
        print_log("[SYNC] Supabase inacessivel (Offline). Pulando ciclo.", Colors.YELLOW)
        if on_state_change:
            on_state_change('offline')
        return 0, 0

    carregar_meta_colunas(conn)
    garantir_tabela_controle(conn)

    # Empresa ABERTA no app (ponte via tabela local cache_dados). Preenchida =
    # importa somente ela. Vazia = comportamento antigo (todas as empresas).
    if empresa_ativa:
        print_log(f"[EMPRESA] Empresa ativa no app: {empresa_ativa} — "
                  f"importando somente os dados dela.", Colors.BLUE)
    else:
        print_log("[EMPRESA] O app ainda não publicou a empresa ativa: "
                  "importando todas (comportamento antigo).", Colors.YELLOW)
    
    # Configurar exodo.sync_mode = 'on' na sessão para desativar triggers em todas as conexões/transações do sincronizador
    with conn.cursor() as cur:
        cur.execute("SET exodo.sync_mode = 'on'")
    conn.commit()
    
    # Reportar status e processar comandos no Supabase. Com a nuvem em pausa
    # (401/402/403) essas chamadas só voltariam 402 de novo: o aviso do bloqueio
    # já foi dado e a pausa expira sozinha.
    if not nuvem_bloqueada():
        atualizar_status_no_supabase(conn, supabase_url, api_key)
        processar_comandos_no_supabase(conn, supabase_url, api_key)
    
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema='public'
              AND table_type='BASE TABLE'
              AND LEFT(table_name, 1) <> '_'
              AND LEFT(table_name, 3) <> 'vw_'
              AND LEFT(table_name, 5) <> 'view_'
              AND POSITION('_bkp_' IN table_name) = 0
              AND table_name NOT LIKE '%_bkp_%'  -- segurança extra: exclui qualquer tabela de backup
              AND table_name NOT IN ('cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos', 'exodo_config', 'sync_status', 'configuracoes_locais', 'sync_logs', 'usuarios')
              -- 'usuarios' excluido: senhas existem APENAS no banco local;
              -- baixar do Supabase sobrescreveria as senhas com NULL/vazio
              -- e quebraria o login. Upload continua funcionando normalmente.
            ORDER BY table_name
        """)
        tabelas = [r[0] for r in cur.fetchall()]

    # Fila de Sincronia por Prioridade: Ordenar tabelas com base na criticidade de negócio
    tabelas.sort(key=get_tabela_prioridade)

    total_recebidos = 0
    total_enviados = 0
    
    # 1. UPLOAD SEQUENCIAL (evita concorrência na tabela _exodo_sync_log)
    # Com a nuvem em pausa (401/402/403) o envio é pulado: bater na parede a cada
    # tabela só gera log. A fila em _exodo_sync_log fica intacta e sobe depois.
    # EXCEÇÃO `empresas`: o tratamento dela é SÓ local (apaga os proprios
    # registros da fila, sem tocar na rede). Pular essa limpeza deixaria cada
    # empresa recebida pela LAN eternamente marcada como "alteração local
    # pendente", e o par nunca mais poderia atualizar o cadastro.
    for tabela in tabelas:
        if _em_cooldown(tabela):
            continue
        if nuvem_bloqueada() and tabela != 'empresas':
            break
        enviados = upload_tabela(conn, tabela, supabase_url, api_key, empresa_ativa)
        total_enviados += enviados

    # 2. SAFEGUARD: Se tabelas críticas estão vazias mas _sync_controle tem
    #    timestamp antigo (desinstalação/corrupção), forçar full download.
    #    Sem isso, registros antigos nunca seriam baixados do Supabase.
    tabelas_vazias_localmente = set()
    for tabela in tabelas:
        try:
            with conn.cursor() as cur:
                cur.execute(f'SELECT COUNT(*) FROM "{tabela}"')
                count = cur.fetchone()[0]
            if count == 0:
                tabelas_vazias_localmente.add(tabela)
                ultima_salva = get_ultima_sync_tabela(conn, tabela, empresa_ativa)
                if ultima_salva != _EPOCH:
                    print_log(
                        f"[SYNC] ⚠️ Tabela '{tabela}' vazia mas timestamp de sync existe "
                        f"({ultima_salva}). Resetando para full download.",
                        Colors.YELLOW
                    )
                    salvar_ultima_sync_tabela(conn, tabela, _EPOCH, empresa_ativa)
        except Exception:
            pass  # Tabela pode não existir ainda; sem problema

    # 2.b Base local INTACTA: nada é apagado por troca de empresa. Em troca,
    #     quando a empresa aberta no app muda, os cursores dela voltam para a
    #     epoch e o passo 3 baixa a empresa inteira de novo — é isso que garante
    #     que os dados apareçam ao voltar para uma empresa já usada antes.
    #     A limpeza das outras empresas continua existindo, mas agora é opt-in
    #     (`_sync_controle.limpar_outras_empresas_local = true`).
    if empresa_ativa:
        global _limpou_outras_empresas_nesta_execucao
        garantir_base_local_completa(conn, empresa_ativa, tabelas)
        if deve_limpar_outras_empresas(
                conn, empresa_ativa, _limpou_outras_empresas_nesta_execucao):
            print_log(f"[EMPRESA] Empresa ativa {empresa_ativa}: limpando da base "
                      f"local os dados das outras empresas...", Colors.YELLOW)
            remover_dados_de_outras_empresas(conn, empresa_ativa, tabelas)
            _limpou_outras_empresas_nesta_execucao = True
        salvar_empresa_ativa_vista(conn, empresa_ativa)

    # 3. DOWNLOAD PARALELO: Executa as requisições HTTP na nuvem em paralelo
    futuros = []
    agora_iso = datetime.now(timezone.utc).isoformat()
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        for tabela in tabelas:
            # Pular tabelas em cooldown (404 recente no Supabase)
            if _em_cooldown(tabela):
                continue
            # Nuvem bloqueada (401/402/403): não abre 40+ requisições que vão
            # voltar com o mesmo erro — a pausa e a notícia já saíram.
            if nuvem_bloqueada():
                break
            ultima_sync_tabela = get_ultima_sync_tabela(conn, tabela, empresa_ativa)
            futuros.append(
                executor.submit(
                    fetch_updates_tabela,
                    tabela,
                    ultima_sync_tabela,
                    supabase_url,
                    api_key,
                    empresa_ativa
                )
            )

    # Registros que NÃO podem ser sobrescritos pela nuvem: alteração local ainda
    # pendente de envio e conflitos abertos esperando decisão. Montado UMA vez
    # por ciclo (é a mesma lista para todas as tabelas) e usado no download.
    bloqueados_no_download = ids_bloqueados_no_download(conn)
    if bloqueados_no_download:
        total_bloqueados = sum(len(v) for v in bloqueados_no_download.values())
        print_log(
            f"[DOWNLOAD] {total_bloqueados} registro(s) protegidos da nuvem "
            "(alteração local pendente ou conflito aberto).",
            Colors.CYAN,
        )

    # Grava os resultados de download de forma síncrona/sequencial no banco local
    for f in futuros:
        try:
            tabela, rows, sucesso, is_404 = f.result()
            if sucesso:
                if rows:
                    recebidos, _aplicados = gravar_registros_locais(
                        conn, tabela, rows,
                        empresa_filtro=empresa_ativa,
                        bloqueados=bloqueados_no_download,
                    )
                    total_recebidos += recebidos
                    # So avanca o timestamp da tabela se a gravacao teve sucesso.
                    # Se TODOS os registros falharam, o timestamp NAO avanca e a
                    # proxima rodada tenta de novo (evita perder registros).
                    if recebidos > 0:
                        salvar_ultima_sync_tabela(conn, tabela, agora_iso, empresa_ativa)
                elif tabela not in tabelas_vazias_localmente:
                    # Tabela com dados local e nada novo na nuvem: avanca o cursor.
                    salvar_ultima_sync_tabela(conn, tabela, agora_iso, empresa_ativa)
                # Tabela VAZIA localmente: o cursor fica onde está (epoch, logo
                # após o reset) e ela é re-checada no próximo ciclo — sem ficar
                # resetando e logando para sempre.
            else:
                if is_404:
                    # Tabela não existe no Supabase (404) — marcar cooldown
                    if tabela not in _tabelas_404_cooldown:
                        _marcar_cooldown(tabela)
                    # else: já em cooldown, silencioso
                else:
                    # Erro transiente (rede, timeout, 5xx) — não marca cooldown
                    # mas limita o log para não poluir
                    if nuvem_bloqueada():
                        # 401/402/403: não é transitório, a nuvem está bloqueada.
                        # Registra UMA vez e para de percorrer as tabelas.
                        registrar_erro_do_ciclo(
                            f"nuvem bloqueada (HTTP {motivo_bloqueio_nuvem()}): "
                            "downloads interrompidos no ciclo")
                        break
                    if tabela not in _tabelas_404_cooldown:
                        print_log(f"[SYNC] Falha transiente ao baixar tabela {tabela} (será reintentado)", Colors.YELLOW)
                        registrar_erro_do_ciclo(f"download {tabela}: falha na nuvem")
        except Exception as e:
            print_log(f"[SYNC] Excecao ao baixar/salvar tabela {tabela}: {e}", Colors.RED)
            registrar_erro_do_ciclo(f"download {tabela}: {e}")

    # Commit final para garantir que nenhuma transação fique aberta (idle in transaction)
    try:
        conn.commit()
    except Exception as e:
        try:
            conn.rollback()
        except:
            pass

    # Atualizar status final com base em conflitos pendentes
    if on_state_change:
        if tem_conflitos_pendentes(conn):
            on_state_change('conflict')
        elif nuvem_bloqueada():
            # Nuvem recusando o projeto (cota/permissão): mostra offline em vez
            # de "online", que mentiria — nada subiu nem desceu neste ciclo.
            on_state_change('offline')
        else:
            on_state_change('online')

    # Reportar status de sync para o portal (sync_status + sync_logs no Supabase).
    # Vai junto o resumo dos erros do ciclo: é isso que acende o alerta no
    # monitor de sincronização do admin.
    resumo_erros = None
    if _erros_do_ciclo:
        resumo_erros = ("; ".join(_erros_do_ciclo))[:1500]
        print_log(f"[SYNC] ⚠️ Ciclo com {len(_erros_do_ciclo)} erro(s) — reportando ao portal", Colors.YELLOW)
    if nuvem_bloqueada():
        # A nuvem recusou o relatório; insistir só gera HTTP 402 por ciclo.
        print_log(f"[SYNC] Relatório do ciclo não enviado: nuvem bloqueada "
                  f"(HTTP {motivo_bloqueio_nuvem()}).", Colors.YELLOW)
    else:
        reportar_sync_status_supabase(
            conn, supabase_url, api_key, total_enviados, total_recebidos,
            erro=resumo_erros
        )

    return total_enviados, total_recebidos


def aguardar_notificacao_ou_timeout(db_host, db_port, db_name, db_user, db_password, timeout=10):
    """Aguarda reativamente notificações (LISTEN) do PostgreSQL local ou cai no timeout."""
    conn = None
    try:
        conn = psycopg2.connect(
            host=db_host, port=db_port, dbname=db_name,
            user=db_user, password=db_password, connect_timeout=5,
            client_encoding='UTF8'
        )
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("LISTEN exodo_sync_event;")
        
        # select.select suspende passivamente a thread do Python no socket
        r, w, x = select.select([conn], [], [], timeout)
        if r:
            conn.poll()
            while conn.notifies:
                conn.notifies.pop()
            return True  # Acordou por notificação (operação local realizada)
    except Exception:
        time.sleep(timeout)
    finally:
        if conn:
            try:
                conn.close()
            except:
                pass
    return False  # Acordou por timeout


# ─────────────────────────────────────────────────────────────────────────────
# Loop principal de sincronização CLI
# ─────────────────────────────────────────────────────────────────────────────

def run_sync_loop(interval_seconds=10, status_callback=None):
    load_dotenv()

    supabase_url = os.getenv('SUPABASE_URL')
    api_key      = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
    db_host      = os.getenv('DB_HOST', 'localhost')
    db_port      = os.getenv('DB_PORT', '5432')
    db_name      = os.getenv('DB_NAME')
    db_user      = os.getenv('DB_USER')
    db_password  = os.getenv('DB_PASSWORD')

    if not all([supabase_url, api_key]):
        print_log("SUPABASE_URL ou chaves nao configuradas no .env!", Colors.RED)
        return

    if not all([db_name, db_user, db_password]):
        print_log("Variaveis PostgreSQL nao configuradas no .env!", Colors.RED)
        return

    print_log("Iniciando Sincronizador Bidirecional Otimizado (Local <-> Supabase)", Colors.BLUE)
    print_log(f"Supabase: {supabase_url}")
    print_log(f"Local:    {db_user}@{db_host}:{db_port}/{db_name}")
    print_log(f"Configuracao: Espera reativa ate {interval_seconds}s (LISTEN/NOTIFY ativo)")

    last_sync_time = 0
    last_full_sync_time = 0
    while True:
        agora = time.time()
        # Cooldown de 5 segundos para evitar CPU loops frenéticos se offline ou falha no socket select.select
        if agora - last_sync_time < 5.0:
            time.sleep(5.0 - (agora - last_sync_time))
            
        last_sync_time = time.time()
        conn = None
        try:
            conn = psycopg2.connect(
                host=db_host, port=db_port,
                dbname=db_name, user=db_user, password=db_password,
                connect_timeout=10,
                client_encoding='UTF8'
            )

            # Verificar se existem alterações locais pendentes na fila de envio
            has_pending = False
            with conn.cursor() as cur:
                # Verificar se a tabela _exodo_sync_log existe e se tem linhas
                cur.execute("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = '_exodo_sync_log'
                    );
                """)
                tabela_existe = cur.fetchone()[0]
                if tabela_existe:
                    cur.execute("SELECT 1 FROM _exodo_sync_log LIMIT 1;")
                    has_pending = cur.fetchone() is not None

            tempo_desde_ultimo = agora - last_full_sync_time
            if not has_pending and tempo_desde_ultimo < interval_seconds:
                # Nenhuma alteração local pendente e ainda dentro do intervalo periódico. Pula o ciclo.
                conn.close()
                aguardar_notificacao_ou_timeout(
                    db_host=db_host, db_port=db_port, db_name=db_name,
                    db_user=db_user, db_password=db_password, timeout=interval_seconds
                )
                continue

            last_full_sync_time = agora
            print_log("--- Inicio do ciclo de sincronizacao ---", Colors.BLUE)
            
            def log_state(state):
                print_log(f"Monitor de Conexao: Estado alterado para {state.upper()}", Colors.BLUE)

            total_enviados, total_recebidos = executar_ciclo_sincronizacao(
                conn, supabase_url, api_key, on_state_change=log_state
            )
            msg = f"Ciclo concluido: {total_enviados} enviados, {total_recebidos} recebidos"
            print_log(f"{msg}", Colors.GREEN)

            if status_callback:
                status_callback(msg)

        except psycopg2.OperationalError:
            print_log("Banco local indisponivel, tentando novamente em breve...", Colors.YELLOW)
        except Exception as e:
            print_log(f"Erro inesperado no ciclo: {e}", Colors.RED)
        finally:
            if conn is not None:
                try:
                    conn.close()
                except:
                    pass

        # Dorme de forma inteligente aguardando eventos ou timeout de verificação
        aguardar_notificacao_ou_timeout(
            db_host=db_host, db_port=db_port, db_name=db_name,
            db_user=db_user, db_password=db_password, timeout=interval_seconds
        )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Sincronizador Bidirecional Local <-> Supabase')
    parser.add_argument('--interval', type=int, default=60, help='Intervalo em segundos (padrao: 60)')
    args = parser.parse_args()
    try:
        run_sync_loop(args.interval)
    except KeyboardInterrupt:
        print_log("Sincronizacao encerrada pelo usuario.", Colors.YELLOW)
        sys.exit(0)

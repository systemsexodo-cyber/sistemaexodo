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
import select
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
import uuid

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from dotenv import load_dotenv
import requests

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

VERSION = "1.0.10"


class Colors:
    GREEN  = '\033[92m'
    RED    = '\033[91m'
    YELLOW = '\033[93m'
    BLUE   = '\033[94m'
    RESET  = '\033[0m'
    BOLD   = '\033[1m'


def print_log(msg, color=Colors.RESET):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {color}{msg}{Colors.RESET}")
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


def get_ultima_sync_tabela(conn, table_name):
    """Retorna o timestamp da última sincronização da tabela ou epoch se nunca rodou."""
    chave = f"sync_{table_name}"
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM _sync_controle WHERE chave=%s", (chave,))
        row = cur.fetchone()
    if row:
        return row[0]
    # Se não houver timestamp específico para a tabela, tenta buscar a global antiga
    with conn.cursor() as cur:
        cur.execute("SELECT valor FROM _sync_controle WHERE chave='ultima_sincronizacao'")
        row = cur.fetchone()
    if row:
        return row[0]
    return "1970-01-01T00:00:00+00:00"


def salvar_ultima_sync_tabela(conn, table_name, timestamp_iso):
    """Salva o timestamp da sincronização de uma tabela específica."""
    chave = f"sync_{table_name}"
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO _sync_controle (chave, valor)
            VALUES (%s, %s)
            ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor
        """, (chave, timestamp_iso))
    conn.commit()


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
    'vendas_balcao': 1,
    'pedidos': 1,
    'aberturas_caixa': 1,
    'fechamentos_caixa': 1,
    'sangrias_caixa': 1,
    'suprimentos_caixa': 1,
    'ordens_servico': 1,
    'nfces': 1,
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
    """Executa requisições GET usando a sessão Keep-Alive configurada."""
    headers = {
        'Accept':        'application/json',
        'apikey':        api_key,
        'Authorization': f'Bearer {api_key}',
    }
    session = get_http_session()
    try:
        response = session.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        print_log(f"HTTP {e.response.status_code}: {e.response.text}", Colors.RED)
        return None
    except Exception as e:
        print_log(f"Erro de conexao: {e}", Colors.RED)
        return None


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
def upload_tabela(conn, table_name, supabase_url, api_key):
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
        registros_to_upload = []
        identical_ids = set()
        
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
                        rows_nuvem = fetch_json(url_check, api_key)
                        if rows_nuvem:
                            for rn in rows_nuvem:
                                nuvem_dict[rn.get('id')] = rn
            except Exception as e_check:
                print_log(f"[CONFLITO] {table_name}: erro ao buscar registros para checagem - {e_check}", Colors.YELLOW)

        # Tratar conflitos e identificar registros idênticos
        if nuvem_dict:
            last_sync_time = get_ultima_sync_tabela(conn, table_name)
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
                            print_log(f"[CONFLITO] Detectado conflito na tabela '{table_name}' para registro ID '{record_id}'", Colors.YELLOW)
                            conflict_id = str(uuid.uuid4())
                            try:
                                with conn.cursor() as cur_conf:
                                    cur_conf.execute("SET LOCAL exodo.sync_mode = 'off'")
                                    cur_conf.execute("""
                                        INSERT INTO exodo_sync_conflitos (id, tabela, registro_id, dados_locais, dados_nuvem, resolvido, empresa_id)
                                        VALUES (%s, %s, %s, %s, %s, FALSE, %s)
                                        ON CONFLICT (id) DO NOTHING
                                    """, (
                                        conflict_id,
                                        table_name,
                                        record_id,
                                        json.dumps(row_local, default=str),
                                        json.dumps(row_nuvem, default=str),
                                        row_local.get('empresa_id', '')
                                    ))
                            except Exception as e_ins:
                                print_log(f"[CONFLITO] Erro ao registrar conflito: {e_ins}", Colors.RED)
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
            log_ids_to_delete.append(log_id)
                
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
                payload_str = json.dumps(chunk, default=str)
                response = session.post(url, data=payload_str, headers=headers, timeout=30)
                response.raise_for_status()
                enviados += len(chunk)
            
        if log_ids_to_delete:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM _exodo_sync_log WHERE id = ANY(%s)", (log_ids_to_delete,))
            conn.commit()
            
        if enviados > 0:
            print_log(f"[UPLOAD] {table_name}: {enviados} registro(s) enviados OK", Colors.GREEN)
        return enviados
        
    except requests.exceptions.HTTPError as e:
        conn.rollback()
        print_log(f"[UPLOAD] {table_name}: erro no envio HTTP {e.response.status_code} - {e.response.text}", Colors.RED)
        return 0
    except Exception as e:
        conn.rollback()
        print_log(f"[UPLOAD] {table_name}: erro no envio - {e}", Colors.RED)
        return 0


# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD: Supabase → Local
# ─────────────────────────────────────────────────────────────────────────────

def _serializar_valor_com_tipo(val, col_type):
    """Converte valores para tipos compatíveis com PostgreSQL com base no tipo da coluna."""
    if val is None:
        return None
        
    if 'JSON' in col_type:
        if isinstance(val, (dict, list)):
            return Json(val)
        if isinstance(val, str):
            try:
                parsed = json.loads(val)
                # Sempre retorna o valor envelopado com Json() para garantir
                # que o psycopg2 envie com aspas de string de JSON corretas.
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


def fetch_updates_tabela(table_name, desde_timestamp, supabase_url, api_key):
    """Consulta dados novos na nuvem para uma tabela (executada concorrentemente)."""
    if table_name.startswith('vw_') or table_name.startswith('view_'):
        return table_name, None, True

    global _colunas_e_tipos_cache
    colunas = _colunas_e_tipos_cache.get(table_name, {})
    
    col_ts = None
    for col in ('updated_at', 'created_at', 'criado_em', 'data_alteracao', 'data_venda', 'data'):
        if col in colunas:
            col_ts = col
            break

    if col_ts:
        ts_encoded = urllib.parse.quote(desde_timestamp)
        params = f"select=*&{col_ts}=gte.{ts_encoded}&order={col_ts}.asc&limit=1000"
    else:
        params = "select=*&limit=1000"

    url = f"{supabase_url.rstrip('/')}/rest/v1/{urllib.parse.quote(table_name, safe='')}?{params}"
    rows = fetch_json(url, api_key)
    
    if rows is None:
        return table_name, None, False
        
    return table_name, rows, True


def gravar_registros_locais(conn, table_name, rows):
    """Persiste no banco de dados local os dados baixados do Supabase."""
    colunas_e_tipos = get_colunas_e_tipos_tabela(conn, table_name)
    colunas_local = set(colunas_e_tipos.keys())
    
    importados = 0
    try:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL exodo.sync_mode = 'on'")
            for row in rows:
                row_filtrado = {k: v for k, v in row.items() if k in colunas_local}
                if not row_filtrado or 'id' not in row_filtrado:
                    continue
                colunas = list(row_filtrado.keys())
                valores = [_serializar_valor_com_tipo(row_filtrado[k], colunas_e_tipos.get(k, 'TEXT')) for k in colunas]
                cols_sql = ', '.join([f'"{c}"' for c in colunas])
                vals_sql = ', '.join(['%s'] * len(valores))
                upd_sql  = ', '.join([f'"{c}"=EXCLUDED."{c}"' for c in colunas if c != 'id'])
                sql = f"""
                    INSERT INTO "{table_name}" ({cols_sql})
                    VALUES ({vals_sql})
                    ON CONFLICT (id) DO UPDATE SET {upd_sql}
                """
                cur.execute(sql, valores)
                importados += 1
        conn.commit()
    except Exception as e_batch:
        conn.rollback()
        print_log(f"[DOWNLOAD] {table_name}: erro na transação em lote ({e_batch}). Iniciando modo resiliente...", Colors.YELLOW)
        importados = 0
        for row in rows:
            row_filtrado = {k: v for k, v in row.items() if k in colunas_local}
            if not row_filtrado or 'id' not in row_filtrado:
                continue
            colunas = list(row_filtrado.keys())
            valores = [_serializar_valor_com_tipo(row_filtrado[k], colunas_e_tipos.get(k, 'TEXT')) for k in colunas]
            cols_sql = ', '.join([f'"{c}"' for c in colunas])
            vals_sql = ', '.join(['%s'] * len(valores))
            upd_sql  = ', '.join([f'"{c}"=EXCLUDED."{c}"' for c in colunas if c != 'id'])
            sql = f"""
                INSERT INTO "{table_name}" ({cols_sql})
                VALUES ({vals_sql})
                ON CONFLICT (id) DO UPDATE SET {upd_sql}
            """
            try:
                with conn.cursor() as cur:
                    cur.execute("SET LOCAL exodo.sync_mode = 'on'")
                    cur.execute(sql, valores)
                conn.commit()
                importados += 1
            except Exception as e_row:
                conn.rollback()
                print_log(f"[DOWNLOAD] {table_name} (Registro {row_filtrado.get('id')}): falha - {e_row}", Colors.RED)

    if importados > 0:
        print_log(f"[DOWNLOAD] {table_name}: {importados} registro(s) recebidos da nuvem", Colors.GREEN)
        
    return importados


def download_tabela(conn, table_name, supabase_url, api_key, desde_timestamp):
    """Baixa registros (wrapper síncrono legado para compatibilidade com outras chamadas)."""
    carregar_meta_colunas(conn)
    _, rows, sucesso = fetch_updates_tabela(table_name, desde_timestamp, supabase_url, api_key)
    if not sucesso:
        return 0, False
    if not rows:
        return 0, True
    
    importados = gravar_registros_locais(conn, table_name, rows)
    return importados, True


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

def executar_atualizacao_completa(supabase_url, api_key):
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
        for cfg_id, (url_dl, ver) in downloads.items():
            local_filename = file_map.get(cfg_id)
            if not local_filename:
                continue
                
            local_path = os.path.join(base_dir, local_filename)
            new_path = local_path + ".new"
            
            print_log(f"[CMD] Baixando {local_filename} versao {ver} de: {url_dl}", Colors.BLUE)
            r_dl = requests.get(url_dl, stream=True, timeout=120)
            if r_dl.status_code == 200:
                with open(new_path, "wb") as f:
                    for chunk in r_dl.iter_content(chunk_size=8192):
                        f.write(chunk)
                baixados.append(local_filename)
            else:
                print_log(f"[CMD] Falha ao baixar {local_filename}: {r_dl.status_code}", Colors.RED)
                
        if not baixados:
            return False, "Nenhum executavel foi baixado com sucesso."
            
        # Gravar o BAT de substituição
        bat_path = os.path.join(base_dir, "update_exodo_system.bat")
        
        # Construir comandos do BAT
        bat_lines = [
            "@echo off",
            "timeout /t 3 /nobreak >nul",
            "taskkill /F /IM sistema_exodo_novo.exe >nul 2>&1",
            "taskkill /F /IM ExodoNfceBridge.exe >nul 2>&1",
            "taskkill /F /IM ExodoNfceBridgeWatchdog.exe >nul 2>&1",
            "taskkill /F /IM SincronizadorNuvem.exe >nul 2>&1",
            "taskkill /F /IM python.exe >nul 2>&1",
            "timeout /t 1 /nobreak >nul"
        ]
        
        for filename in baixados:
            bat_lines.append(f'if exist "{filename}.new" move /Y "{filename}.new" "{filename}"')
            
        # Reiniciar os serviços
        bat_lines.append('if exist "ExodoNfceBridgeWatchdog.exe" (start "" "ExodoNfceBridgeWatchdog.exe") else (if exist "ExodoNfceBridge.exe" start "" "ExodoNfceBridge.exe")')
        bat_lines.append('if exist "SincronizadorNuvem.exe" start "" "SincronizadorNuvem.exe"')
        bat_lines.append('if exist "sistema_exodo_novo.exe" start "" "sistema_exodo_novo.exe"')
        bat_lines.append('del "%~f0"')
        
        with open(bat_path, "w", encoding="ansi") as f:
            f.write("\n".join(bat_lines))
            
        # Disparar BAT e sair
        print_log(f"[CMD] Executando script de swap e fechando: {bat_path}", Colors.BLUE)
        subprocess.Popen([bat_path], shell=True)
        
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
    headers = {
        "Authorization": f"Bearer {api_key}",
        "apikey": api_key,
        "Content-Type": "application/json"
    }
    
    # Buscar comandos pendentes para este PC ou sem target definido
    url_get = f"{supabase_url.rstrip('/')}/rest/v1/bridge_commands?status=eq.pendente&or=(target_pc.eq.{pc_name},target_pc.is.null)"
    
    try:
        r = requests.get(url_get, headers=headers, timeout=10)
        if r.status_code != 200:
            return
        
        comandos = r.json()
        for cmd in comandos:
            cmd_id = cmd.get("id")
            comando = cmd.get("comando")
            
            print_log(f"[CMD] Recebido comando '{comando}' do Supabase!", Colors.BLUE)
            
            # Reivindicar o comando: marcar como 'processando'
            url_patch = f"{supabase_url.rstrip('/')}/rest/v1/bridge_commands?id=eq.{cmd_id}"
            requests.patch(url_patch, json={
                "status": "processando",
                "processor_pc": pc_name
            }, headers=headers, timeout=10)
            
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
                    sucesso, resultado = executar_atualizacao_completa(supabase_url, api_key)
                    
                elif comando == "identify":
                    resultado = f"PC identificado: {pc_name}"
                    sucesso = True
                else:
                    resultado = f"Comando desconhecido: {comando}"
                    sucesso = False
            except Exception as e:
                resultado = f"Erro ao executar comando: {e}"
                sucesso = False
                
            # Atualizar resultado no Supabase
            requests.patch(url_patch, json={
                "status": "concluido" if sucesso else "erro",
                "resultado": resultado,
                "sucesso": sucesso
            }, headers=headers, timeout=10)
            
    except Exception as e:
        print_log(f"[SYNC] Erro ao processar comandos: {e}", Colors.RED)

def executar_ciclo_sincronizacao(conn, supabase_url, api_key, on_state_change=None):
    """Executa o ciclo completo de sincronização utilizando downloads concorrentes em threads."""
    if on_state_change:
        on_state_change('syncing')

    # Monitor de Conexão Inteligente: Testar conectividade antes de iniciar chamadas lentas à nuvem
    if not testar_conexao_supabase(supabase_url):
        print_log("[SYNC] Supabase inacessivel (Offline). Pulando ciclo.", Colors.YELLOW)
        if on_state_change:
            on_state_change('offline')
        return 0, 0

    carregar_meta_colunas(conn)
    garantir_tabela_controle(conn)
    
    # Configurar exodo.sync_mode = 'on' na sessão para desativar triggers em todas as conexões/transações do sincronizador
    with conn.cursor() as cur:
        cur.execute("SET exodo.sync_mode = 'on'")
    conn.commit()
    
    # Reportar status e processar comandos no Supabase
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
              AND table_name NOT IN ('cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos')
            ORDER BY table_name
        """)
        tabelas = [r[0] for r in cur.fetchall()]

    # Fila de Sincronia por Prioridade: Ordenar tabelas com base na criticidade de negócio
    tabelas.sort(key=get_tabela_prioridade)

    total_recebidos = 0
    total_enviados = 0
    
    # 1. UPLOAD SEQUENCIAL (evita concorrência na tabela _exodo_sync_log)
    for tabela in tabelas:
        enviados = upload_tabela(conn, tabela, supabase_url, api_key)
        total_enviados += enviados

    # 2. DOWNLOAD PARALELO: Executa as requisições HTTP na nuvem em paralelo
    futuros = []
    agora_iso = datetime.now(timezone.utc).isoformat()
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        for tabela in tabelas:
            ultima_sync_tabela = get_ultima_sync_tabela(conn, tabela)
            futuros.append(
                executor.submit(
                    fetch_updates_tabela,
                    tabela,
                    ultima_sync_tabela,
                    supabase_url,
                    api_key
                )
            )

    # Grava os resultados de download de forma síncrona/sequencial no banco local
    for f in futuros:
        try:
            tabela, rows, sucesso = f.result()
            if sucesso:
                salvar_ultima_sync_tabela(conn, tabela, agora_iso)
                if rows:
                    recebidos = gravar_registros_locais(conn, tabela, rows)
                    total_recebidos += recebidos
            else:
                print_log(f"[SYNC] Falha ao baixar dados da tabela {tabela}", Colors.YELLOW)
        except Exception as e:
            print_log(f"[SYNC] Excecao ao baixar/salvar tabela {tabela}: {e}", Colors.RED)

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
        else:
            on_state_change('online')

    return total_enviados, total_recebidos


def aguardar_notificacao_ou_timeout(db_host, db_port, db_name, db_user, db_password, timeout=10):
    """Aguarda reativamente notificações (LISTEN) do PostgreSQL local ou cai no timeout."""
    conn = None
    try:
        conn = psycopg2.connect(
            host=db_host, port=db_port, dbname=db_name,
            user=db_user, password=db_password, connect_timeout=5
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
                connect_timeout=10
            )

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
    parser.add_argument('--interval', type=int, default=10, help='Intervalo em segundos (padrao: 10)')
    args = parser.parse_args()
    try:
        run_sync_loop(args.interval)
    except KeyboardInterrupt:
        print_log("Sincronizacao encerrada pelo usuario.", Colors.YELLOW)
        sys.exit(0)

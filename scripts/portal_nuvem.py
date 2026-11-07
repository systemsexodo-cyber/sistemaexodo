#!/usr/bin/env python3
"""Portal + API na MESMA origem, servidos pelo Funnel do Tailscale.

POR QUE ISSO EXISTE
-------------------
O site publicado no Firebase (https://exodosystems-1541d.web.app) chamava a
Data API da nuvem local em https://servidorsupabase.tail9b4943.ts.net/rest/v1.
Nos aparelhos com Tailscale esse hostname resolve para um endereco da rede
local (100.x). A partir do Chrome 142 a permissao "Local Network Access" faz o
navegador BLOQUEAR esse tipo de requisicao (site publico -> endereco local):

    blocked by CORS policy: Permission was denied for this request to
    access the `local` address space.

Resultado: o app abria, mas TODAS as listas ficavam vazias.

A CORRECAO
----------
Este servidor entrega o build web e a API no MESMO host do Funnel:

    https://servidorsupabase.tail9b4943.ts.net/            -> build/web
    https://servidorsupabase.tail9b4943.ts.net/rest/v1/... -> Kong :8001

Como a pagina e a API passam a ter a mesma origem, nao existe mais a mudanca
"publico -> local": o navegador nao bloqueia e o CORS deixa de ser necessario.

USO
---
    python scripts/portal_nuvem.py                # porta 8090, sem console
    pythonw scripts/portal_nuvem.py               # idem, sem janela (logon)

O `INICIAR_FUNNEL_SUPABASE.bat` sobe este servidor no logon e aponta o Funnel
HTTPS para ele (a porta 10000 do Postgres continua igual).
"""

from __future__ import annotations

import argparse
import gzip
import http.client
import json
import mimetypes
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

# Prefixos do Supabase que devem ir para o Kong local. Todo o resto e portal.
PREFIXOS_API = (
    "/rest/v1",
    "/auth/v1",
    "/storage/v1",
    "/realtime/v1",
    "/functions/v1",
)

# Cabecalhos hop-by-hop: nao podem ser repassados entre conexoes.
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
}

TIPOS_EXTRAS = {
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".json": "application/json; charset=utf-8",
    ".otf": "font/otf",
    ".ttf": "font/ttf",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".svg": "image/svg+xml",
    ".env": "text/plain; charset=utf-8",
    ".map": "application/json; charset=utf-8",
    ".symbols": "text/plain; charset=utf-8",
}

# Arquivos que NUNCA podem ficar em cache: sem isso o navegador continua
# rodando um build antigo depois de uma atualizacao.
SEM_CACHE = {"index.html", "app.env", "flutter_bootstrap.js", "version.json"}

# Payloads menores que isto nao compensam o custo de comprimir/decomprimir.
TAMANHO_MINIMO_GZIP = 1024

# ============================================================================
# LOCAL POSTGRESQL CONNECTION (read from .env in project root or .env.neon)
# ============================================================================
_local_pg_pool = None
_local_pg_lock = threading.Lock()

def _ler_env_local() -> dict:
    """Le o .env da raiz do projeto (onde roda o app Windows)."""
    import re
    base = Path(__file__).resolve().parent.parent
    candidatos = [
        base / ".env",
        base / ".env.neon",
        base.parent / ".env",
        base.parent / ".env.neon",
    ]
    for arq in candidatos:
        if arq.is_file():
            try:
                txt = arq.read_text(encoding="utf-8")
                vals = {}
                for line in txt.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"): continue
                    m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
                    if m:
                        k, v = m.groups()
                        v = v.strip()
                        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                            v = v[1:-1]
                        vals[k] = v
                if vals:
                    return vals
            except Exception:
                pass
    return {}

def _get_local_pg_dsn() -> str | None:
    """Monta a DSN do PostgreSQL local a partir do .env."""
    env = _ler_env_local()
    # Tentar DATABASE_URL primeiro
    for k in ("DATABASE_URL", "NEON_DATABASE_URL", "NEON_DATABASE_URL_UNPOOLED"):
        if env.get(k):
            return env[k]
    # Montar a partir das partes
    from urllib.parse import quote
    host = env.get("DB_HOST", "localhost")
    port = env.get("DB_PORT", "5432")
    name = env.get("DB_NAME", "exodo_db")
    user = env.get("DB_USER", "exodo_user")
    pwd = env.get("DB_PASSWORD", "ex@#$")
    # URL-encode password and user to handle special chars like #, @, etc.
    pwd_enc = quote(pwd, safe='')
    user_enc = quote(user, safe='')
    return f"postgresql://{user_enc}:{pwd_enc}@{host}:{port}/{name}"

_chave_api_cache: str | None = None

# Publicacao "tudo" (publicar_tudo.py) rodando em segundo plano: o build leva
# minutos, entao o painel dispara e acompanha o log em vez de esperar.
_publicacao_processo = None


def _chave_api_publica() -> str:
    """Chave anonima do Supabase (a mesma que o app web ja carrega em app.env).

    O painel administrativo fala com o Kong pelo mesmo host do portal e nao
    envia cabecalho `apikey`; sem ele o Kong responde 401 e as listas (empresas
    etc.) ficam vazias. Injetamos a chave apenas quando o cliente nao mandou
    nenhuma, preservando o JWT de quem ja esta autenticado.
    """
    global _chave_api_cache
    if _chave_api_cache is None:
        env = _ler_env_local()
        _chave_api_cache = (
            env.get("SUPABASE_ANON_KEY")
            or env.get("SUPABASE_SERVICE_ROLE_KEY")
            or ""
        ).strip()
    return _chave_api_cache


def _ler_fim_do_log(caminho, quantas: int) -> list[str]:
    """Ultimas `quantas` linhas do arquivo de log, lendo so o fim.

    O log do portal passa de 600 MB; ler o arquivo inteiro para pegar as
    ultimas linhas segurava centenas de MB na memoria a cada refresh do painel.
    """
    try:
        if not caminho or not caminho.is_file():
            return []
        bloco = 256 * 1024
        pedaco = b""
        with open(caminho, "rb") as arquivo:
            arquivo.seek(0, 2)
            restante = arquivo.tell()
            while restante > 0 and pedaco.count(b"\n") <= quantas:
                ler = min(bloco, restante)
                restante -= ler
                arquivo.seek(restante)
                pedaco = arquivo.read(ler) + pedaco
                bloco = min(bloco * 2, 8 * 1024 * 1024)
        return pedaco.decode("utf-8", "replace").splitlines()[-quantas:]
    except OSError:
        return []


def _get_local_pg_conn(dados: dict | None = None):
    """Retorna uma conexao psycopg2.

    Sem `dados`, conecta no PostgreSQL local desta maquina (via .env).
    Com `dados` (host/port/banco/usuario/senha), conecta no banco de outro
    cliente - e assim que a Central abre o banco de uma loja pela internet.
    """
    global _local_pg_pool
    try:
        import psycopg2
    except ImportError:
        raise RuntimeError("psycopg2 nao instalado no ambiente do portal (pip install psycopg2-binary)")

    if dados:
        dsn = _dsn_de_parametros(dados)
        # Se a senha nao foi informada (ex.: conexao padrao/local), usa o DSN
        # completo do PostgreSQL local (que ja vem com usuario/senha do .env).
        sem_senha = not (dados.get("senha") or dados.get("password"))
        if sem_senha:
            dsn_local = _get_local_pg_dsn()
            if dsn_local:
                dsn = dsn_local
    else:
        dsn = _get_local_pg_dsn()
    if not dsn:
        raise RuntimeError("Nao foi possivel montar DSN do PostgreSQL (verifique .env)")
    # Conexao remota via params_remotos
    if params_remotos and isinstance(params_remotos, dict) and params_remotos.get('host'):
        from urllib.parse import quote
        host = params_remotos.get('host')
        porta = str(params_remotos.get('porta') or params_remotos.get('port') or '5432')
        nome = params_remotos.get('banco') or params_remotos.get('dbname') or 'exodo_db'
        usuario = params_remotos.get('usuario') or params_remotos.get('user') or 'exodo_user'
        senha = params_remotos.get('senha') or params_remotos.get('password') or ''
        senha_enc = quote(str(senha), safe='')
        usuario_enc = quote(str(usuario), safe='')
        dsn_remoto = "postgresql://%s:%s@%s:%s/%s" % (usuario_enc, senha_enc, host, porta, nome)
        print("[MIGRATION REMOTO] Conectando em: " + dsn_remoto)
        return psycopg2.connect(dsn_remoto, connect_timeout=8)
    return psycopg2.connect(dsn, connect_timeout=8)


def _dsn_de_parametros(dados: dict) -> str:
    """Monta DSN a partir dos campos informados no painel (conexao remota)."""
    from urllib.parse import quote
    host = (dados.get("host") or "localhost").strip()
    porta = str(dados.get("porta") or dados.get("port") or "5432").strip()
    banco = (dados.get("banco") or dados.get("dbname") or "exodo_db").strip()
    usuario = (dados.get("usuario") or dados.get("user") or "exodo_user").strip()
    senha = dados.get("senha") or dados.get("password") or ""
    senha_enc = quote(str(senha), safe="")
    usuario_enc = quote(str(usuario), safe="")
    return "postgresql://%s:%s@%s:%s/%s" % (usuario_enc, senha_enc, host, porta, banco)


def _execute_local_sql(sql: str, params: tuple = None, fetch: bool = True, limit: int = 1000, dados: dict | None = None):
    """Executa SQL (local ou remoto) e retorna resultado como lista de dicts."""
    conn = _get_local_pg_conn(dados)
    try:
        conn.autocommit = True  # Para SELECTs e DDLs simples
        with conn.cursor() as cur:
            # Só passa `params` quando existem: com uma tupla vazia o psycopg2
            # trata a SQL como paramétrica e QUALQUER `%` (ex.: LIKE '%texto%')
            # vira placeholder — a consulta do painel quebrava com erro 500.
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            if fetch and cur.description:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchmany(limit)
                return [dict(zip(cols, r)) for r in rows]
            return {"affected_rows": cur.rowcount}
    finally:
        conn.close()

def _proxy_get(caminho: str, headers: dict):
    """GET simples para o Kong/PostgREST (chave de servico)."""
    conexao = http.client.HTTPConnection(ServidorPortal.api_host, ServidorPortal.api_port, timeout=60)
    conexao.request("GET", caminho, headers=headers)
    resposta = conexao.getresponse()
    dados = resposta.read()
    conexao.close()
    return resposta.status, dados


def _get_local_tables(schema: str = "public", dados: dict | None = None) -> list:
    """Lista tabelas de um banco (local ou remoto)."""
    sql = """
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = %s AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """
    return _execute_local_sql(sql, (schema,), fetch=True, dados=dados)

def _get_table_columns(table: str, schema: str = "public", dados: dict | None = None) -> list:
    """Lista colunas de uma tabela (local ou remoto)."""
    sql = """
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position
    """
    return _execute_local_sql(sql, (schema, table), fetch=True, dados=dados)


# ---------------------------------------------------------------------------
# CONEXOES SALVAS (para abrir o banco de cada loja/cliente pela Central)
# ---------------------------------------------------------------------------
CONEXOES_ARQUIVO = Path(__file__).resolve().parent.parent / "tool" / "central_conexoes.json"


def _ler_conexoes() -> list:
    try:
        if CONEXOES_ARQUIVO.is_file():
            dados = json.loads(CONEXOES_ARQUIVO.read_text(encoding="utf-8"))
            if isinstance(dados, list):
                return dados
    except Exception:
        pass
    return []


def _salvar_conexoes(lista: list) -> None:
    CONEXOES_ARQUIVO.parent.mkdir(parents=True, exist_ok=True)
    CONEXOES_ARQUIVO.write_text(
        json.dumps(lista, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _dados_conexao(fonte: dict | None) -> dict | None:
    """Normaliza os dados de conexao vindos do painel.

    Retorna None quando nao foi informado nada (usa o banco local do .env).
    """
    if not fonte:
        return None
    chaves = ("host", "porta", "banco", "usuario", "senha", "port", "dbname", "user", "password", "nome")
    if not any(fonte.get(k) for k in chaves):
        return None
    dados = {
        "host": fonte.get("host") or "localhost",
        "porta": str(fonte.get("porta") or fonte.get("port") or "5432"),
        "banco": fonte.get("banco") or fonte.get("dbname") or "exodo_db",
        "usuario": fonte.get("usuario") or fonte.get("user") or "exodo_user",
        "senha": fonte.get("senha") if fonte.get("senha") is not None else (fonte.get("password") or ""),
    }
    if not dados["senha"]:
        # Se so veio o nome de uma conexao salva, busca a senha guardada.
        nome = (fonte.get("nome") or "").strip()
        if nome:
            for salva in _ler_conexoes():
                if (salva.get("nome") or "").strip().lower() == nome.lower():
                    dados.update({k: salva.get(k, dados[k]) for k in ("host", "porta", "banco", "usuario", "senha")})
                    break
    return dados


def _conn_de_query(query: str) -> dict | None:
    """Le os dados de conexao da query string (GET)."""
    q = parse_qs(query)
    simples = {k: v[0] for k, v in q.items() if v}
    if simples.get("conexao"):
        simples["nome"] = simples["conexao"]
    return _dados_conexao(simples)


def _mascarar_conexao(c: dict) -> dict:
    copia = dict(c)
    if copia.get("senha"):
        copia["senha"] = "****"
    copia["tem_senha"] = bool(c.get("senha"))
    return copia


def _tipo_compresseivel(tipo: str) -> bool:
    """True para tipos textuais (vale comprimir); False para binarios que ja
    vem compactados (imagem, midia), onde so gastaria CPU.
    """
    t = tipo.lower().split(";")[0].strip()
    if t.startswith("text/"):
        return True
    return t in (
        "application/javascript",
        "application/json",
        "application/manifest+json",
        "application/wasm",
        "image/svg+xml",
        "font/otf",
        "font/ttf",
        "font/woff",
    )


def _comprimir_se_vale_a_pena(
    dados: bytes, tipo: str, aceita_gzip: bool, ja_codificado: str | None
) -> tuple[bytes, bool]:
    """Comprime payload de texto quando faz sentido.

    Devolve (dados_finais, comprimido). Nao mexe em resposta que ja veio
    codificada (o remetente ja cuidou disso) e so troca quando o resultado
    fica realmente menor.

    POR QUE ISSO EXISTE: o `main.dart.js` tem ~11 MB e o Funnel do Tailscale
    nao comprime. Sem gzip o celular fora da loja fica preso numa tela preta
    esperando o bundle inteiro baixar.
    """
    if ja_codificado:
        return dados, False
    if not aceita_gzip or len(dados) < TAMANHO_MINIMO_GZIP:
        return dados, False
    if not _tipo_compresseivel(tipo):
        return dados, False
    compactado = gzip.compress(dados, 6)
    if len(compactado) >= len(dados):
        return dados, False
    return compactado, True


# Comprimir o main.dart.js (~11 MB) custa ~0,6 s de CPU por acesso. Guardamos
# o resultado por arquivo para nao recomprimir a cada visitante; invalida so
# quando o proprio arquivo muda (mtime/tamanho).
_cache_gzip: dict[str, tuple[int, int, bytes]] = {}


def _comprimir_arquivo(
    arquivo: Path, dados: bytes, tipo: str, aceita_gzip: bool
) -> tuple[bytes, bool]:
    """Igual [_comprimir_se_vale_a_pena], mas memoriza por arquivo."""
    if not aceita_gzip:
        return dados, False
    try:
        st = arquivo.stat()
        chave = str(arquivo.resolve())
        mtime, tamanho = st.st_mtime_ns, st.st_size
    except OSError:
        return _comprimir_se_vale_a_pena(dados, tipo, aceita_gzip, None)

    guardado = _cache_gzip.get(chave)
    if guardado is not None and guardado[0] == mtime and guardado[1] == tamanho:
        return guardado[2], True

    comprimido, ok = _comprimir_se_vale_a_pena(dados, tipo, aceita_gzip, None)
    if ok:
        if len(_cache_gzip) > 64:
            _cache_gzip.clear()
        _cache_gzip[chave] = (mtime, tamanho, comprimido)
    return comprimido, ok


class ServidorPortal(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # No Windows, SO_REUSEADDR deixa DUAS instancias escutarem a mesma porta e
    # as requisicoes passam a cair em qualquer uma delas. Desligado de
    # proposito: a segunda instancia falha ao subir (a primeira continua).
    allow_reuse_address = False

    # Preenchidos em main() apos resolver os argumentos.
    raiz: Path = Path("build/web")
    api_host: str = "127.0.0.1"
    api_port: int = 8001
    log_path: Path | None = None

    # ------------------------------------------------------------------ log
    def log_message(self, fmt: str, *args) -> None:
        linha = "[%s] %s - %s\n" % (
            time.strftime("%Y-%m-%d %H:%M:%S"),
            self.address_string(),
            fmt % args,
        )
        # Sob `pythonw` (logon sem janela) sys.stdout e None: escrever nele
        # derrubava a requisicao com "Empty reply from server".
        try:
            if sys.stdout is not None:
                sys.stdout.write(linha)
                sys.stdout.flush()
        except (AttributeError, OSError):
            pass
        if self.log_path is not None:
            try:
                with self.log_path.open("a", encoding="utf-8") as f:
                    f.write(linha)
            except OSError:
                pass

    # -------------------------------------------------------------- roteador
    def _e_api(self, caminho: str) -> bool:
        return any(
            caminho == p or caminho.startswith(p + "/") for p in PREFIXOS_API
        )

    def _e_admin(self, caminho: str) -> bool:
        return caminho == "/central-servidor" or caminho.startswith("/central-servidor/") or \
               caminho == "/admin" or caminho.startswith("/admin/")

    def _responder(self, metodo: str, com_corpo: bool) -> None:
        partes = urlsplit(self.path)
        caminho = partes.path or "/"
        try:
            if self._e_api(caminho):
                self._proxy(metodo, com_corpo)
            elif self._e_admin(caminho):
                self._admin(metodo, caminho, com_corpo)
            elif metodo in ("GET", "HEAD"):
                self._estatico(caminho, com_corpo)
            else:
                self._erro(405, "Metodo nao permitido")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:  # nunca derrubar o servidor por uma requisicao
            self.log_message("ERRO %s %s: %s", metodo, self.path, e)
            try:
                self._erro(502, "Falha interna no portal: %s" % e)
            except Exception:
                pass

    def do_GET(self) -> None:  # noqa: N802
        self._responder("GET", True)

    def do_HEAD(self) -> None:  # noqa: N802
        self._responder("HEAD", False)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._responder("OPTIONS", True)

    def do_POST(self) -> None:  # noqa: N802
        self._responder("POST", True)

    def do_PUT(self) -> None:  # noqa: N802
        self._responder("PUT", True)

    def do_PATCH(self) -> None:  # noqa: N802
        self._responder("PATCH", True)

    def do_DELETE(self) -> None:  # noqa: N802
        self._responder("DELETE", True)

    # ---------------------------------------------------------------- proxy
    def _corpo_da_requisicao(self) -> bytes:
        tamanho = self.headers.get("Content-Length")
        if not tamanho:
            return b""
        try:
            return self.rfile.read(int(tamanho))
        except (ValueError, OSError):
            return b""

    def _aceita_gzip(self) -> bool:
        """O cliente aceita gzip? Navegador sempre manda; ferramentas nem sempre."""
        aceita = self.headers.get("Accept-Encoding", "")
        for item in aceita.split(","):
            codigo = item.split(";")[0].strip().lower()
            if codigo in ("gzip", "*"):
                return True
        return False

    def _proxy(self, metodo: str, com_corpo: bool) -> None:
        corpo = self._corpo_da_requisicao()
        cabecalhos = {}
        for chave, valor in self.headers.items():
            if chave.lower() in HOP_BY_HOP:
                continue
            cabecalhos[chave] = valor
        # O Kong fala com o PostgREST local: o Host do Funnel nao serve la.
        cabecalhos["Host"] = "%s:%d" % (self.api_host, self.api_port)

        caminho_api = urlsplit(self.path).path
        if any(
            caminho_api == p or caminho_api.startswith(p + "/")
            for p in PREFIXOS_API
        ):
            if not any(k.lower() == "apikey" for k in cabecalhos):
                chave = _chave_api_publica()
                if chave:
                    cabecalhos["apikey"] = chave
                    if not any(k.lower() == "authorization" for k in cabecalhos):
                        cabecalhos["Authorization"] = "Bearer " + chave

        conexao = http.client.HTTPConnection(
            self.api_host, self.api_port, timeout=120
        )
        try:
            conexao.request(metodo, self.path, body=corpo, headers=cabecalhos)
            resposta = conexao.getresponse()
            dados = resposta.read()
            # A carga inicial baixa ~30 tabelas de uma vez e o Kong local nao
            # comprime; sem gzip isso segurava o primeiro desenho da tela.
            dados, comprimido = _comprimir_se_vale_a_pena(
                dados,
                resposta.getheader("Content-Type") or "",
                self._aceita_gzip(),
                resposta.getheader("Content-Encoding"),
            )
            self.send_response(resposta.status, resposta.reason)
            for chave, valor in resposta.getheaders():
                if chave.lower() in HOP_BY_HOP or chave.lower() == "content-length":
                    continue
                if comprimido and chave.lower() == "content-encoding":
                    continue
                self.send_header(chave, valor)
            if comprimido:
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Vary", "Accept-Encoding")
            self.send_header("Content-Length", str(len(dados)))
            self.end_headers()
            if com_corpo:
                self.wfile.write(dados)
        finally:
            conexao.close()

    # ---------------------------------------------------------------- admin
    def _admin(self, metodo: str, caminho: str, com_corpo: bool) -> None:
        """Admin panel routes: /central-servidor/ (UI) and /admin/ (API)."""
        # Normalize path
        if caminho == "/central-servidor":
            caminho = "/central-servidor/"
        if caminho == "/admin":
            caminho = "/admin/"

        # Serve admin UI
        if caminho.startswith("/central-servidor/"):
            if metodo not in ("GET", "HEAD"):
                self._erro(405, "Metodo nao permitido")
                return
            # Serve the admin panel HTML
            admin_html = Path(__file__).resolve().parent / "admin_panel.html"
            if not admin_html.is_file():
                # Fallback inline
                fallback_html = """<!DOCTYPE html><html><head><meta charset="utf-8"><title>Central da Nuvem</title>
<style>body{font-family:sans-serif;background:#0f172a;color:#e2e8f0;padding:2rem;max-width:800px;margin:0 auto}
.card{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:1.5rem;margin:1rem 0}
.btn{background:#3b82f6;color:#fff;border:none;padding:0.75rem 1.5rem;border-radius:8px;cursor:pointer;font-size:1rem}
.btn:hover{background:#2563eb}input,textarea{background:#0f172a;border:1px solid #334155;color:#e2e8f0;padding:0.5rem;border-radius:6px;width:100%;margin:0.5rem 0}
pre{background:#0f172a;border:1px solid #334155;padding:1rem;overflow:auto;max-height:400px}</style>
</head><body>
<h1>Central da Nuvem</h1>
<div class="card"><h3>Admin panel nao encontrado</h3>
<p>Copie <code>scripts/admin_panel.html</code> para <code>build/web/central-servidor/index.html</code> ou reinicie o portal.</p>
<button class="btn" onclick="location.reload()">Recarregar</button>
</div></body></html>"""
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                if com_corpo:
                    self.wfile.write(fallback_html.encode("utf-8"))
                return
            self._servir_arquivo_admin(admin_html, com_corpo)
            return

        # Admin API endpoints
        if caminho.startswith("/admin/"):
            api_path = caminho[6:]  # remove "/admin"
            self._admin_api(metodo, api_path, com_corpo)
            return

        self._erro(404, "Nao encontrado")

    def _servir_arquivo_admin(self, arquivo: Path, com_corpo: bool) -> None:
        """Serve admin panel HTML with no-cache."""
        try:
            dados = arquivo.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Content-Length", str(len(dados)))
            self.end_headers()
            if com_corpo:
                self.wfile.write(dados)
        except OSError:
            self._erro(404, "Admin panel nao encontrado")

    def _admin_api(self, metodo: str, caminho: str, com_corpo: bool) -> None:
        """Admin API: /admin/repair, /admin/logs, /admin/exec-sql, etc."""
        import json
        import subprocess
        import sys
        from datetime import datetime, timezone

        global _publicacao_processo

        # Normalize path for matching
        api_path = caminho.lstrip("/")

        if api_path == "repair" and metodo == "POST":
            try:
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}
                listas = params.get("listas", ["perfis_tributarios"])
                aplicar = params.get("aplicar", False)

                raiz = Path(__file__).resolve().parent.parent
                scripts_por_lista = {
                    "perfis_tributarios": raiz / "tool" / "reparar_perfis_cloud.py",
                    "perfis_preco": raiz / "tool" / "check_other_lists.py",
                    "departamentos": raiz / "tool" / "check_other_lists.py",
                    "estoques": raiz / "tool" / "check_other_lists.py",
                }

                saidas = []
                sucesso_total = True
                executados = set()
                for lista in listas:
                    script = scripts_por_lista.get(lista)
                    if not script or not script.is_file():
                        saidas.append({"lista": lista, "sucesso": False, "erro": "script nao encontrado: %s" % script})
                        sucesso_total = False
                        continue
                    chave = str(script)
                    if chave in executados:
                        continue
                    executados.add(chave)
                    cmd = [sys.executable, str(script)]
                    if aplicar:
                        cmd.append("--aplicar")
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=str(raiz))
                    ok = result.returncode == 0
                    sucesso_total = sucesso_total and ok
                    saidas.append({
                        "lista": lista,
                        "script": script.name,
                        "sucesso": ok,
                        "stdout": result.stdout,
                        "stderr": result.stderr,
                    })

                response = {
                    "sucesso": sucesso_total,
                    "aplicar": aplicar,
                    "resultados": saidas,
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
            except Exception as e:
                response = {"sucesso": False, "erro": str(e), "timestamp": datetime.now(timezone.utc).isoformat()}

            self._json_response(response)
            return

        if api_path == "logs" and metodo == "GET":
            # `?linhas=N` (padrao 200, limite 50000). Le so o FIM do arquivo:
            # o log passa de 600 MB e um readlines() inteiro segurava tudo na
            # memoria. Cada linha traz o level pelo codigo HTTP: >=500 erro,
            # >=400 aviso, o resto e acesso normal.
            try:
                import re as _re
                from urllib.parse import parse_qs as _parse_qs
                from urllib.parse import urlsplit as _urlsplit

                try:
                    pedido = int(_parse_qs(_urlsplit(self.path).query).get("linhas", ["200"])[0])
                except (TypeError, ValueError):
                    pedido = 200
                quantas = max(1, min(pedido, 50000))
                linhas = _ler_fim_do_log(self.log_path, quantas)

                response = []
                for linha in linhas:
                    achado = _re.search(r'"\s+(\d{3})\s', linha)
                    codigo = int(achado.group(1)) if achado else 0
                    if codigo >= 500:
                        nivel = "error"
                    elif codigo >= 400:
                        nivel = "warning"
                    else:
                        nivel = "info"
                    response.append({
                        "time": linha.split("]")[0] + "]" if "]" in linha else "",
                        "msg": linha.split("]", 1)[1].strip() if "]" in linha else linha.strip(),
                        "level": nivel,
                        "status": codigo,
                    })
            except Exception as e:
                response = [{"time": datetime.now().isoformat(), "msg": "Erro ao ler logs: " + str(e), "level": "error", "status": 0}]
            self._json_response(response)
            return

        if api_path == "publicar" and metodo == "POST":
            # Dispara `publicar_tudo.py` em segundo plano (compila Windows, sobe
            # o pacote, grava a bridge_config e recompila o site). O painel
            # acompanha por /admin/publicar/status.
            try:
                import os as _os
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}

                if _publicacao_processo is not None and _publicacao_processo.poll() is None:
                    self._json_response({
                        "iniciado": False,
                        "erro": "ja existe uma publicacao em andamento",
                        "pid": _publicacao_processo.pid,
                    })
                    return

                raiz = Path(__file__).resolve().parent.parent
                comando = [sys.executable, "publicar_tudo.py",
                           (params.get("destino") or "global").strip()]
                versao = (params.get("versao") or "").strip()
                if versao:
                    comando.append(versao)
                if params.get("force"):
                    comando.append("--force")
                if (params.get("notas") or "").strip():
                    comando += ["--notas", str(params.get("notas"))]
                if params.get("sem_build_windows"):
                    comando.append("--sem-build-windows")
                if params.get("sem_build_web"):
                    comando.append("--sem-build-web")
                if params.get("simular"):
                    comando.append("--simular")

                destino_log = raiz / "logs" / "publicar_tudo.log"
                destino_log.parent.mkdir(exist_ok=True)
                arquivo = open(destino_log, "a", encoding="utf-8", errors="replace")
                arquivo.write("\n\n===== PUBLICACAO %s =====\n"
                              % datetime.now().strftime("%d/%m/%Y %H:%M:%S"))
                arquivo.flush()

                ambiente = dict(_os.environ)
                ambiente["PYTHONIOENCODING"] = "utf-8"
                ambiente["PYTHONUNBUFFERED"] = "1"
                _publicacao_processo = subprocess.Popen(
                    comando,
                    cwd=str(raiz),
                    stdout=arquivo,
                    stderr=subprocess.STDOUT,
                    env=ambiente,
                )
                self._json_response({
                    "iniciado": True,
                    "pid": _publicacao_processo.pid,
                    "log": str(destino_log),
                    "comando": comando,
                })
            except Exception as e:
                self._json_response({"iniciado": False, "erro": str(e)})
            return

        if api_path == "publicar/status" and metodo == "GET":
            rodando = (_publicacao_processo is not None
                       and _publicacao_processo.poll() is None)
            raiz = Path(__file__).resolve().parent.parent
            linhas = _ler_fim_do_log(raiz / "logs" / "publicar_tudo.log", 300)
            self._json_response({
                "rodando": rodando,
                "pid": getattr(_publicacao_processo, "pid", None),
                "codigo_saida": None if rodando or _publicacao_processo is None
                                else _publicacao_processo.returncode,
                "linhas": linhas,
            })
            return

        if api_path == "pacotes" and metodo == "GET":
            # Lista os pacotes .zip do bucket `atualizacoes`, para o painel
            # pre-preencher a versao em vez de digitar a mao. Precisa da chave
            # de servico: a anonima tem leitura do objeto publico, mas nao
            # permissao de LISTAR o bucket.
            try:
                import re
                import urllib.request

                env = _ler_env_local()
                chave = (env.get("SUPABASE_SERVICE_ROLE_KEY")
                         or env.get("SUPABASE_ANON_KEY") or "").strip()
                base = (env.get("SUPABASE_URL") or "http://127.0.0.1:8001").rstrip("/")
                corpo = json.dumps({
                    "prefix": "", "limit": 500, "offset": 0,
                    "sortBy": {"column": "name", "order": "asc"},
                }).encode("utf-8")
                req = urllib.request.Request(
                    base + "/storage/v1/object/list/atualizacoes",
                    data=corpo,
                    method="POST",
                    headers={
                        "apikey": chave,
                        "Authorization": "Bearer " + chave,
                        "Content-Type": "application/json",
                    },
                )
                with urllib.request.urlopen(req, timeout=15) as resp:
                    itens = json.loads(resp.read().decode("utf-8", "replace"))
                versoes = []
                for item in itens or []:
                    achado = re.match(
                        r"^sistema_exodo_novo_(\d[\w.\-]*)\.zip$",
                        str(item.get("name") or ""),
                    )
                    if not achado:
                        continue
                    versoes.append({
                        "versao": achado.group(1),
                        "bytes": (item.get("metadata") or {}).get("size"),
                        "atualizado_em": item.get("updated_at"),
                    })
                versoes.sort(key=lambda v: [
                    int(parte) if parte.isdigit() else 0
                    for parte in v["versao"].split(".")
                ])
                response = {"sucesso": True, "versoes": versoes}
            except Exception as e:
                response = {"sucesso": False, "erro": str(e), "versoes": []}
            self._json_response(response)
            return

        if api_path == "exec-sql" and metodo == "POST":
            # This would need a PostgREST function to execute arbitrary SQL
            # For now return guidance
            response = {"sucesso": False, "msg": "Use PostgREST REST API ou crie uma function RPC no Postgres para SQL arbitrário", "timestamp": datetime.now(timezone.utc).isoformat()}
            self._json_response(response)
            return

        if api_path == "debug" and metodo == "GET":
            # Return debug info via proxy to Supabase
            self._proxy("GET", True)  # Will be handled by normal proxy
            return

        # --- Novo: Disparar workflow GitHub Actions ---
        if api_path == "github/dispatch" and metodo == "POST":
            try:
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}
                workflow = params.get("workflow", "flutter_web")
                ref = params.get("ref", "main")
                # Se tiver secret GITHUB_TOKEN no .env, usa ele; senão usa anon key
                env = _ler_env_local()
                github_token = env.get("GITHUB_TOKEN", "")
                headers = {
                    "Accept": "application/vnd.github+json",
                }
                if github_token:
                    headers["Authorization"] = f"Bearer {github_token}"
                else:
                    # Fallback: usa anon key (funciona para repositorios publicos ou com permissao)
                    chave = env.get("SUPABASE_ANON_KEY") or ""
                    if chave:
                        headers["X-GitHub-Api-Version"] = "2022-11-28"
                
                import urllib.request
                base = "https://api.github.com"
                repo = env.get("GITHUB_REPOSITORY", "")
                url = f"{base}/repos/{repo}/dispatches" if repo else ""
                
                payload = json.dumps({
                    "event_type": workflow,
                    "client_payload": {"ref": ref}
                }).encode() if url else b""
                
                req = urllib.request.Request(
                    url,
                    data=payload,
                    headers={**headers, "Content-Type": "application/json"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=30) as r:
                    resposta = r.read().decode("utf-8")
                    self._json_response({
                        "status": "queued",
                        "message": "Workflow disparado na nuvem GitHub",
                        "raw": resposta[:200]
                    })
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)
            return

        # ============================================================
        # BANCO DE DADOS (local do servidor OU de um cliente)
        # ============================================================
        if api_path == "local/tables" and metodo == "GET":
            try:
                q = parse_qs(urlsplit(self.path).query)
                schema = q.get("schema", ["public"])[0]
                conn = _conn_de_query(urlsplit(self.path).query)
                tables = _get_local_tables(schema, dados=conn)
                self._json_response({
                    "schema": schema,
                    "tables": tables,
                    "origem": conn["host"] if conn else "local",
                })
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)
            return

        if api_path == "local/columns" and metodo == "GET":
            try:
                q = parse_qs(urlsplit(self.path).query)
                table = q.get("table", [None])[0]
                schema = q.get("schema", ["public"])[0]
                conn = _conn_de_query(urlsplit(self.path).query)
                if not table:
                    self._json_response({"erro": "Parametro 'table' obrigatorio"}, 400)
                    return
                cols = _get_table_columns(table, schema, dados=conn)
                self._json_response({"table": table, "schema": schema, "columns": cols})
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)
            return

        if api_path == "local/query" and metodo == "POST":
            sql = ""
            try:
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}
                sql = (params.get("sql") or "").strip()
                limit = int(params.get("limit", 1000) or 1000)
                read_only = params.get("read_only", True)
                conn = _dados_conexao(params.get("conn"))

                if not sql:
                    self._json_response({"erro": "Campo 'sql' obrigatorio"}, 400)
                    return

                # Trava de seguranca: por padrao so SELECT.
                if read_only and not sql.lstrip().upper().startswith("SELECT"):
                    self._json_response({"erro": "Apenas SELECT permitido (desmarque 'Somente leitura' para DML/DDL)"}, 400)
                    return

                result = _execute_local_sql(
                    sql, None, fetch=read_only, limit=limit, dados=conn
                )
                if isinstance(result, list):
                    self._json_response({
                        "sql": sql, "rows": result, "count": len(result),
                        "origem": conn["host"] if conn else "local",
                    })
                else:
                    self._json_response({
                        "sql": sql, "affected_rows": result.get("affected_rows"),
                        "origem": conn["host"] if conn else "local",
                    })
            except Exception as e:
                self._json_response({"erro": str(e), "sql": sql}, 500)
            return



        # --- Novo: Endpoints de Migration de Schema ---
        if api_path == "migrations/list" and metodo == "GET":
            # Lista migrations disponíveis na pasta tool/migrations/ e verifica quais
            # já foram aplicadas no banco local via tabela _schema_migrations
            import os
            import json
            base = Path(__file__).resolve().parent.parent / "tool" / "migrations"
            migrations = []
            if base.is_dir():
                for f in sorted(base.glob("*.sql")):
                    nome = f.name.replace(".sql", "")
                    # Verificar se já foi aplicada no banco local
                    try:
                        import psycopg2
                        dsn = _get_local_pg_dsn()
                        conn = psycopg2.connect(dsn, connect_timeout=8)
                        cur = conn.cursor()
                        cur.execute(
                            "SELECT versao FROM _schema_migrations WHERE versao = %s",
                            (nome,),
                        )
                        aplicada = cur.fetchone() is not None
                        conn.close()
                        migrations.append(
                            {
                                "versao": nome,
                                "arquivo": f.name,
                                "aplicada": aplicada,
                                "caminho": str(f),
                            }
                        )
                    except Exception as e:
                        migrations.append(
                            {
                                "versao": nome,
                                "arquivo": f.name,
                                "aplicada": False,
                                "erro": str(e)[:100],
                            }
                        )
            self._json_response({"migrations": migrations})

        if api_path == "migrations/run" and metodo == "POST":
            # Executa uma migration específica no banco local do servidor
            # ou de um cliente (via params de conexão)
            import json
            import psycopg2
            body = self._corpo_da_requisicao()
            params = json.loads(body.decode("utf-8")) if body else {}
            versao = params.get("versao", "")
            descricao = params.get("descricao", "Aplicado via portal")
            if not versao:
                self._json_response({"erro": "Informe a versão da migration"}, 400)
                return
            # Encontrar o arquivo SQL correspondente
            base = Path(__file__).resolve().parent.parent / "tool" / "migrations"
            arquivo = next(
                (f for f in base.glob("*.sql") if f.stem == versao), None
            )
            if not arquivo:
                self._json_response(
                    {"erro": "Migration não encontrada na pasta tool/migrations/"},
                    404,
                )
                return
            try:
                sql = arquivo.read_text(encoding="utf-8")
                # Executar no banco local (usando .env credentials)
                conn = _get_local_pg_conn()
                conn.autocommit = True
                with conn.cursor() as cur:
                    cur.execute(sql)
                    # Registrar na tabela de versão
                    with conn.cursor() as cur2:
                        cur2.execute(
                            "INSERT INTO _schema_migrations (versao, descricao) "
                            "VALUES (%s, %s) ON CONFLICT (versao) DO NOTHING",
                            (versao, descricao),
                        )
                conn.close()
                self._json_response(
                    {"sucesso": True, "aplicada": versao, "descricao": descricao}
                )
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)

        if api_path == "local/test" and metodo == "POST":
            try:
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}
                conn = _dados_conexao(params.get("conn") or params)
                linhas = _execute_local_sql(
                    "SELECT 1 AS ok, current_database() AS banco, current_user AS usuario, inet_server_addr()::text AS servidor",
                    None, fetch=True, dados=conn,
                )
                self._json_response({
                    "conectado": True,
                    "origem": conn["host"] if conn else "local",
                    "info": linhas[0] if linhas else {},
                })
            except Exception as e:
                self._json_response({"conectado": False, "erro": str(e)}, 200)
            return

        if api_path == "local/connections" and metodo == "GET":
            self._json_response({
                "conexoes": [_mascarar_conexao(c) for c in _ler_conexoes()]
            })
            return

        if api_path == "local/connections" and metodo == "POST":
            try:
                body = self._corpo_da_requisicao()
                params = json.loads(body.decode("utf-8")) if body else {}
                nome = (params.get("nome") or "").strip()
                if not nome:
                    self._json_response({"erro": "Informe um nome para a conexao"}, 400)
                    return
                dados = _dados_conexao(params) or {}
                lista = _ler_conexoes()
                # Se a senha veio mascarada/vazia e ja existe, mantem a antiga.
                antiga = next((c for c in lista if (c.get("nome") or "").lower() == nome.lower()), None)
                if antiga and (not params.get("senha") or params.get("senha") == "****"):
                    dados["senha"] = antiga.get("senha", "")
                registro = {
                    "nome": nome,
                    "host": dados.get("host"),
                    "porta": dados.get("porta"),
                    "banco": dados.get("banco"),
                    "usuario": dados.get("usuario"),
                    "senha": dados.get("senha", ""),
                }
                lista = [c for c in lista if (c.get("nome") or "").lower() != nome.lower()]
                lista.append(registro)
                lista.sort(key=lambda c: (c.get("nome") or "").lower())
                _salvar_conexoes(lista)
                self._json_response({"sucesso": True, "conexao": _mascarar_conexao(registro)})
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)
            return

        if api_path == "local/connections" and metodo == "DELETE":
            try:
                q = parse_qs(urlsplit(self.path).query)
                nome = (q.get("nome", [""])[0] or "").strip()
                if not nome:
                    self._json_response({"erro": "Parametro 'nome' obrigatorio"}, 400)
                    return
                lista = [c for c in _ler_conexoes() if (c.get("nome") or "").lower() != nome.lower()]
                _salvar_conexoes(lista)
                self._json_response({"sucesso": True, "removida": nome})
            except Exception as e:
                self._json_response({"erro": str(e)}, 500)
            return

        if api_path == "local/dsn" and metodo == "GET":
            try:
                dsn = _get_local_pg_dsn()
                import re
                safe_dsn = re.sub(r':([^:@]+)@', ':****@', dsn) if dsn else None
                self._json_response({"dsn": safe_dsn, "conectado": bool(dsn)})
            except Exception as e:
                self._json_response({"erro": str(e), "conectado": False}, 500)
            return

        if api_path == "tabelas" and metodo == "GET":
            # Lista todas as tabelas do schema public da NUBEM (via OpenAPI do
            # PostgREST com a chave de servico -- a anon key nao abre o /openapi).
            texto = ""
            status_up = None
            try:
                env2 = _ler_env_local()
                chave = (
                    env2.get("SUPABASE_SERVICE_ROLE_KEY")
                    or env2.get("SUPABASE_ANON_KEY")
                    or ""
                ).strip()
                status_up, dados = _proxy_get(
                    "/rest/v1/",
                    {
                        "apikey": chave,
                        "Authorization": "Bearer " + chave,
                        "Accept": "application/json",
                        "Host": "%s:%d" % (ServidorPortal.api_host, ServidorPortal.api_port),
                    },
                )
                texto = dados.decode("utf-8")
                doc = json.loads(texto)
                nomes = []
                for rota, info in (doc.get("paths") or {}).items():
                    partes = [p for p in rota.strip("/").split("/") if p]
                    if len(partes) != 1:
                        continue
                    topo = partes[0]
                    if topo.startswith(("auth", "storage", "realtime", "functions", "graphql", "rpc", "pg", "api")):
                        continue
                    nomes.append(topo)
                self._json_response({
                    "tabelas": sorted(set(nomes)),
                    "origem": "nuvem",
                    "total": len(set(nomes)),
                })
            except Exception as e:
                self._json_response({
                    "erro": str(e),
                    "tabelas": [],
                    "origem": "nuvem",
                }, 500)
            return

        self._erro(404, "Admin API endpoint nao encontrado: " + caminho)

    def _json_response(self, data: dict, status: int = 200) -> None:
        import json
        from decimal import Decimal
        from datetime import datetime, date

        class CustomEncoder(json.JSONEncoder):
            def default(self, obj):
                if isinstance(obj, Decimal):
                    return float(obj)
                if isinstance(obj, (datetime, date)):
                    return obj.isoformat()
                return super().default(obj)

        body = json.dumps(data, ensure_ascii=False, cls=CustomEncoder).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # -------------------------------------------------------------- estatico
    def _resolver_arquivo(self, caminho: str) -> Path | None:
        relativo = caminho.lstrip("/")
        alvo = (self.raiz / relativo).resolve()
        try:
            if os.path.commonpath([str(self.raiz.resolve()), str(alvo)]) != str(
                self.raiz.resolve()
            ):
                return None
        except ValueError:
            return None
        if alvo.is_file():
            return alvo
        return None

    def _estatico(self, caminho: str, com_corpo: bool) -> None:
        arquivo = self._resolver_arquivo(caminho)

        # Rota do SPA (ex.: /loja, /agenda/slug): devolve o index.html e deixa o
        # Flutter resolver a URL. Sem isso um link direto daria 404.
        if arquivo is None and not Path(caminho).suffix:
            arquivo = self.raiz / "index.html"

        if arquivo is None or not arquivo.is_file():
            self._erro(404, "Nao encontrado")
            return

        dados = arquivo.read_bytes()
        tipo = TIPOS_EXTRAS.get(arquivo.suffix.lower())
        if tipo is None:
            tipo = mimetypes.guess_type(arquivo.name)[0] or "application/octet-stream"

        dados, comprimido = _comprimir_arquivo(
            arquivo, dados, tipo, self._aceita_gzip()
        )

        self.send_response(200)
        self.send_header("Content-Type", tipo)
        if comprimido:
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Vary", "Accept-Encoding")
        self.send_header("Content-Length", str(len(dados)))
        if arquivo.name in SEM_CACHE:
            self.send_header(
                "Cache-Control", "no-cache, no-store, must-revalidate"
            )
        elif arquivo.suffix.lower() in {".js", ".json", ".wasm", ".html"}:
            # Arquivos do app mudam a cada publicacao. Com max-age=3600 o
            # navegador continuava executando o main.dart.js VELHO por ate 1h
            # depois de uma correcao (sintoma: edito, salvo, recarrego e volta).
            self.send_header("Cache-Control", "no-cache")
        else:
            self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if com_corpo:
            self.wfile.write(dados)

    # ---------------------------------------------------------------- erros
    def _erro(self, status: int, mensagem: str) -> None:
        dados = mensagem.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(dados)


def _console(mensagem: str) -> None:
    """print seguro: sob `pythonw` sys.stdout pode ser None."""
    try:
        if sys.stdout is not None:
            print(mensagem)
            sys.stdout.flush()
    except (AttributeError, OSError):
        pass


def main() -> int:
    base = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Portal + API na mesma origem")
    parser.add_argument("--porta", type=int, default=8090)
    parser.add_argument("--raiz", default=str(base / "build" / "web"))
    parser.add_argument("--api-host", default="127.0.0.1")
    parser.add_argument("--api-porta", type=int, default=8001)
    parser.add_argument("--log", default=str(base / "logs" / "portal_nuvem.log"))
    args = parser.parse_args()

    raiz = Path(args.raiz).resolve()
    if not (raiz / "index.html").is_file():
        _console("ERRO: nao encontrei index.html em %s" % raiz)
        _console("Rode 'flutter build web --release' antes de subir o portal.")
        return 1

    log_path = Path(args.log) if args.log else None
    if log_path is not None:
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError:
            log_path = None

    ServidorPortal.raiz = raiz
    ServidorPortal.api_host = args.api_host
    ServidorPortal.api_port = args.api_porta
    ServidorPortal.log_path = log_path

    servidor = ThreadingHTTPServer(("127.0.0.1", args.porta), ServidorPortal)
    servidor.daemon_threads = True
    _console(
        "Portal na porta %d | raiz=%s | api=http://%s:%d"
        % (args.porta, raiz, args.api_host, args.api_porta)
    )
    _console("Abra https://servidorsupabase.tail9b4943.ts.net (Funnel HTTPS).")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        servidor.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

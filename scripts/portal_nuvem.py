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
import mimetypes
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

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

    def _responder(self, metodo: str, com_corpo: bool) -> None:
        partes = urlsplit(self.path)
        caminho = partes.path or "/"
        try:
            if self._e_api(caminho):
                self._proxy(metodo, com_corpo)
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

"""Descoberta automatica de outros dispositivos Exodo na rede local.

A descoberta anuncia somente identidade e porta do servico PostgreSQL.
Credenciais, dados comerciais e conteudo do banco NUNCA sao transmitidos aqui.
"""
from __future__ import annotations

import json
import os
import socket
import threading
import time
import uuid
from pathlib import Path

PROTOCOLO = "exodo-sync-lan"
VERSAO_PROTOCOLO = 1
PORTA_DESCOBERTA = 45872
INTERVALO_ANUNCIO = 3.0
EXPIRACAO_PEER = 15.0
TAMANHO_MAXIMO_PACOTE = 2048


def carregar_ou_criar_device_id(caminho):
    """Retorna identidade persistente da instalacao, criando-a se necessario."""
    arquivo = Path(caminho)
    try:
        valor = json.loads(arquivo.read_text(encoding="utf-8"))
        device_id = str(valor.get("device_id", "")).strip()
        uuid.UUID(device_id)
        return device_id
    except (OSError, ValueError, TypeError, AttributeError):
        pass

    device_id = str(uuid.uuid4())
    arquivo.parent.mkdir(parents=True, exist_ok=True)
    temporario = arquivo.with_suffix(arquivo.suffix + ".tmp")
    temporario.write_text(
        json.dumps({"device_id": device_id}, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    os.replace(str(temporario), str(arquivo))
    return device_id


def criar_anuncio(device_id, porta_postgres=5432):
    """Pacote publico de descoberta; nao inclui nome do PC ou credenciais."""
    return json.dumps({
        "protocol": PROTOCOLO,
        "version": VERSAO_PROTOCOLO,
        "device_id": str(device_id),
        "postgres_port": int(porta_postgres),
    }, separators=(",", ":")).encode("utf-8")


def validar_anuncio(payload, ip_origem, meu_device_id):
    """Valida um anuncio e devolve os dados minimos de um par, ou None."""
    if not ip_origem or len(payload) > TAMANHO_MAXIMO_PACOTE:
        return None
    try:
        dado = json.loads(payload.decode("utf-8"))
        device_id = str(dado["device_id"])
        uuid.UUID(device_id)
        porta = int(dado["postgres_port"])
        if dado.get("protocol") != PROTOCOLO:
            return None
        if int(dado.get("version", 0)) != VERSAO_PROTOCOLO:
            return None
        if device_id == str(meu_device_id) or not 1 <= porta <= 65535:
            return None
        socket.inet_aton(ip_origem)
        return {"device_id": device_id, "host": ip_origem, "port": porta}
    except (ValueError, TypeError, KeyError, UnicodeError, OSError):
        return None


class DescobertaLan:
    """Anuncia este dispositivo e mantem a lista temporaria dos pares vistos."""

    def __init__(self, device_id, porta_postgres=5432,
                 porta_descoberta=PORTA_DESCOBERTA,
                 intervalo=INTERVALO_ANUNCIO, expiracao=EXPIRACAO_PEER):
        self.device_id = str(device_id)
        self.porta_postgres = int(porta_postgres)
        self.porta_descoberta = int(porta_descoberta)
        self.intervalo = float(intervalo)
        self.expiracao = float(expiracao)
        self._pares = {}
        self._lock = threading.Lock()
        self._parar = threading.Event()
        self._thread = None
        self._socket = None

    def iniciar(self):
        if self._thread and self._thread.is_alive():
            return
        self._parar.clear()
        self._thread = threading.Thread(
            target=self._executar, name="Exodo-LAN-Discovery", daemon=True
        )
        self._thread.start()

    def parar(self):
        self._parar.set()
        if self._socket:
            try:
                self._socket.close()
            except OSError:
                pass
        if self._thread:
            self._thread.join(timeout=2)

    def pares(self):
        agora = time.monotonic()
        with self._lock:
            expirados = [
                chave for chave, valor in self._pares.items()
                if agora - valor["visto_em"] > self.expiracao
            ]
            for chave in expirados:
                del self._pares[chave]
            return [
                {k: v for k, v in valor.items() if k != "visto_em"}
                for valor in self._pares.values()
            ]

    def _executar(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket = sock
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", self.porta_descoberta))
            sock.settimeout(0.5)
            anuncio = criar_anuncio(self.device_id, self.porta_postgres)
            proximo_anuncio = 0.0
            while not self._parar.is_set():
                agora = time.monotonic()
                if agora >= proximo_anuncio:
                    try:
                        sock.sendto(anuncio, ("255.255.255.255", self.porta_descoberta))
                    except OSError:
                        pass
                    proximo_anuncio = agora + self.intervalo
                try:
                    payload, endereco = sock.recvfrom(TAMANHO_MAXIMO_PACOTE)
                    par = validar_anuncio(payload, endereco[0], self.device_id)
                    if par:
                        par["visto_em"] = time.monotonic()
                        with self._lock:
                            self._pares[par["device_id"]] = par
                except socket.timeout:
                    continue
                except OSError:
                    if self._parar.is_set():
                        break
        finally:
            try:
                sock.close()
            except OSError:
                pass
            self._socket = None

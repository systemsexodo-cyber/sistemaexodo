#!/usr/bin/env python3
"""Valida o Supabase Realtime com um WebSocket em stdlib puro (sem deps).

Uso: python3 raw_ws_realtime.py <url> <anon_key>
Ex.: python3 raw_ws_realtime.py ws://IP_DO_CONTAINER:4000/socket/websocket?vsn=1.0.0 ANON
Fases: handshake 101 -> JOIN de canal broadcast -> eco do broadcast.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time

url = sys.argv[1]
anon = sys.argv[2]

# ws://host:port/path?query
assert url.startswith("ws://"), url
rest = url[5:]
hostport, _, path = rest.partition("/")
host, _, port = hostport.partition(":")
port = int(port or 80)
path = "/" + path

t0 = time.time()
def log(msg):
    print(f"[{time.time()-t0:6.2f}s] {msg}", flush=True)

def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("conexao fechada pelo servidor")
        buf += chunk
    return buf

def read_frame(sock):
    h = recv_exact(sock, 2)
    fin_op, mlen = h[0], h[1]
    opcode = fin_op & 0x0F
    masked = mlen & 0x80
    ln = mlen & 0x7F
    if ln == 126:
        ln = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif ln == 127:
        ln = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask = recv_exact(sock, 4) if masked else None
    data = recv_exact(sock, ln)
    if mask:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return opcode, data

def send_frame(sock, data: bytes, opcode=0x1):
    key = os.urandom(4)
    masked = bytes(b ^ key[i % 4] for i, b in enumerate(data))
    header = bytes([0x80 | opcode])
    n = len(masked)
    if n < 126:
        header += bytes([0x80 | n])
    elif n < 65536:
        header += bytes([0x80 | 126]) + struct.pack("!H", n)
    else:
        header += bytes([0x80 | 127]) + struct.pack("!Q", n)
    sock.sendall(header + key + masked)

# 1) handshake HTTP
key = base64.b64encode(os.urandom(16)).decode()
req = (
    f"GET {path}?{url.split('?',1)[1] if '?' in url else ''} HTTP/1.1\r\n"
    f"Host: {os.environ.get('WS_HOST') or f'{host}:{port}'}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    f"apikey: {anon}\r\n"
    "User-Agent: validacao-raw\r\n"
    "\r\n"
)
s = socket.create_connection((host, port), timeout=8)
s.settimeout(10)
s.sendall(req.encode())
resp = b""
while b"\r\n\r\n" not in resp:
    resp += s.recv(4096)
head = resp.split(b"\r\n\r\n", 1)[0].decode(errors="replace")
status = head.split("\r\n", 1)[0]
log(f"handshake: {status}")
accept_ok = " 101" in status
if not accept_ok:
    print(head[:800])
    sys.exit(1)
expected = base64.b64encode(
    hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
).decode()
log(f"Sec-WebSocket-Accept confere: {expected in head}")

# 2) JOIN do canal broadcast
canal = "realtime:validacao-raw"
join = ["1", "1", canal, "phx_join",
        {"config": {"broadcast": {"self": True, "private": False}}, "access_token": anon}]
send_frame(s, json.dumps(join).encode())
log(f"-> phx_join {canal}")

# 3) ler frames por ~8s, ecoando broadcast; envia heartbeat de vez em quando
hb = 0
deadline = time.time() + 8
while time.time() < deadline:
    try:
        s.settimeout(1.5)
        opcode, data = read_frame(s)
    except (socket.timeout, TimeoutError):
        hb += 1
        send_frame(s, json.dumps(["", str(hb + 10), "phoenix", "heartbeat", {}]).encode())
        log("-> heartbeat")
        continue
    if opcode == 0x9:  # ping do servidor
        send_frame(s, data, opcode=0xA)
        log("<- ping do servidor (respondido pong)")
        continue
    if opcode == 0x8:
        code = struct.unpack("!H", data[:2])[0] if len(data) >= 2 else None
        log(f"<- close frame code={code} motivo={data[2:].decode(errors='replace')!r}")
        break
    txt = data.decode(errors="replace")
    log(f"<- frame: {txt[:400]}")
    try:
        m = json.loads(txt)
    except Exception:
        continue
    if m[3] == "phx_reply" and m[4].get("status") == "ok" and m[2] == canal:
        log("JOIN confirmado pelo servidor")
        send_frame(s, json.dumps(["1", "2", canal, "broadcast",
                                  {"type": "broadcast", "event": "ping",
                                   "payload": {"ts": int(time.time())}}]).encode())
        log("-> broadcast ping")
    if m[3] == "broadcast":
        log("BROADCAST ECOU DE VOLTA — realtime funcional por este caminho")
        s.close()
        sys.exit(0)

log("NAO RECEBEU RESPOSTA NENHUMA (join sem reply)")
s.close()
sys.exit(2)

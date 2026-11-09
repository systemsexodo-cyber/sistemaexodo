#!/usr/bin/env python3
"""Matriz de protocolo do Supabase Realtime local: vsn 1.0.0/2.0.0 x array/object.
Uso: ANON=<key> python3 realtime_matrix.py  (roda NA VM; acha o IP do container sozinho.)
"""
import base64
import json
import os
import socket
import struct
import time

IP = os.popen(
    "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' realtime-dev.supabase-realtime"
).read().strip()
ANON = os.environ["ANON"]


def frame(op, data=b""):
    k = os.urandom(4)
    m = bytes(b ^ k[i % 4] for i, b in enumerate(data))
    h = bytes([0x80 | op])
    n = len(m)
    if n < 126:
        h += bytes([0x80 | n])
    else:
        h += bytes([0x80, 126]) + struct.pack("!H", n)
    return h + k + m


def readframes(s, seconds):
    out = []
    end = time.time() + seconds
    while time.time() < end:
        try:
            s.settimeout(max(0.2, end - time.time()))
            h = s.recv(2)
            if not h:
                out.append(("closed", b""))
                break
            op = h[0] & 0x0F
            ln = h[1] & 0x7F
            if ln == 126:
                ln = struct.unpack("!H", s.recv(2))[0]
            elif ln == 127:
                ln = struct.unpack("!Q", s.recv(8))[0]
            if h[1] & 0x80:
                s.recv(4)
            data = b""
            while len(data) < ln:
                chunk = s.recv(ln - len(data))
                if not chunk:
                    break
                data += chunk
            out.append((op, data))
        except Exception:
            break
    return out


def tentativa(vsn, formato, topico, event_extra=None):
    s = socket.create_connection((IP, 4000), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((
        f"GET /socket/websocket?vsn={vsn}&apikey={ANON} HTTP/1.1\r\n"
        "Host: realtime-dev.supabase-realtime\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    ).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)
    status = buf.split(b"\r\n")[0].decode()
    cfg = {"config": {"broadcast": {"self": True, "private": False}}, "access_token": ANON}
    if formato == "array":
        join = ["1", "1", topico, "phx_join", cfg]
        hb = ["", "2", "phoenix", "heartbeat", {}]
    else:
        join = {"join_ref": "1", "ref": "1", "topic": topico, "event": "phx_join", "payload": cfg}
        hb = {"join_ref": "", "ref": "2", "topic": "phoenix", "event": "heartbeat", "payload": {}}
    s.sendall(frame(1, json.dumps(join).encode()))
    time.sleep(0.4)
    s.sendall(frame(1, json.dumps(hb).encode()))
    frames = readframes(s, 2.5)
    resumo = [(op, d[:180].decode(errors="replace")) for op, d in frames]
    print(f"vsn={vsn} fmt={formato}: {status} | frames={resumo or 'NENHUM'}", flush=True)
    s.close()


for vsn in ("1.0.0", "2.0.0"):
    for fmt in ("array", "object"):
        tentativa(vsn, fmt, "realtime:matriz")

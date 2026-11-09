# -*- coding: utf-8 -*-
"""
Repara a divergencia entre a configuracao LOCAL e a NUVEM nas listas-vivas
(perfis tributarios, perfis de preco, departamentos, estoques).

Regra identica a do app (lib/utils/perfis_tributarios_merge.dart):
  1. lista vazia de um lado -> vence o outro;
  2. carimbo (<lista>_atualizado_em) mais recente vence;
  3. sem carimbo nos dois lados -> vence a empresa com updated_at maior.

Uso:
    python tool/reparar_perfis_cloud.py            (mostra o que mudaria)
    python tool/reparar_perfis_cloud.py --aplicar  (grava na nuvem)
"""
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

import psycopg2

LOCAL_DSN = "host=localhost port=5432 dbname=exodo_db user=exodo_user password=ex@#$"
CLOUD_URL = "http://127.0.0.1:8001"
CLOUD_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAog"
    "ICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3"
    "OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"
)

LISTAS = [
    ("perfis_tributarios", "perfis_tributarios_atualizado_em"),
    ("perfis_preco", "perfis_preco_atualizado_em"),
    ("departamentos", "departamentos_atualizado_em"),
    ("estoques", "estoques_atualizado_em"),
]


def parse_dt(valor):
    if not valor:
        return None
    try:
        texto = str(valor).replace("Z", "+00:00")
        dt = datetime.fromisoformat(texto)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None


def carimbo(config, chave):
    return parse_dt(config.get(chave))


def vencedora(chave, chave_carimbo, cfg_local, cfg_remota, upd_local, upd_remota):
    local = cfg_local.get(chave)
    remota = cfg_remota.get(chave)
    lista_local = local if isinstance(local, list) and local else None
    lista_remota = remota if isinstance(remota, list) and remota else None
    if lista_local is None and lista_remota is None:
        return None
    if lista_local is None:
        return lista_remota, chave_carimbo
    if lista_remota is None:
        return lista_local, chave_carimbo
    cl = carimbo(cfg_local, chave_carimbo)
    cr = carimbo(cfg_remota, chave_carimbo)
    if cl and cr:
        return (lista_remota if cr > cl else lista_local), chave_carimbo
    if cr:
        return lista_remota, chave_carimbo
    if cl:
        return lista_local, chave_carimbo
    return (lista_remota if upd_remota > upd_local else lista_local), chave_carimbo


def req(method, path, body=None):
    data = None
    headers = {
        "apikey": CLOUD_KEY,
        "Authorization": "Bearer " + CLOUD_KEY,
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    r = urllib.request.Request(CLOUD_URL + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=20) as resp:
        bruto = resp.read()
        return resp.status, (json.loads(bruto) if bruto else None)


def resumo(lista):
    if not isinstance(lista, list):
        return "?"
    partes = []
    for p in lista:
        if isinstance(p, dict):
            partes.append(
                "%s[ibs=%s cbs=%s trib=%s]" % (
                    p.get("nome"),
                    p.get("aliquota_ibs"),
                    p.get("aliquota_cbs"),
                    p.get("c_class_trib"),
                )
            )
    return "; ".join(partes)


def main():
    aplicar = "--aplicar" in sys.argv
    conn = psycopg2.connect(LOCAL_DSN)
    cur = conn.cursor()
    cur.execute("select id, configuracoes, updated_at from empresas")
    locais = {row[0]: (row[1] or {}, row[2]) for row in cur.fetchall()}
    cur.close()
    conn.close()

    _, remotas = req("GET", "/rest/v1/empresas?select=id,configuracoes,updated_at")
    for remota in remotas or []:
        empresa_id = remota["id"]
        cfg_remota = remota.get("configuracoes") or {}
        upd_remota = parse_dt(remota.get("updated_at")) or datetime.now(timezone.utc)
        if empresa_id not in locais:
            continue
        cfg_local, upd_local_raw = locais[empresa_id]
        upd_local = parse_dt(upd_local_raw) or datetime.now(timezone.utc)

        # Parte da copia da NUVEM e substitui SOMENTE as listas cujo carimbo
        # local e mais novo. Assim nenhuma chave que exista so na nuvem
        # (pagamentos, ecommerce, certificado...) e perdida.
        merged = dict(cfg_remota)
        mudou = False
        for chave, chave_carimbo in LISTAS:
            escolha = vencedora(chave, chave_carimbo, cfg_local, cfg_remota, upd_local, upd_remota)
            if escolha is None:
                continue
            lista, _ = escolha
            atual = cfg_remota.get(chave)
            if lista is not atual and json.dumps(lista, sort_keys=True) == json.dumps(atual, sort_keys=True):
                continue
            if json.dumps(lista, sort_keys=True) == json.dumps(atual, sort_keys=True):
                continue
            merged[chave] = lista
            carimbo_escolhido = carimbo(
                cfg_local if lista is cfg_local.get(chave) else cfg_remota, chave_carimbo
            )
            if carimbo_escolhido is not None:
                merged[chave_carimbo] = carimbo_escolhido.isoformat().replace("+00:00", "Z")
            mudou = True
            print("=" * 78)
            print("EMPRESA %s / LISTA %s" % (empresa_id, chave))
            print("  carimbo local : %s" % carimbo(cfg_local, chave_carimbo))
            print("  carimbo nuvem : %s" % carimbo(cfg_remota, chave_carimbo))
            print("  vencedor      : %s" % ("LOCAL" if lista is cfg_local.get(chave) else "NUVEM"))
            print("  nuvem hoje    : %s" % resumo(atual))
            print("  ficara com    : %s" % resumo(lista))

        if not mudou:
            continue
        if aplicar:
            # Backup da copia atual da nuvem antes de qualquer gravacao.
            pasta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backups")
            os.makedirs(pasta, exist_ok=True)
            marca = datetime.now().strftime("%Y%m%d_%H%M%S")
            caminho = os.path.join(pasta, "config_empresa_%s_%s.json" % (empresa_id, marca))
            with open(caminho, "w", encoding="utf-8") as f:
                json.dump(cfg_remota, f, ensure_ascii=False, indent=2)
            print("  backup da nuvem: %s" % caminho)
            status, _ = req(
                "PATCH",
                "/rest/v1/empresas?id=eq." + empresa_id,
                {"configuracoes": merged},
            )
            print("  >>> PATCH aplicado (HTTP %s)" % status)
        else:
            print("  >>> (dry-run) use --aplicar para gravar")


if __name__ == "__main__":
    main()

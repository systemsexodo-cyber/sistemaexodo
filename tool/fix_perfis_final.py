# -*- coding: utf-8 -*-
import json
import psycopg2
import urllib.request
from datetime import datetime, timezone

LOCAL_DSN = "host=localhost port=5432 dbname=exodo_db user=exodo_user password=ex@#$"
CLOUD_URL = "http://127.0.0.1:8001"
CLOUD_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"
EMPRESA_ID = "bd45d75b-fee4-4ac2-8975-0f36f61d01bf"

PERFIS = [
    {"id": "padrao_tributado_simples", "nome": "Tributado (Simples Nacional)", "cfop": "5102", "csosn": "102", "icms_cst": "", "pis_cst": "99", "cofins_cst": "000", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": True},
    {"id": "padrao_nao_tributado_simples", "nome": "Nao Tributado (Simples Nacional)", "cfop": "5102", "csosn": "400", "icms_cst": "", "pis_cst": "99", "cofins_cst": "000", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": False},
    {"id": "padrao_substituicao_simples", "nome": "Substituicao Tributaria (Simples Nacional)", "cfop": "5405", "csosn": "500", "icms_cst": "", "pis_cst": "49", "cofins_cst": "49", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": False},
    {"id": "padrao_tributado_normal", "nome": "Tributado (Regime Normal)", "cfop": "5102", "csosn": None, "icms_cst": "00", "pis_cst": None, "cofins_cst": None, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": True},
    {"id": "padrao_nao_tributado_normal", "nome": "Nao Tributado (Regime Normal)", "cfop": "5102", "csosn": None, "icms_cst": "41", "pis_cst": None, "cofins_cst": None, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": False},
    {"id": "padrao_substituicao_normal", "nome": "Substituicao Tributaria (Regime Normal)", "cfop": "5405", "csosn": None, "icms_cst": "60", "pis_cst": None, "cofins_cst": None, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": False},
]

def main():
    # Update local
    conn = psycopg2.connect(LOCAL_DSN)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            carimbo = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            # For jsonb_set, the value must be valid JSON. String needs to be JSON-quoted.
            carimbo_json = json.dumps(carimbo)  # adds quotes: "2026-11-06T03:22:00.000Z"
            cur.execute(
                "UPDATE empresas SET configuracoes = jsonb_set(jsonb_set(configuracoes, '{perfis_tributarios}', %s::jsonb, true), '{perfis_tributarios_atualizado_em}', %s::jsonb, true), updated_at = NOW() WHERE id = %s",
                (json.dumps(PERFIS, ensure_ascii=False), carimbo_json, EMPRESA_ID)
            )
            print("Local updated, carimbo:", carimbo)
        conn.commit()
        print("Local committed!")
    finally:
        conn.close()

    # Verify local
    conn = psycopg2.connect(LOCAL_DSN)
    cur = conn.cursor()
    cur.execute("SELECT configuracoes->>'perfis_tributarios_atualizado_em', jsonb_array_length(configuracoes->'perfis_tributarios') FROM empresas WHERE id=%s", (EMPRESA_ID,))
    row = cur.fetchone()
    print("Local verify - carimbo:", row[0], "qtd:", row[1])
    cur.close()
    conn.close()

    # Push to cloud
    conn = psycopg2.connect(LOCAL_DSN)
    cur = conn.cursor()
    cur.execute("SELECT configuracoes FROM empresas WHERE id=%s", (EMPRESA_ID,))
    row = cur.fetchone()
    cfg_local = row[0] or {}
    cur.close()
    conn.close()

    headers = {
        "apikey": CLOUD_KEY,
        "Authorization": "Bearer " + CLOUD_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }
    body = json.dumps({"configuracoes": cfg_local}, ensure_ascii=False).encode("utf-8")
    r = urllib.request.Request(CLOUD_URL + "/rest/v1/empresas?id=eq." + EMPRESA_ID, data=body, headers=headers, method="PATCH")
    with urllib.request.urlopen(r, timeout=30) as resp:
        print("Cloud PATCH status:", resp.status)

    # Verify cloud
    r = urllib.request.Request(CLOUD_URL + "/rest/v1/empresas?select=updated_at,configuracoes&id=eq." + EMPRESA_ID, headers={"apikey": CLOUD_KEY, "Authorization": "Bearer " + CLOUD_KEY})
    with urllib.request.urlopen(r, timeout=30) as resp:
        data = json.loads(resp.read())[0]
        cfg_cloud = data.get("configuracoes") or {}
        print("Cloud verify - carimbo:", cfg_cloud.get("perfis_tributarios_atualizado_em"), "qtd:", len(cfg_cloud.get("perfis_tributarios", [])))
        for p in cfg_cloud.get("perfis_tributarios", []):
            print("  ", p.get("nome"), "padrao=", p.get("is_default"))

if __name__ == "__main__":
    main()
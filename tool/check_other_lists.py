# -*- coding: utf-8 -*-
import json
import urllib.request

CLOUD_URL = "http://127.0.0.1:8001"
CLOUD_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"

headers = {"apikey": CLOUD_KEY, "Authorization": "Bearer " + CLOUD_KEY}
r = urllib.request.Request(CLOUD_URL + "/rest/v1/empresas?select=id,razao_social,configuracoes", headers=headers)
with urllib.request.urlopen(r, timeout=30) as resp:
    data = json.loads(resp.read())
    for e in data:
        cfg = e.get("configuracoes") or {}
        print("%s | %s" % (e["id"], e["razao_social"]))
        print("  perfis_preco carimbo: %s, qtd: %d" % (cfg.get("perfis_preco_atualizado_em"), len(cfg.get("perfis_preco", []))))
        print("  departamentos carimbo: %s, qtd: %d" % (cfg.get("departamentos_atualizado_em"), len(cfg.get("departamentos", []))))
        print("  estoques carimbo: %s, qtd: %d" % (cfg.get("estoques_atualizado_em"), len(cfg.get("estoques", []))))
        # Show details
        for p in cfg.get("perfis_preco", []):
            print("    preco: %s (padrao=%s)" % (p.get("nome"), p.get("is_default")))
        for d in cfg.get("departamentos", []):
            print("    dept: %s" % d.get("nome"))
        for s in cfg.get("estoques", []):
            print("    estoque: %s (principal=%s)" % (s.get("nome"), s.get("principal")))
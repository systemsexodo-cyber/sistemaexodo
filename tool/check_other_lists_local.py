# -*- coding: utf-8 -*-
import json
import psycopg2

LOCAL_DSN = "host=localhost port=5432 dbname=exodo_db user=exodo_user password=ex@#$"

conn = psycopg2.connect(LOCAL_DSN)
cur = conn.cursor()
cur.execute("select id, razao_social, configuracoes from empresas")
rows = cur.fetchall()
for row in rows:
    cfg = row[2] or {}
    print("%s | %s" % (row[0], row[1]))
    print("  perfis_preco carimbo: %s, qtd: %d" % (cfg.get("perfis_preco_atualizado_em"), len(cfg.get("perfis_preco", []))))
    print("  departamentos carimbo: %s, qtd: %d" % (cfg.get("departamentos_atualizado_em"), len(cfg.get("departamentos", []))))
    print("  estoques carimbo: %s, qtd: %d" % (cfg.get("estoques_atualizado_em"), len(cfg.get("estoques", []))))
    for p in cfg.get("perfis_preco", []):
        print("    preco: %s (padrao=%s)" % (p.get("nome"), p.get("is_default")))
    for d in cfg.get("departamentos", []):
        print("    dept: %s" % d.get("nome"))
    for s in cfg.get("estoques", []):
        print("    estoque: %s (principal=%s)" % (s.get("nome"), s.get("principal")))
cur.close()
conn.close()
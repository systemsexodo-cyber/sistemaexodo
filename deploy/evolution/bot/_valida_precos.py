"""Valida se o preco que o bot responde e o preco real do cadastro.

Roda dentro do container do bot: le a tabela `produtos` e compara, item por item,
com o que /chat devolve. Uso: python _valida_precos.py
"""
import json
import os
import re
import urllib.request

import pg8000.native

import bot

TOKEN = os.getenv("BOT_ADMIN_TOKEN", "")
BASE = "http://127.0.0.1:8096"


def produtos():
    partes = bot._dsn_partes(bot.CATALOGO_DSN)
    conn = pg8000.native.Connection(
        user=partes["user"],
        password=partes["password"],
        host=partes["host"],
        port=partes["port"],
        database=partes["database"],
        timeout=10,
    )
    try:
        sql = (
            "SELECT nome, preco, preco_promocional, tem_promocao, promocao_inicio, "
            "promocao_fim, estoque FROM produtos WHERE ativo IS NOT FALSE "
            "AND coalesce(nome,'') <> ''"
        )
        params = {}
        if bot.CATALOGO_EMPRESA:
            sql += " AND empresa_id = :e"
            params["e"] = bot.CATALOGO_EMPRESA
        linhas = conn.run(sql, **params)
        colunas = [c["name"] for c in (conn.columns or [])]
    finally:
        conn.close()
    base = {}
    for linha in linhas:
        d = dict(zip(colunas, linha))
        nome = str(d.get("nome") or "").strip()
        try:
            preco = float(d.get("preco") or 0)
        except (TypeError, ValueError):
            preco = 0.0
        promo = None
        if d.get("tem_promocao"):
            try:
                promo = float(d.get("preco_promocional") or 0) or None
            except (TypeError, ValueError):
                promo = None
        if not bot._promo_vale(promo, preco, d.get("promocao_inicio"), d.get("promocao_fim")):
            promo = None
        esperado = promo if promo and 0 < promo < preco else preco
        base[bot._norm(nome)] = {"nome": nome, "esperado": round(esperado, 2)}
    return base


def pergunta(texto, telefone=""):
    payload = {"text": texto}
    if telefone:
        payload["telefone"] = telefone
    req = urllib.request.Request(
        BASE + "/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "x-bot-token": TOKEN},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def confere(texto, base):
    """Devolve (ok, detalhes) comparando cada 'Nome por R$ X' com o banco."""
    dados = pergunta(texto)
    resposta = dados.get("reply") or ""
    origem = dados.get("source") or "?"
    if not resposta:
        return None, f"[{origem}] sem resposta", resposta
    problemas = []
    conferidos = 0
    # A resposta lista um item por linha ("• Nome — R$ 8,98"); o formato antigo
    # ("Nome por R$ 8,98; ...") continua aceito para nao quebrar em versao antiga.
    for trecho in re.split(r";|\.\s|\n", resposta):
        m = re.search(r"(?i)(?:por|—|–|-)\s*(R\$\s*[\d.,]+)", trecho)
        if not m:
            continue
        valor = bot._valores(m.group(1))
        antes = trecho[: m.start()]
        nome = re.sub(r"(?i)^[\W_]*(temos\s*:?|•)?[\W_]*", "", antes).strip(" :;-")
        cadastro = base.get(bot._norm(nome))
        if not cadastro:
            continue  # nao achei o item no cadastro por nome literal: ignora
        conferidos += 1
        if not valor or round(list(valor)[0], 2) != cadastro["esperado"]:
            problemas.append(
                f"{cadastro['nome']}: bot disse {m.group(1)} / banco {cadastro['esperado']:.2f}"
            )
    # Preco solto na resposta sem item correspondente (ex.: IA inventando valor).
    valores_resposta = bot._valores(resposta)
    if valores_resposta and not conferidos:
        problemas.append(f"resposta com valor sem item do banco: {resposta[:90]}")
    return (not problemas), f"{origem}: {problemas or f'{conferidos} item(ns) conferido(s)'}", resposta


CASOS = [
    "quanto custa racao golden?",
    "tem areia pipicat?",
    "quanto custa antipulgas para gato?",
    "preco do shampoo para cachorro",
    "quanto custa coleira para gato?",
    "tem petisco para cao?",
    "quanto custa vermifugo para gato?",
    "racao para gato castrado",
    "quanto custa racao para peixe?",
    "tem brinquedo para cachorro?",
    "quanto custa banho e tosa?",
    "quanto custa o taxi dog?",
    "quantos anos voces tem?",
]

if __name__ == "__main__":
    base = produtos()
    print(f"cadastro: {len(base)} produto(s)")
    falhas = 0
    for caso in CASOS:
        ok, detalhe, resposta = confere(caso, base)
        marca = "OK " if ok else ("-- " if ok is None else "FALHA")
        if ok is False:
            falhas += 1
        print(f"{marca} {caso!r:38} -> {detalhe}")
        print(f"      {resposta[:160]}")
    print(f"\nfalhas: {falhas}")

#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Envia para o Supabase Storage os XMLs de nota que estao no disco, para o
contador conseguir baixa-los pelo Portal do Contador.

Os XMLs ficam em:   C:\\ExodoNFCe\\<CNPJ>\\<AAAA-MM>\\<CHAVE>-nfe.xml
E vao para:         bucket 'xmls'  ->  xmls/<empresa_id>/<CHAVE>.xml

ANTES DE USAR:
  1. Rode CRIAR_BUCKET_XMLS_SUPABASE.sql no SQL Editor do Supabase
  2. Tenha o .env na raiz com SUPABASE_URL e SUPABASE_ANON_KEY

COMO USAR:
  # Simular sem enviar nada (mostra o que seria feito)
  .venv\\Scripts\\python.exe enviar_xmls_storage.py --simular

  # Enviar tudo que ainda nao esta na nuvem
  .venv\\Scripts\\python.exe enviar_xmls_storage.py

  # Reenviar (sobrescrever) tudo
  .venv\\Scripts\\python.exe enviar_xmls_storage.py --sobrescrever

  # Enviar apenas de um CNPJ / de outra pasta
  .venv\\Scripts\\python.exe enviar_xmls_storage.py --cnpj 04829400000165
  .venv\\Scripts\\python.exe enviar_xmls_storage.py --pasta "D:\\Backup\\XMLs"
"""

import argparse
import json
import os
import re
import sys

import requests

BUCKET = "xmls"
PASTA_PADRAO = r"C:\ExodoNFCe"
SO_CNPJ = re.compile(r"[^0-9]")


def carregar_env():
    env_vars = {}
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.exists(caminho):
        with open(caminho, "r", encoding="utf-8") as arquivo:
            for linha in arquivo:
                linha = linha.strip()
                if not linha or linha.startswith("#") or "=" not in linha:
                    continue
                chave, valor = linha.split("=", 1)
                env_vars[chave.strip()] = valor.strip().strip('"').strip("'")

    url = env_vars.get("SUPABASE_URL")
    key = env_vars.get("SUPABASE_ANON_KEY")
    if not url or not key:
        print("[ERRO] Defina SUPABASE_URL e SUPABASE_ANON_KEY no .env da raiz do projeto.")
        sys.exit(1)
    return url.rstrip("/"), key


def headers(key):
    return {"apikey": key, "Authorization": f"Bearer {key}"}


def somente_digitos(valor):
    return SO_CNPJ.sub("", valor or "")


def carregar_empresas(url, key):
    """Retorna {'<cnpj somente digitos>': '<empresa_id>'}."""
    resposta = requests.get(
        f"{url}/rest/v1/empresas?select=id,cnpj", headers=headers(key), timeout=30
    )
    if resposta.status_code != 200:
        print(f"[ERRO] Falha ao ler as empresas: {resposta.status_code} - {resposta.text}")
        sys.exit(1)

    mapa = {}
    for empresa in resposta.json():
        cnpj = somente_digitos(empresa.get("cnpj"))
        if cnpj and empresa.get("id"):
            mapa[cnpj] = str(empresa["id"])
    return mapa


def chave_do_conteudo(caminho):
    """Le a chave de acesso de dentro do XML (campo chNFe / chNFCe)."""
    try:
        with open(caminho, "r", encoding="utf-8", errors="ignore") as arquivo:
            conteudo = arquivo.read(12000)
        achado = re.search(r"<ch(NFe|NFCe)>\s*(\d{44})\s*</ch", conteudo)
        if achado:
            return achado.group(2)
    except OSError:
        pass
    return None


def chave_do_nome(nome_arquivo):
    achado = re.search(r"(\d{44})", nome_arquivo)
    return achado.group(1) if achado else None


def cnpj_da_chave(chave):
    """A chave de acesso guarda o CNPJ do emitente nas posicoes 7 a 20."""
    if chave and len(chave) == 44:
        return chave[6:20]
    return None


def resolver_cnpj(partes, chave, empresas):
    """Descobre de qual empresa e o XML.

    A pasta (<CNPJ>\<AAAA-MM>\...) e a fonte mais confiavel para as notas DE
    ENTRADA (o CNPJ da chave seria o do fornecedor). Quando a pasta nao tem o
    CNPJ - caso das copias em 'Pacotes\...' criadas para o contador - usamos o
    CNPJ contido na propria chave de acesso.
    """
    cnpj_pasta = somente_digitos(partes[0]) if len(partes) > 1 else ""
    if len(cnpj_pasta) == 14 and cnpj_pasta in empresas:
        return cnpj_pasta

    cnpj_da_nota = cnpj_da_chave(chave)
    if cnpj_da_nota and cnpj_da_nota in empresas:
        return cnpj_da_nota

    return cnpj_pasta or cnpj_da_nota or ""


def chaves_ja_na_nuvem(url, key, empresa_id):
    resposta = requests.post(
        f"{url}/storage/v1/object/list/{BUCKET}",
        json={"prefix": f"{empresa_id}/", "limit": 1000},
        headers={**headers(key), "Content-Type": "application/json"},
        timeout=60,
    )
    if resposta.status_code != 200:
        return set()
    try:
        return {item["name"] for item in resposta.json()}
    except (ValueError, KeyError, TypeError):
        return set()


def enviar(url, key, empresa_id, chave, conteudo):
    resposta = requests.post(
        f"{url}/storage/v1/object/{BUCKET}/{empresa_id}/{chave}.xml",
        data=conteudo.encode("utf-8"),
        headers={
            **headers(key),
            "Content-Type": "application/xml",
            "x-upsert": "true",
        },
        timeout=120,
    )
    return resposta.status_code in (200, 201), resposta


def main():
    parser = argparse.ArgumentParser(description="Envia os XMLs de nota para o Supabase Storage.")
    parser.add_argument("--pasta", default=PASTA_PADRAO, help=f"Pasta raiz (padrao: {PASTA_PADRAO})")
    parser.add_argument("--cnpj", help="Enviar apenas de um CNPJ")
    parser.add_argument("--simular", action="store_true", help="Mostra o que seria feito, sem enviar")
    parser.add_argument("--sobrescrever", action="store_true", help="Reenvia mesmo se ja existir na nuvem")
    args = parser.parse_args()

    url, key = carregar_env()

    if not os.path.isdir(args.pasta):
        print(f"[ERRO] Pasta nao encontrada: {args.pasta}")
        sys.exit(1)

    empresas = carregar_empresas(url, key)
    print(f"[INFO] {len(empresas)} empresa(s) cadastrada(s) na nuvem.")

    cnpj_filtro = somente_digitos(args.cnpj) if args.cnpj else None
    enviados = pulados = ignorados = erros = 0
    ja_na_nuvem = {}

    for raiz, _, arquivos in os.walk(args.pasta):
        for nome in arquivos:
            if not nome.lower().endswith(".xml"):
                continue

            caminho = os.path.join(raiz, nome)
            relativo = os.path.relpath(caminho, args.pasta)
            partes = relativo.split(os.sep)

            # Chave de acesso: primeiro pelo nome do arquivo, senao pelo conteudo
            chave = chave_do_nome(nome) or chave_do_conteudo(caminho)
            if not chave:
                print(f"  [IGNORADO] {relativo} -> nao foi possivel achar a chave de acesso")
                ignorados += 1
                continue

            cnpj_arquivo = resolver_cnpj(partes, chave, empresas)
            if cnpj_filtro and cnpj_arquivo != cnpj_filtro:
                continue

            empresa_id = empresas.get(cnpj_arquivo)
            if not empresa_id:
                print(f"  [IGNORADO] {relativo} -> CNPJ {cnpj_arquivo or '?'} nao esta em empresas")
                ignorados += 1
                continue

            if empresa_id not in ja_na_nuvem:
                ja_na_nuvem[empresa_id] = chaves_ja_na_nuvem(url, key, empresa_id)

            if not args.sobrescrever and f"{chave}.xml" in ja_na_nuvem[empresa_id]:
                pulados += 1
                continue

            if args.simular:
                print(f"  [SIMULAR] {relativo} -> xmls/{empresa_id}/{chave}.xml")
                enviados += 1
                continue

            try:
                with open(caminho, "r", encoding="utf-8", errors="ignore") as arquivo:
                    conteudo = arquivo.read()
            except OSError as erro:
                print(f"  [ERRO] {relativo}: {erro}")
                erros += 1
                continue

            ok, resposta = enviar(url, key, empresa_id, chave, conteudo)
            if ok:
                enviados += 1
                print(f"  [OK] {chave}.xml ({len(conteudo)} bytes)")
            else:
                erros += 1
                print(f"  [ERRO] {chave}.xml: {resposta.status_code} - {resposta.text[:200]}")

    print()
    print("=" * 60)
    print(f"  Enviados:  {enviados}")
    print(f"  Ja existiam (pulados): {pulados}")
    print(f"  Ignorados: {ignorados}")
    print(f"  Erros:     {erros}")
    print("=" * 60)
    if args.simular:
        print("  MODO SIMULACAO: nada foi enviado de verdade.")


if __name__ == "__main__":
    main()

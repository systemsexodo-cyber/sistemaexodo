#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Cadastra (ou atualiza) o acesso do CONTADOR no Portal do Contador.

O contador entra no portal com CNPJ + senha e baixa os XMLs das notas da
empresa (NFC-e emitidas, NF-e emitidas e NF-e de entrada), separados por tipo.

ANTES DE USAR:
  1. Rode o script CRIAR_PORTAL_CONTADOR_SUPABASE.sql no SQL Editor do Supabase
  2. Tenha o arquivo .env na raiz do projeto com SUPABASE_URL e SUPABASE_ANON_KEY

COMO USAR:
  # Criar/atualizar o acesso com senha propria
  python criar_acesso_portal_contador.py --cnpj 04.829.400/0001-65 --senha "MinhaSenha123" --nome "Escritorio Contabil ABC"

  # Criar usando a SENHA PADRAO (quando --senha nao e informado)
  python criar_acesso_portal_contador.py --cnpj 04829400000165 --nome "Contador Joao"

  # Listar os acessos cadastrados
  python criar_acesso_portal_contador.py --listar

  # Desativar um acesso (o contador deixa de conseguir entrar)
  python criar_acesso_portal_contador.py --cnpj 04829400000165 --desativar

Observacao: a senha NUNCA e gravada em texto puro - o banco guarda apenas o
hash sha256(salt + senha), exatamente o mesmo calculo feito pelo app.

SEGURANCA: a senha padrao e apenas para o PRIMEIRO acesso / testes. Troque-a
logo depois rodando de novo o script com --cnpj e --senha (ele atualiza o
mesmo acesso, sem duplicar).
"""

import argparse
import hashlib
import os
import secrets
import sys
import uuid

import requests

TABELA = "portal_contador_acessos"

# Senha usada quando --senha nao e informado. TROQUE depois do primeiro acesso.
SENHA_PADRAO = "Exodo@2026"


def carregar_env():
    """Le as credenciais do Supabase a partir do arquivo .env do projeto."""
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
        print("[ERRO] Defina SUPABASE_URL e SUPABASE_ANON_KEY no arquivo .env da raiz do projeto.")
        sys.exit(1)
    return url.rstrip("/"), key


def headers(key, extra=None):
    cabecalhos = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if extra:
        cabecalhos.update(extra)
    return cabecalhos


def somente_digitos(valor):
    return "".join(c for c in valor if c.isdigit())


def gerar_hash(senha, salt):
    return hashlib.sha256((salt + senha).encode("utf-8")).hexdigest()


def criar_ou_atualizar(url, key, cnpj, senha, nome, email):
    cnpj = somente_digitos(cnpj)
    if len(cnpj) != 14:
        print(f"[ERRO] CNPJ invalido: informe 14 digitos (recebido {len(cnpj)}).")
        sys.exit(1)

    usou_padrao = not senha
    if usou_padrao:
        senha = SENHA_PADRAO
    if len(senha) < 6:
        print("[ERRO] A senha precisa ter pelo menos 6 caracteres.")
        sys.exit(1)

    salt = secrets.token_hex(16)
    payload = {
        "id": str(uuid.uuid4()),
        "cnpj": cnpj,
        "nome": nome or "Contador",
        "email": email or "",
        "salt": salt,
        "senha_hash": gerar_hash(senha, salt),
        "ativo": True,
    }

    # ON CONFLICT (cnpj) DO UPDATE
    resposta = requests.post(
        f"{url}/rest/v1/{TABELA}?on_conflict=cnpj",
        json=payload,
        headers=headers(key, {"Prefer": "resolution=merge-duplicates,return=representation"}),
        timeout=30,
    )

    if resposta.status_code not in (200, 201):
        print(f"[ERRO] Falha ao gravar o acesso: {resposta.status_code} - {resposta.text}")
        print("       Verifique se o script CRIAR_PORTAL_CONTADOR_SUPABASE.sql foi executado.")
        sys.exit(1)

    print("[OK] Acesso do contador cadastrado/atualizado com sucesso!")
    print(f"     CNPJ de login: {cnpj}")
    print(f"     Nome: {payload['nome']}")
    if usou_padrao:
        print(f"     Senha: {SENHA_PADRAO}   <-- SENHA PADRAO")
        print("     ATENCAO: troque esta senha! Rode de novo com --senha para atualizar.")
    else:
        print("     Senha: (a que voce digitou - nao e armazenada)")
    print("     Endereco do portal: https://exodosystems-1541d.web.app/portal-contador")


def listar(url, key):
    resposta = requests.get(
        f"{url}/rest/v1/{TABELA}?select=cnpj,nome,email,ativo,ultimo_acesso&order=cnpj",
        headers=headers(key),
        timeout=30,
    )
    if resposta.status_code != 200:
        print(f"[ERRO] Falha ao listar: {resposta.status_code} - {resposta.text}")
        sys.exit(1)

    acessos = resposta.json()
    if not acessos:
        print("Nenhum acesso cadastrado ainda.")
        return

    print(f"{len(acessos)} acesso(s) cadastrado(s):\n")
    for acesso in acessos:
        situacao = "ATIVO" if acesso.get("ativo") else "DESATIVADO"
        print(
            f"  CNPJ {acesso.get('cnpj')} | {situacao} | "
            f"{acesso.get('nome') or '-'} | ultimo acesso: {acesso.get('ultimo_acesso') or 'nunca'}"
        )


def desativar(url, key, cnpj):
    cnpj = somente_digitos(cnpj)
    resposta = requests.patch(
        f"{url}/rest/v1/{TABELA}?cnpj=eq.{cnpj}",
        json={"ativo": False},
        headers=headers(key, {"Prefer": "return=representation"}),
        timeout=30,
    )
    if resposta.status_code not in (200, 204):
        print(f"[ERRO] Falha ao desativar: {resposta.status_code} - {resposta.text}")
        sys.exit(1)

    if resposta.status_code == 200 and not resposta.json():
        print(f"[AVISO] Nenhum acesso encontrado para o CNPJ {cnpj}.")
        return
    print(f"[OK] Acesso do CNPJ {cnpj} desativado.")


def main():
    parser = argparse.ArgumentParser(description="Gerencia os acessos do Portal do Contador.")
    parser.add_argument("--cnpj", help="CNPJ de login do contador")
    parser.add_argument(
        "--senha",
        help=f"Senha do contador (minimo 6 caracteres). Padrao: {SENHA_PADRAO}",
    )
    parser.add_argument("--nome", help="Nome do contador/escritorio")
    parser.add_argument("--email", help="E-mail do contador")
    parser.add_argument("--listar", action="store_true", help="Lista os acessos cadastrados")
    parser.add_argument("--desativar", action="store_true", help="Desativa o acesso do CNPJ informado")
    args = parser.parse_args()

    url, key = carregar_env()

    if args.listar:
        listar(url, key)
    elif args.desativar:
        if not args.cnpj:
            print("[ERRO] Informe o --cnpj junto com --desativar.")
            sys.exit(1)
        desativar(url, key, args.cnpj)
    elif args.cnpj:
        criar_ou_atualizar(url, key, args.cnpj, args.senha, args.nome, args.email)
    else:
        parser.print_help()
        print("\n[ERRO] Informe --cnpj (ou use --listar / --desativar).")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Publica uma versão nova em UM comando, nos dois canais:

  1. bump da versão (código + pubspec);
  2. `flutter build windows --release`  -> pacote .zip do programa;
  3. `flutter build web --release`      -> build servido pelo site da central;
  4. upload do .zip (+ detalhes) para o bucket `atualizacoes`;
  5. grava a versão na `bridge_config` (global ou por empresa);
  6. histórico em HISTORICO_VERSOES.md.

Uso:
  python publicar_tudo.py                          # global, versão do código
  python publicar_tudo.py global 1.0.61
  python publicar_tudo.py <ID_DA_EMPRESA> 1.0.61 --force
  python publicar_tudo.py global 1.0.61 --notas "corrige o caixa"
  python publicar_tudo.py --sem-build-windows      # reaproveita o build atual
  python publicar_tudo.py --sem-build-web          # não mexe no site
  python publicar_tudo.py --simular                # mostra tudo, não envia nada

`--force` publica a versão com prefixo `!`: o app aplica em todo cliente cuja
versão instalada for DIFERENTE (é assim que se faz downgrade).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# O console do Windows abre em cp1252 e explode com acento/emoji.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BUCKET = "atualizacoes"
PASTA_WEB = os.path.join(BASE_DIR, "build", "web")
PASTA_WINDOWS = os.path.join(BASE_DIR, "build", "windows", "x64", "runner", "Release")

# Pastas dentro de build/web que NÃO vêm do Flutter e o build apaga.
# `central-servidor` é o painel copiado para o site.
EXTRAS_DO_SITE = ["central-servidor"]

ARQUIVO_VERSAO_CODIGO = os.path.join(
    BASE_DIR, "lib", "services", "app_update_service.dart"
)
ARQUIVO_PUBSPEC = os.path.join(BASE_DIR, "pubspec.yaml")


def log(msg=""):
    print(msg, flush=True)


def titulo(texto):
    log("=" * 64)
    log(f"   {texto}")
    log("=" * 64)


def ler_env():
    env = {}
    caminho = os.path.join(BASE_DIR, ".env")
    if os.path.exists(caminho):
        with open(caminho, "r", encoding="utf-8", errors="ignore") as f:
            for linha in f:
                linha = linha.strip()
                if linha and not linha.startswith("#") and "=" in linha:
                    chave, valor = linha.split("=", 1)
                    env[chave.strip()] = valor.strip().strip('"').strip("'")
    return env


def versao_valida(versao):
    return bool(re.fullmatch(r"\d+(\.\d+)*", str(versao or "").strip()))


def ler_versao_do_codigo():
    from publicar_pacote_comum import ler_versao_do_codigo as ler

    return ler(BASE_DIR)


def gravar_versao_no_codigo(versao):
    """Ajusta `currentAppVersion` (o app) e `version:` do pubspec (instalador/site)."""
    mudou = []

    with open(ARQUIVO_VERSAO_CODIGO, "r", encoding="utf-8") as f:
        codigo = f.read()
    novo = re.sub(
        r'(currentAppVersion\s*=\s*")[^"]+(")',
        lambda m: m.group(1) + versao + m.group(2),
        codigo,
        count=1,
    )
    if novo != codigo:
        with open(ARQUIVO_VERSAO_CODIGO, "w", encoding="utf-8") as f:
            f.write(novo)
        mudou.append("lib/services/app_update_service.dart")

    with open(ARQUIVO_PUBSPEC, "r", encoding="utf-8") as f:
        pubspec = f.read()
    # build_number acompanha o último segmento (1.0.61+61)
    numero = int(str(versao).split(".")[-1]) if str(versao).split(".")[-1].isdigit() else 0
    novo_pub = re.sub(
        r"(?m)^version:\s*\S+",
        f"version: {versao}+{numero}",
        pubspec,
        count=1,
    )
    if novo_pub != pubspec:
        with open(ARQUIVO_PUBSPEC, "w", encoding="utf-8") as f:
            f.write(novo_pub)
        mudou.append("pubspec.yaml")

    return mudou


def achar_flutter():
    """Descobre o flutter mesmo quando ele não está no PATH do processo.

    O painel da central roda este script sem herdar o PATH do PowerShell, então
    `flutter` dava "comando não encontrado". Procuramos na ordem: PATH, variável
    FLUTTER_ROOT, o SDK que o projeto já usa (.dart_tool/package_config.json) e
    os diretórios mais comuns.
    """
    achado = shutil.which("flutter")
    if achado:
        return achado

    candidatos = []
    raiz = os.environ.get("FLUTTER_ROOT", "").strip()
    if raiz:
        candidatos.append(os.path.join(raiz, "bin", "flutter.bat"))

    try:
        with open(
            os.path.join(BASE_DIR, ".dart_tool", "package_config.json"),
            encoding="utf-8",
        ) as arquivo:
            for pacote in json.load(arquivo).get("packages") or []:
                if pacote.get("name") != "flutter":
                    continue
                uri = str(pacote.get("rootUri", ""))
                if uri.startswith("file:///"):
                    # <sdk>/packages/flutter  ->  <sdk>/bin/flutter.bat
                    caminho = uri[len("file:///") :]
                    sdk = os.path.dirname(os.path.dirname(caminho))
                    candidatos.append(os.path.join(sdk, "bin", "flutter.bat"))
                break
    except Exception:
        pass

    candidatos += [
        "C:/src/flutter/bin/flutter.bat",
        "C:/flutter/bin/flutter.bat",
        "C:/dev/flutter/bin/flutter.bat",
        os.path.expanduser("~/flutter/bin/flutter.bat"),
    ]
    for candidato in candidatos:
        if candidato and os.path.isfile(candidato):
            return candidato
    return None


def rodar(comando, descricao):
    """Roda um comando no projeto; devolve (ok, mensagem)."""
    comando = list(comando)
    if comando and comando[0] == "flutter":
        caminho = achar_flutter()
        if caminho:
            comando[0] = caminho
    if os.name == "nt" and comando and comando[0].lower().endswith(
        (".bat", ".cmd")
    ):
        comando = ["cmd", "/c"] + comando
    log(f"▶ {descricao}")
    log(f"  $ {' '.join(comando)}")
    try:
        processo = subprocess.run(
            comando,
            cwd=BASE_DIR,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        return False, (
            f"comando não encontrado: {comando[0]}"
            + (
                " — instale o Flutter ou defina FLUTTER_ROOT"
                if comando[0].lower().endswith("flutter") or comando[0] == "flutter"
                else ""
            )
        )
    saida = (processo.stdout or "") + (processo.stderr or "")
    if processo.returncode != 0:
        ultimas = "\n".join(saida.strip().splitlines()[-15:])
        return False, f"{descricao} falhou (código {processo.returncode}):\n{ultimas}"
    if "Out of memory" in saida or "OutOfMemory" in saida:
        return False, "compilação sem memória: feche programas e tente de novo"
    log("  ✓ ok")
    return True, ""


def guardar_extras_do_site():
    """Copia as pastas que o `flutter build web` apaga (ex: central-servidor)."""
    temporario = tempfile.mkdtemp(prefix="site_extras_")
    guardadas = []
    for nome in EXTRAS_DO_SITE:
        origem = os.path.join(PASTA_WEB, nome)
        if os.path.isdir(origem):
            shutil.copytree(origem, os.path.join(temporario, nome))
            guardadas.append(nome)
    return temporario, guardadas


def devolver_extras_do_site(temporario, guardadas):
    for nome in guardadas:
        origem = os.path.join(temporario, nome)
        destino = os.path.join(PASTA_WEB, nome)
        if os.path.isdir(origem):
            if os.path.isdir(destino):
                shutil.rmtree(destino, ignore_errors=True)
            shutil.copytree(origem, destino)
    shutil.rmtree(temporario, ignore_errors=True)
    return guardadas


def enviar_pacote(supabase_url, chave, caminho_zip, nome_arquivo):
    """Sobe o .zip no bucket. Devolve a URL pública."""
    import requests

    cabecalhos = {
        "Authorization": f"Bearer {chave}",
        "apikey": chave,
        "x-upsert": "true",
        "Content-Type": "application/octet-stream",
    }
    url_upload = f"{supabase_url}/storage/v1/object/{BUCKET}/{nome_arquivo}"
    with open(caminho_zip, "rb") as f:
        dados = f.read()
    resposta = requests.post(url_upload, data=dados, headers=cabecalhos, timeout=600)
    if resposta.status_code not in (200, 201):
        raise RuntimeError(
            f"upload falhou: HTTP {resposta.status_code} - {resposta.text[:200]}"
        )
    return f"{supabase_url}/storage/v1/object/public/{BUCKET}/{nome_arquivo}"


def gravar_publicacao(supabase_url, chave, config_id, versao, url):
    """Cria ou atualiza a linha da `bridge_config` (upsert de verdade)."""
    import requests

    cabecalhos = {
        "apikey": chave,
        "Authorization": f"Bearer {chave}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=representation",
    }
    resposta = requests.post(
        f"{supabase_url}/rest/v1/bridge_config?on_conflict=id",
        json={"id": config_id, "version": versao, "download_url": url, "ativo": True},
        headers=cabecalhos,
        timeout=30,
    )
    if resposta.status_code not in (200, 201):
        raise RuntimeError(
            f"bridge_config falhou: HTTP {resposta.status_code} - {resposta.text[:200]}"
        )
    linhas = resposta.json()
    if not linhas or linhas[0].get("version") != versao:
        raise RuntimeError("a bridge_config não confirmou a versão gravada")
    return linhas[0]


def main():
    parser = argparse.ArgumentParser(description="Publica uma versão nos dois canais")
    parser.add_argument("destino", nargs="?", default="global",
                        help="'global' (todos) ou o ID da empresa")
    parser.add_argument("versao", nargs="?", default="",
                        help="versão a publicar (padrão: a do código)")
    parser.add_argument("--force", action="store_true",
                        help="publica com '!' (aplica também em downgrade)")
    parser.add_argument("--notas", default="", help="o que mudou nesta versão")
    parser.add_argument("--sem-build-windows", action="store_true",
                        help="reaproveita o build Release atual")
    parser.add_argument("--sem-build-web", action="store_true",
                        help="não recompila o site")
    parser.add_argument("--simular", action="store_true",
                        help="faz tudo, menos enviar/gravar na nuvem")
    args = parser.parse_args()

    from publicar_pacote_comum import (
        empacotar_programa,
        enviar_notas,
        nome_pacote,
        registrar_historico,
    )

    env = ler_env()
    supabase_url = (env.get("SUPABASE_URL") or "").rstrip("/")
    chave = (
        env.get("SUPABASE_SERVICE_ROLE_KEY")
        or env.get("SUPABASE_SERVICE_KEY")
        or env.get("SUPABASE_ANON_KEY")
        or ""
    )

    destino = (args.destino or "global").strip()
    eh_global = destino.lower() == "global"
    config_id = "app_latest" if eh_global else f"app_update_{destino}"

    versao_codigo = ler_versao_do_codigo()
    versao = (args.versao or versao_codigo or "").strip().replace("!", "")
    if not versao_valida(versao):
        log(f"❌ Versão inválida: {versao!r} (use algo como 1.0.61)")
        return 2
    versao_publicada = f"!{versao}" if args.force else versao

    titulo("PUBLICAR TUDO — SISTEMA ÊXODO")
    log(f"  Destino ........ {config_id} ({'TODAS as empresas' if eh_global else 'só esta empresa'})")
    log(f"  Versão ......... {versao_publicada}")
    log(f"  Versão no código {versao_codigo}")
    log(f"  Notas .......... {args.notas.strip() or '(nenhuma)'}")
    log(f"  Simulação ...... {'SIM (nada é enviado)' if args.simular else 'não'}")
    log()

    if not supabase_url or not chave:
        log("❌ Faltam SUPABASE_URL / chave no .env")
        return 2

    # 1. Bump das versões ------------------------------------------------
    if versao != versao_codigo:
        alterados = gravar_versao_no_codigo(versao)
        log(f"✏️  Versão atualizada em: {', '.join(alterados) or '(nada a mudar)'}")
    else:
        log("✏️  Versão do código já é a publicada.")

    # 2. Build do Windows ------------------------------------------------
    if args.sem_build_windows:
        log("▶ Build do Windows: reaproveitando o atual (--sem-build-windows)")
    else:
        ok, erro = rodar(["flutter", "build", "windows", "--release"], "Build do Windows")
        if not ok:
            log(f"❌ {erro}")
            return 1

    # 3. Pacote .zip -----------------------------------------------------
    nome_arquivo = nome_pacote(versao)
    caminho_zip = os.path.join(BASE_DIR, nome_arquivo)
    try:
        empacotar_programa(BASE_DIR, caminho_zip)
    except FileNotFoundError as erro:
        log(f"❌ {erro}")
        return 1
    tamanho_mb = os.path.getsize(caminho_zip) / 1024 / 1024
    log(f"📦 Pacote: {nome_arquivo} ({tamanho_mb:.1f} MB)")

    # 4. Build do site ---------------------------------------------------
    if args.sem_build_web:
        log("▶ Build do site: pulado (--sem-build-web)")
    else:
        temporario, guardadas = guardar_extras_do_site()
        ok, erro = rodar(["flutter", "build", "web", "--release"], "Build do site (web)")
        devolvidas = devolver_extras_do_site(temporario, guardadas)
        if not ok:
            log(f"❌ {erro}")
            if devolvidas:
                log(f"   (pastas do site restauradas: {', '.join(devolvidas)})")
            return 1
        if devolvidas:
            log(f"   pastas restauradas no site: {', '.join(devolvidas)}")
        json_versao = os.path.join(PASTA_WEB, "version.json")
        if os.path.exists(json_versao):
            with open(json_versao, "r", encoding="utf-8") as f:
                log(f"   site agora reporta: {f.read().strip()}")

    # 5. Upload + registro ----------------------------------------------
    if args.simular:
        log("▶ Simulação: upload e gravação na nuvem NÃO foram feitos.")
        log(f"   (seria {supabase_url}/storage/v1/object/public/{BUCKET}/{nome_arquivo})")
        log(f"   (seria bridge_config {config_id} = {versao_publicada})")
        return 0

    try:
        url_publica = enviar_pacote(supabase_url, chave, caminho_zip, nome_arquivo)
        log(f"📤 Pacote no ar: {url_publica}")
        if enviar_notas(
            supabase_url,
            {
                "Authorization": f"Bearer {chave}",
                "apikey": chave,
                "x-upsert": "true",
                "Content-Type": "text/plain",
            },
            BUCKET,
            versao,
            args.notas,
        ):
            log("📝 Detalhes da versão enviados.")
        linha = gravar_publicacao(
            supabase_url, chave, config_id, versao_publicada, url_publica
        )
        log(f"✅ Nuvem: {linha.get('id')} = {linha.get('version')}")
    except Exception as erro:
        log(f"❌ {erro}")
        return 1

    registrar_historico(
        BASE_DIR,
        versao,
        args.notas,
        "TODAS as empresas" if eh_global else f"empresa {destino}",
    )

    log()
    titulo("PRONTO")
    log("  Desktop: os clientes baixam no próximo boot:")
    log(f"    {config_id} = {versao_publicada}")
    log("  Site: o build novo já está em build/web (o portal serve de lá).")
    log("    Se a página mostrar a versão antiga, Ctrl+Shift+R no navegador.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

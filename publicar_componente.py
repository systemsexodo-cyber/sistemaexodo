#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Publica SÓ o sincronizador ou SÓ o bridge, separado do app.

O app tem o seu próprio pacote (`.zip` com `app.so` + `flutter_assets`, que é o
que a tela de atualização aplica). Sincronizador e bridge são executáveis
PyInstaller com ciclo de vida próprio e precisam de canal separado na
`bridge_config`:

    sinc   -> `sync_latest`  -> SincronizadorNuvem.exe (+ pasta _internal)
    bridge -> `latest`       -> ExodoNfceBridge.exe

Uso:
    python publicar_componente.py sinc 1.0.15
    python publicar_componente.py bridge 3.5.9 --build
    python publicar_componente.py sinc --simular

Antes de enviar, o script lê a versão do código (`VERSION` no
`sincronizar_local_supabase.py`, `BRIDGE_VERSION` no `backend_nfce/main.py`) e,
quando você informa outra, grava a nova no próprio fonte para não publicar um
executável que não sabe em que versão está.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import publicar_tudo as pt  # noqa: E402  (usa ler_env/upload/gravação já testados)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BUCKET = pt.BUCKET


class Componente:
    def __init__(self, chave, rotulo, config_id, executavel, fonte, regex_versao,
                 spec, empacotado_em_pasta):
        self.chave = chave
        self.rotulo = rotulo
        self.config_id = config_id
        self.executavel = executavel
        self.fonte = os.path.join(BASE_DIR, fonte)
        self.regex_versao = regex_versao
        self.spec = spec
        # `True` = o exe só funciona com a pasta ao lado (PyInstaller onedir).
        self.empacotado_em_pasta = empacotado_em_pasta


COMPONENTES = {
    "sinc": Componente(
        "sinc", "Sincronizador", "sync_latest", "SincronizadorNuvem.exe",
        "sincronizar_local_supabase.py", r'(?m)^VERSION\s*=\s*"([^"]+)"',
        "SincronizadorNuvem.spec", empacotado_em_pasta=True,
    ),
    "bridge": Componente(
        "bridge", "Bridge NFC-e", "latest", "ExodoNfceBridge.exe",
        os.path.join("backend_nfce", "main.py"),
        r'(?m)^BRIDGE_VERSION\s*=\s*"([^"]+)"',
        "ExodoNfceBridge.spec", empacotado_em_pasta=False,
    ),
}


def ler_versao_do_codigo(comp):
    try:
        with open(comp.fonte, encoding="utf-8", errors="replace") as arquivo:
            achado = re.search(comp.regex_versao, arquivo.read())
        return achado.group(1) if achado else ""
    except OSError:
        return ""


def gravar_versao_no_codigo(comp, versao):
    with open(comp.fonte, encoding="utf-8", errors="replace") as arquivo:
        texto = arquivo.read()
    novo = re.sub(comp.regex_versao, f'VERSION = "{versao}"' if comp.chave == "sinc"
                  else f'BRIDGE_VERSION = "{versao}"', texto, count=1)
    if novo == texto:
        return False
    with open(comp.fonte, "w", encoding="utf-8") as arquivo:
        arquivo.write(novo)
    return True


ARQUIVO_VERSAO_SINC = os.path.join(BASE_DIR, "version_sincronizador.txt")


def tupla_versao(versao):
    partes = [int(p) for p in re.findall(r"\d+", versao)][:4]
    while len(partes) < 4:
        partes.append(0)
    return tuple(partes)


def gravar_versao_no_arquivo_versao(versao):
    """Mantem o FileVersion do .exe igual ao VERSION do sinc.

    O `SincronizadorNuvem.spec` embute o `version_sincronizador.txt`. Se ele nao
    acompanha a publicacao, o exe sai com 1.0.16 nas propriedades mesmo
    publicado como 1.0.19 — o painel e a aba "Versoes do App" mostram o numero
    errado.
    """
    try:
        with open(ARQUIVO_VERSAO_SINC, encoding="utf-8", errors="replace") as arquivo:
            texto = arquivo.read()
    except OSError:
        return False

    tupla = ", ".join(str(p) for p in tupla_versao(versao))
    completo = f"{'.'.join(str(p) for p in tupla_versao(versao))}"
    novo = re.sub(r"filevers=\([^)]*\)", f"filevers=({tupla})", texto)
    novo = re.sub(r"prodvers=\([^)]*\)", f"prodvers=({tupla})", novo)
    novo = re.sub(r"'FileVersion', '[^']*'", f"'FileVersion', '{completo}'", novo)
    novo = re.sub(r"'ProductVersion', '[^']*'", f"'ProductVersion', '{completo}'", novo)
    if novo == texto:
        return False
    with open(ARQUIVO_VERSAO_SINC, "w", encoding="utf-8") as arquivo:
        arquivo.write(novo)
    return True


def versao_valida(versao):
    return bool(re.fullmatch(r"\d+(\.\d+){1,3}", versao or ""))


def achar_artefato(comp):
    """Devolve (caminho, eh_pasta). Prefere o build em `dist/`, cai para a raiz."""
    dist = os.path.join(BASE_DIR, "dist")
    if comp.empacotado_em_pasta:
        pasta = os.path.join(dist, os.path.splitext(comp.executavel)[0])
        if os.path.isdir(pasta):
            return pasta, True
        # Layout já montado na raiz: exe + _internal ao lado.
        exe = os.path.join(BASE_DIR, comp.executavel)
        if os.path.isfile(exe):
            return BASE_DIR, False
        return None, False

    for candidato in (
        os.path.join(dist, comp.executavel),
        os.path.join(BASE_DIR, comp.executavel),
    ):
        if os.path.isfile(candidato):
            return candidato, False
    return None, False


def compilar(comp):
    pt.log(f"▶ Compilando {comp.rotulo} ({comp.spec})")
    return pt.rodar(
        [sys.executable, "-m", "PyInstaller", comp.spec, "--clean", "--noconfirm"],
        f"Build do {comp.rotulo}",
    )


def montar_pacote(comp, versao):
    """Gera o arquivo a subir: `.exe` (bridge) ou `.zip` (sinc, que é uma pasta)."""
    origem, eh_pasta = achar_artefato(comp)
    if not origem:
        raise FileNotFoundError(
            f"executável do {comp.rotulo} não encontrado — rode com --build"
        )

    destino = os.path.join(BASE_DIR, "build", "componentes")
    os.makedirs(destino, exist_ok=True)
    if comp.empacotado_em_pasta:
        nome = f"{os.path.splitext(comp.executavel)[0]}_{versao}.zip"
        caminho = os.path.join(destino, nome)
        if eh_pasta:
            # Build novo: a pasta do `dist` inteira, do jeito que o PyInstaller fez.
            arquivos = []
            for raiz_pasta, _, nomes in os.walk(origem):
                for nome_arquivo in nomes:
                    completo = os.path.join(raiz_pasta, nome_arquivo)
                    arquivos.append((completo,
                                     os.path.relpath(completo, origem)))
        else:
            # Layout montado na raiz: SÓ o executável e a pasta `_internal`.
            # Zipar a raiz inteira levava código-fonte do projeto para o cliente.
            arquivos = [(os.path.join(origem, comp.executavel), comp.executavel)]
            interna = os.path.join(origem, "_internal")
            for raiz_pasta, _, nomes in os.walk(interna):
                for nome_arquivo in nomes:
                    completo = os.path.join(raiz_pasta, nome_arquivo)
                    arquivos.append((completo,
                                     os.path.relpath(completo, origem)))

        with zipfile.ZipFile(caminho, "w", zipfile.ZIP_DEFLATED) as zipado:
            for completo, relativo in arquivos:
                zipado.write(completo, relativo.replace("\\", "/"))
        return caminho, nome, zipado_tamanho(caminho)

    nome = f"{os.path.splitext(comp.executavel)[0]}_{versao}.exe"
    caminho = os.path.join(destino, nome)
    shutil.copy2(origem, caminho)
    return caminho, nome, os.path.getsize(caminho)


def zipado_tamanho(caminho):
    return os.path.getsize(caminho)


def main():
    parser = argparse.ArgumentParser(description="Publica sinc ou bridge separado do app")
    parser.add_argument("componente", choices=sorted(COMPONENTES))
    parser.add_argument("versao", nargs="?", default="")
    parser.add_argument("--build", action="store_true",
                        help="compila com PyInstaller antes de publicar")
    parser.add_argument("--simular", action="store_true",
                        help="faz tudo, menos enviar/gravar na nuvem")
    args = parser.parse_args()

    comp = COMPONENTES[args.componente]
    env = pt.ler_env()
    supabase_url = (env.get("SUPABASE_URL") or "").rstrip("/")
    chave = (env.get("SUPABASE_SERVICE_ROLE_KEY")
             or env.get("SUPABASE_SERVICE_KEY")
             or env.get("SUPABASE_ANON_KEY") or "")
    base_publica = pt.url_publica_base(env, supabase_url)

    versao_codigo = ler_versao_do_codigo(comp)
    versao = (args.versao or versao_codigo or "").strip()
    if not versao_valida(versao):
        pt.log(f"❌ Versão inválida: {versao!r} (ex: 1.0.15)")
        return 2

    pt.titulo(f"PUBLICAR {comp.rotulo.upper()} — SISTEMA ÊXODO")
    pt.log(f"  Canal .......... {comp.config_id} (todas as máquinas)")
    pt.log(f"  Versão ......... {versao}")
    pt.log(f"  Versão no código {versao_codigo or '(não achei)'}")
    pt.log(f"  Simulação ...... {'SIM (nada é enviado)' if args.simular else 'não'}")
    if base_publica != supabase_url:
        pt.log(f"  Link p/ cliente  {base_publica} (o .env aponta para o Kong local)")
    pt.log()

    if not args.simular and (not supabase_url or not chave):
        pt.log("❌ Faltam SUPABASE_URL / chave no .env")
        return 2

    if versao != versao_codigo:
        if gravar_versao_no_codigo(comp, versao):
            pt.log(f"✏️  Versão atualizada em {os.path.relpath(comp.fonte, BASE_DIR)}")
        if comp.chave == "sinc" and gravar_versao_no_arquivo_versao(versao):
            pt.log(f"✏️  FileVersion do exe: {versao}")
    elif comp.chave == "sinc" and gravar_versao_no_arquivo_versao(versao):
        # Mesmo com a mesma versao no codigo, o arquivo de versao pode estar atras.
        pt.log(f"✏️  FileVersion do exe sincronizado com {versao}")

    if args.build:
        ok, erro = compilar(comp)
        if not ok:
            pt.log(f"❌ {erro}")
            return 1
        if comp.chave == "sinc":
            # Erro de sintaxe num modulo nao quebra o PyInstaller: ele gera o
            # exe SEM o modulo e o sincronizador so falha no cliente. Conferir
            # aqui evita subir pacote quebrado como `sync_latest`.
            ok_modulos, _ = pt.rodar(
                [sys.executable, "verificar_sincronizador.py"],
                "Conferência dos módulos do build",
            )
            if not ok_modulos:
                pt.log("❌ Build saiu sem os módulos principais — NADA foi publicado.")
                return 1
    else:
        pt.log("▶ Build: reaproveitando o executável atual (use --build para recompilar)")

    try:
        caminho, nome, tamanho = montar_pacote(comp, versao)
    except FileNotFoundError as erro:
        pt.log(f"❌ {erro}")
        return 1
    pt.log(f"📦 Pacote: {nome} ({tamanho / 1024 / 1024:.1f} MB)")

    if args.simular:
        pt.log("▶ Simulação: upload e gravação na nuvem NÃO foram feitos.")
        pt.log(f"   (seria {base_publica}/storage/v1/object/public/{BUCKET}/{nome})")
        pt.log(f"   (seria bridge_config {comp.config_id} = {versao})")
        return 0

    try:
        url = pt.enviar_pacote(supabase_url, chave, caminho, nome, base_publica)
        pt.log(f"📤 No ar: {url}")
        pt.gravar_publicacao(supabase_url, chave, comp.config_id, versao, url)
        pt.log(f"✅ Nuvem: {comp.config_id} = {versao}")
    except Exception as erro:
        pt.log(f"❌ {erro}")
        return 1

    pt.log()
    pt.log("As máquinas aplicam no próximo ciclo do sincronizador.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

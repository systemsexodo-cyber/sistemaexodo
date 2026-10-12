"""
Monta e nomeia o PACOTE de atualização usado pelos publicadores.

Por que existe: publicar só o `sistema_exodo_novo.exe` NÃO atualiza o programa.
Esse .exe é o runner do Flutter: tem ~85 KB e é idêntico em todas as versões —
o código de verdade fica no `data/app.so` (+ `data/flutter_assets`, que tem as
telas, fontes e imagens). O pacote leva os três, em .zip, e o app é que o aplica.

O nome do arquivo na nuvem carrega a versão (`sistema_exodo_novo_1.0.37.zip`),
então publicar para uma empresa nunca troca o arquivo que outra já baixou e não
existe cache servindo uma versão velha no lugar da nova.
"""

import os
import zipfile


def nome_pacote(versao: str) -> str:
    """`1.0.37` -> `sistema_exodo_novo_1.0.37.zip` (só caracteres seguros)."""
    limpa = str(versao).replace("!", "").strip()
    segura = "".join(c if (c.isalnum() or c in "._-") else "_" for c in limpa)
    return f"sistema_exodo_novo_{segura or 'sem_versao'}.zip"


def nome_notas(versao: str) -> str:
    """Detalhes da versão, ao lado do pacote: `..._1.0.37.notas.txt`."""
    return nome_pacote(versao).replace(".zip", ".notas.txt")


def enviar_notas(supabase_url, headers_upload, bucket_name, versao, notas):
    """Sobe os DETALHES da atualização (o cliente lê na tela de atualização).

    Devolve True se subiu; False é aceitável — a atualização funciona sem eles.
    """
    import requests

    texto = (notas or "").strip()
    if not texto:
        return False
    url = (f"{supabase_url.rstrip('/')}/storage/v1/object/{bucket_name}/"
           f"{nome_notas(versao)}")
    try:
        r = requests.post(url, data=texto.encode("utf-8"),
                          headers=headers_upload, timeout=60)
        return r.status_code in (200, 201)
    except Exception:
        return False


def proxima_versao(atual: str, tipo: str = "correcao") -> str:
    """Proximo numero: correcao 1.0.36->1.0.37, nova->1.1.0, grande->2.0.0."""
    partes = []
    for pedaco in str(atual or "0.0.0").replace("!", "").strip().split("."):
        partes.append(int(pedaco) if pedaco.isdigit() else 0)
    while len(partes) < 3:
        partes.append(0)
    maior, menor, correcao = partes[0], partes[1], partes[2]
    if tipo == "nova":
        return f"{maior}.{menor + 1}.0"
    if tipo == "grande":
        return f"{maior + 1}.0.0"
    return f"{maior}.{menor}.{correcao + 1}"


def ler_versao_do_codigo(base_dir: str):
    """Le `currentAppVersion` do codigo; None se nao achar."""
    import re

    caminho = os.path.join(base_dir, "lib", "services", "app_update_service.dart")
    if not os.path.exists(caminho):
        return None
    with open(caminho, "r", encoding="utf-8") as f:
        achado = re.search(r'currentAppVersion\s*=\s*"([^"]+)"', f.read())
    return achado.group(1) if achado else None


def registrar_historico(base_dir: str, versao: str, notas: str, destino: str):
    """Acrescenta a versao publicada no HISTORICO_VERSOES.md do projeto."""
    import datetime

    caminho = os.path.join(base_dir, "HISTORICO_VERSOES.md")
    if not os.path.exists(caminho):
        with open(caminho, "w", encoding="utf-8") as f:
            f.write("# Histórico de versões publicadas\n\n"
                    "Cada entrada é escrita quando uma versão é publicada.\n")
    agora = datetime.datetime.now()
    linhas = ["", f"## {versao} — {agora.strftime('%d/%m/%Y %H:%M')}",
              f"- destino: {destino}"]
    texto = (notas or "").strip() or "(sem detalhes informados)"
    for linha in texto.split("\n"):
        linhas.append(f"- {linha.strip()}")
    with open(caminho, "a", encoding="utf-8") as f:
        f.write("\n".join(linhas) + "\n")
    return True


def pasta_do_programa(base_dir: str) -> str:
    """Pasta do build Release (onde estão o .exe e a pasta data/)."""
    return os.path.join(base_dir, "build", "windows", "x64", "runner", "Release")


def empacotar_programa(base_dir: str, destino_zip: str) -> str:
    """Monta o .zip com `data/app.so`, `data/flutter_assets` e o executável.

    Levanta FileNotFoundError com explicação se o programa não estiver compilado.
    """
    release = pasta_do_programa(base_dir)
    exe = os.path.join(release, "sistema_exodo_novo.exe")
    app_so = os.path.join(release, "data", "app.so")
    assets = os.path.join(release, "data", "flutter_assets")

    if not os.path.exists(app_so) or not os.path.exists(exe):
        raise FileNotFoundError(
            f"Programa compilado não encontrado em {release}\n"
            f"   (esperado: sistema_exodo_novo.exe e data\\app.so)"
        )

    if not destino_zip.lower().endswith(".zip"):
        destino_zip += ".zip"

    with zipfile.ZipFile(destino_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(exe, "sistema_exodo_novo.exe")
        z.write(app_so, "data/app.so")
        if os.path.isdir(assets):
            for raiz, _, arquivos in os.walk(assets):
                for nome in arquivos:
                    caminho = os.path.join(raiz, nome)
                    rel = os.path.relpath(caminho, release).replace("\\", "/")
                    z.write(caminho, rel)
    return destino_zip

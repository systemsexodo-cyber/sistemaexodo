#!/usr/bin/env python3
"""
Publicador de Atualização
Uso: python publicar_para_empresa.py ID_DA_EMPRESA [versao] [--force] [--notas "texto"]
     python publicar_para_empresa.py global [versao] [--force] [--notas "texto"]

--notas: os detalhes da atualização ("o que mudou"). Vão para a nuvem ao lado
do pacote e aparecem para o cliente na tela de atualização.

- Passando um ID de empresa: cria/atualiza app_update_{ID} na bridge_config
- Passando 'global': atualiza app_latest na bridge_config (TODOS os clientes)
- Usando --force: prefixa a versão com '!' para forçar downgrade

Faz o upload do PACOTE compilado (.zip com data/app.so, telas e executável)
para o Supabase Storage e cria/atualiza o registro na bridge_config.
O arquivo na nuvem leva a versão no nome (sistema_exodo_novo_<versao>.zip),
então publicar para uma empresa não troca o arquivo de outra versão.
"""

import os
import sys
import json
import requests

def main():
    # 1. Ler argumentos
    if len(sys.argv) < 2:
        print("❌ Uso: python publicar_para_empresa.py ID_DA_EMPRESA [versao] [--force] [--notas \"texto\"]")
        print("   Ex: python publicar_para_empresa.py emp_abc123 1.0.17")
        print("       python publicar_para_empresa.py emp_abc123 1.0.16 --force   (downgrade forçado)")
        print("       python publicar_para_empresa.py global 1.0.17   (para TODOS)")
        print("       python publicar_para_empresa.py global 1.0.17 --notas \"corrige o caixa\"")
        sys.exit(1)

    empresa_id = sys.argv[1]
    is_global = (empresa_id.lower() == 'global')
    
    # Extrair versão, --force e --notas
    new_version = "1.0.17"
    is_force = False
    notas = ""
    args = sys.argv[2:]
    for indice, arg in enumerate(args):
        if arg == '--force':
            is_force = True
        elif arg == '--notas':
            notas = args[indice + 1] if indice + 1 < len(args) else ""
        elif not arg.startswith('--') and (indice == 0 or args[indice - 1] != '--notas'):
            new_version = arg
    
    # Se for downgrade forçado, prefixar com '!'
    db_version = f"!{new_version}" if is_force else new_version

    # Se for global, o ID na bridge_config é 'app_latest'
    config_id = "app_latest" if is_global else f"app_update_{empresa_id}"

    print("=" * 60)
    if is_global:
        print(f"   🌍 PUBLICAR ATUALIZAÇÃO GLOBAL (app_latest)")
    else:
        print(f"   PUBLICAR ATUALIZAÇÃO PARA EMPRESA: {empresa_id}")
    print(f"   Config ID: {config_id}")
    print(f"   Versão: {new_version}")
    print("=" * 60)
    print()

    # 2. Carregar credenciais do .env
    base_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(base_dir, ".env")
    
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    env_vars[key.strip()] = val.strip().strip('"').strip("'")

    supabase_url = env_vars.get("SUPABASE_URL") or "https://febffvlpvxtiihvnfuts.supabase.co"
    supabase_key = env_vars.get("SUPABASE_SERVICE_KEY") or env_vars.get("SUPABASE_ANON_KEY")

    if not supabase_key:
        print("❌ Nenhuma chave encontrada no .env! (SUPABASE_SERVICE_KEY ou SUPABASE_ANON_KEY)")
        sys.exit(1)

    bucket_name = "atualizacoes"

    # 3. Montar o PACOTE (.zip)
    #    Só o .exe NÃO atualiza o programa: ele é o runner do Flutter (~85 KB) e
    #    é igual em todas as versões — o código fica no data/app.so.
    from publicar_pacote_comum import empacotar_programa, nome_pacote

    file_name = nome_pacote(new_version)
    local_exe = os.path.join(base_dir, file_name)
    try:
        empacotar_programa(base_dir, local_exe)
    except FileNotFoundError as erro:
        print(f"❌ Erro: {erro}")
        print(f"   Compile com: flutter build windows --release")
        sys.exit(1)

    print(f"📦 Pacote: {local_exe}")
    print(f"📏 Tamanho: {os.path.getsize(local_exe) / 1024 / 1024:.1f} MB")
    print()

    headers = {
        "Authorization": f"Bearer {supabase_key}",
        "apikey": supabase_key,
    }

    # 4. Upload do executável
    print("📤 Enviando para o Supabase Storage...")
    upload_url = f"{supabase_url}/storage/v1/object/{bucket_name}/{file_name}"
    headers_upload = {
        **headers,
        "x-upsert": "true",
        "Content-Type": "application/octet-stream",
    }

    with open(local_exe, "rb") as f:
        file_data = f.read()

    r = requests.post(upload_url, data=file_data, headers=headers_upload, timeout=300)
    if r.status_code not in (200, 201):
        print(f"❌ Falha no upload: {r.status_code} - {r.text[:200]}")
        # Tentar criar bucket primeiro
        print("🔄 Tentando criar bucket 'atualizacoes'...")
        bucket_url = f"{supabase_url}/storage/v1/bucket"
        r2 = requests.post(bucket_url, json={"id": bucket_name, "name": bucket_name, "public": True}, headers={**headers, "Content-Type": "application/json"}, timeout=15)
        if r2.status_code in (200, 201, 409):
            print("✅ Bucket pronto! Tentando upload novamente...")
            r = requests.post(upload_url, data=file_data, headers=headers_upload, timeout=300)
            if r.status_code not in (200, 201):
                print(f"❌ Falha no upload novamente: {r.status_code} - {r.text[:200]}")
                sys.exit(1)
        else:
            sys.exit(1)

    download_url = f"{supabase_url}/storage/v1/object/public/{bucket_name}/{file_name}"
    print(f"✅ Upload concluído!")
    print(f"🔗 URL: {download_url}")

    from publicar_pacote_comum import enviar_notas
    if enviar_notas(supabase_url, headers_upload, bucket_name, new_version, notas):
        print("📝 Detalhes da versão enviados (o cliente lê na atualização).")
    elif notas.strip():
        print("⚠️ Não consegui enviar os detalhes (a atualização segue normalmente).")
    print()

    # 5. Atualizar bridge_config
    print(f"💾 Atualizando '{config_id}' na bridge_config...")

    headers_db = {
        **headers,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }

    # Tentar PATCH primeiro (se já existe)
    update_url = f"{supabase_url}/rest/v1/bridge_config?id=eq.{config_id}"
    db_payload = {
        "version": db_version,
        "download_url": download_url,
    }
    
    r = requests.patch(update_url, json=db_payload, headers=headers_db, timeout=15)
    if r.status_code in (200, 204):
        print(f"✅ Registro '{config_id}' atualizado com sucesso!")
    else:
        # Se não existe, criar novo
        print(f"📝 Registro não encontrado. Criando novo...")
        insert_url = f"{supabase_url}/rest/v1/bridge_config"
        db_payload_insert = {
            "id": config_id,
            "version": db_version,
            "download_url": download_url,
        }
        r2 = requests.post(insert_url, json=db_payload_insert, headers=headers_db, timeout=15)
        if r2.status_code in (200, 201):
            print(f"✅ Registro '{config_id}' criado com sucesso!")
        else:
            print(f"❌ Erro: {r2.status_code} - {r2.text[:200]}")
            sys.exit(1)

    # 6. Confirmar que está no banco
    print()
    print("🔍 Verificando...")
    check = requests.get(
        f"{supabase_url}/rest/v1/bridge_config?id=eq.{config_id}",
        headers=headers_db,
        timeout=10
    )
    if check.status_code == 200 and check.json():
        data = check.json()[0]
        print(f"✅ Registro confirmado!")
        print(f"   ID: {data['id']}")
        print(f"   Versão: {data.get('version')}")
        print(f"   Download: {data.get('download_url')}")
    else:
        print(f"⚠️ Não foi possível confirmar: {check.text[:200]}")

    print()
    print("=" * 60)
    if is_global:
        print(f"   🌍 ATUALIZAÇÃO GLOBAL PUBLICADA!")
        print(f"   Todos os clientes receberão a versão {new_version}!")
    else:
        print(f"   🎉 ATUALIZAÇÃO PUBLICADA PARA A EMPRESA!")
        print(f"   ID: {empresa_id}")
        print(f"   Versão: {new_version}")
    print(f"   Quando o cliente abrir o app, a atualização será baixada!")
    print("=" * 60)


if __name__ == "__main__":
    main()

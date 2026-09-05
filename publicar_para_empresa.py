#!/usr/bin/env python3
"""
Publicador de Atualização
Uso: python publicar_para_empresa.py ID_DA_EMPRESA [versao] [--force]
     python publicar_para_empresa.py global [versao] [--force]

- Passando um ID de empresa: cria/atualiza app_update_{ID} na bridge_config
- Passando 'global': atualiza app_latest na bridge_config (TODOS os clientes)
- Usando --force: prefixa a versão com '!' para forçar downgrade

Faz o upload do executável compilado para o Supabase Storage
e cria/atualiza o registro correspondente na bridge_config.
"""

import os
import sys
import json
import requests

def main():
    # 1. Ler argumentos
    if len(sys.argv) < 2:
        print("❌ Uso: python publicar_para_empresa.py ID_DA_EMPRESA [versao] [--force]")
        print("   Ex: python publicar_para_empresa.py emp_abc123 1.0.17")
        print("       python publicar_para_empresa.py emp_abc123 1.0.16 --force   (downgrade forçado)")
        print("       python publicar_para_empresa.py global 1.0.17   (para TODOS)")
        sys.exit(1)

    empresa_id = sys.argv[1]
    is_global = (empresa_id.lower() == 'global')
    
    # Extrair versão e flag --force
    new_version = "1.0.17"
    is_force = False
    for arg in sys.argv[2:]:
        if arg == '--force':
            is_force = True
        elif not arg.startswith('--'):
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
    file_name = "sistema_exodo_novo.exe"
    
    # 3. Localizar executável compilado
    local_exe = os.path.join(base_dir, "build", "windows", "x64", "runner", "Release", file_name)
    if not os.path.exists(local_exe):
        # Tentar local alternativo
        local_exe = os.path.join(base_dir, file_name)
        if not os.path.exists(local_exe):
            print(f"❌ Executável não encontrado em:")
            print(f"   {os.path.join(base_dir, 'build', 'windows', 'x64', 'runner', 'Release', file_name)}")
            print(f"   Compile com: flutter build windows --release")
            sys.exit(1)

    print(f"📦 Executável: {local_exe}")
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

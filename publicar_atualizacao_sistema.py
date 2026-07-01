import os
import re
import sys
import subprocess
import requests

def main():
    print("=" * 60)
    print("   PUBLICADOR UNIFICADO DE ATUALIZACAO - SISTEMA EXODO")
    print("=" * 60)
    print()

    # 1. Carregar variaveis de ambiente do .env
    env_vars = {}
    if os.path.exists(".env"):
        with open(".env", "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    env_vars[key.strip()] = val.strip().strip('"').strip("'")

    supabase_url = env_vars.get("SUPABASE_URL")
    supabase_key = env_vars.get("SUPABASE_ANON_KEY")

    if not supabase_url or not supabase_key:
        print("[ERRO] SUPABASE_URL ou SUPABASE_ANON_KEY nao definidos no seu arquivo .env!")
        sys.exit(1)

    # 2. Menu de Opcoes
    print("Escolha qual componente deseja atualizar:")
    print("[1] Aplicativo Principal (sistema_exodo_novo.exe)")
    print("[2] Emissor NFC-e (ExodoNfceBridge.exe)")
    print("[3] Sincronizador Nuvem (SincronizadorNuvem.exe)")
    print()
    
    opcao = input("Digite a opcao desejada (1, 2 ou 3): ").strip()
    if opcao not in ("1", "2", "3"):
        print("[ERRO] Opcao invalida!")
        sys.exit(1)

    # 3. Solicitar numero da nova versao
    new_version = input("Digite a nova versao (ex: 1.0.9): ").strip()
    if not re.match(r"^\d+\.\d+\.\d+(\.\d+)?$", new_version):
        print("[ERRO] Versao invalida! Use o formato X.Y.Z (ex: 1.0.9).")
        sys.exit(1)

    base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
    bucket_name = "atualizacoes"

    # Configuracoes especificas por componente
    if opcao == "1":
        cfg_id = "app_latest"
        file_name = "sistema_exodo_novo.exe"
        local_exe_path = os.path.join(base_dir, "build", "windows", "x64", "runner", "Release", "sistema_exodo_novo.exe")
        
        # Atualizar a versao no codigo (app_update_service.dart) antes do build
        update_service_path = os.path.join(base_dir, "lib", "services", "app_update_service.dart")
        if os.path.exists(update_service_path):
            print("[INFO] Atualizando versao local no codigo do app...")
            with open(update_service_path, "r", encoding="utf-8") as f:
                content = f.read()

            new_content = re.sub(
                r'static const String currentAppVersion = "[^"]+";',
                f'static const String currentAppVersion = "{new_version}";',
                content
            )

            with open(update_service_path, "w", encoding="utf-8") as f:
                f.write(new_content)
            print(f"[OK] Versao do app atualizada para {new_version} no codigo!")

        # Compilar o Flutter
        print("\n[BUILD] Compilando aplicativo Flutter para Windows (Release)...")
        build_result = subprocess.run(["flutter", "build", "windows", "--release"], shell=True)
        if build_result.returncode != 0:
            print("[ERRO] Erro na compilacao do Flutter! O processo foi abortado.")
            sys.exit(1)
        print("[OK] Compilacao concluida com sucesso!")

    elif opcao == "2":
        cfg_id = "latest"
        file_name = "ExodoNfceBridge.exe"
        local_exe_path = os.path.join(base_dir, file_name)
        if not os.path.exists(local_exe_path):
            # Tentar na pasta dist do pyinstaller
            local_exe_path = os.path.join(base_dir, "backend_nfce", "dist", file_name)
            if not os.path.exists(local_exe_path):
                print(f"[ERRO] Coloque o arquivo '{file_name}' compilado na pasta raiz antes de rodar o publicador!")
                sys.exit(1)

    else: # opcao == "3"
        cfg_id = "sync_latest"
        file_name = "SincronizadorNuvem.exe"
        local_exe_path = os.path.join(base_dir, file_name)
        if not os.path.exists(local_exe_path):
            # Tentar na pasta dist do pyinstaller
            local_exe_path = os.path.join(base_dir, "dist", file_name)
            if not os.path.exists(local_exe_path):
                print(f"[ERRO] Coloque o arquivo '{file_name}' compilado na pasta raiz antes de rodar o publicador!")
                sys.exit(1)

    # 4. Enviar arquivo para o Supabase Storage
    if not os.path.exists(local_exe_path):
        print(f"[ERRO] Executavel nao encontrado em {local_exe_path}!")
        sys.exit(1)

    # Criar/garantir bucket
    print("\n[BUCKET] Verificando/Criando bucket 'atualizacoes' no Supabase...")
    bucket_url = f"{supabase_url}/storage/v1/bucket"
    headers = {
        "Authorization": f"Bearer {supabase_key}",
        "apikey": supabase_key,
        "Content-Type": "application/json"
    }
    try:
        requests.post(bucket_url, json={"id": bucket_name, "name": bucket_name, "public": True}, headers=headers, timeout=10)
    except Exception as e:
        print(f"[AVISO] Nao foi possivel verificar/criar o bucket: {e}")

    # Upload do executavel
    print(f"[UPLOAD] Fazendo upload de {file_name} para o Supabase Storage...")
    upload_url = f"{supabase_url}/storage/v1/object/{bucket_name}/{file_name}"
    headers_upload = {
        "Authorization": f"Bearer {supabase_key}",
        "apikey": supabase_key,
        "x-upsert": "true",
        "Content-Type": "application/octet-stream"
    }

    with open(local_exe_path, "rb") as f:
        file_data = f.read()

    r = requests.post(upload_url, data=file_data, headers=headers_upload, timeout=180)
    if r.status_code not in (200, 201):
        print(f"[ERRO] Falha ao subir arquivo para o Storage: {r.status_code} - {r.text}")
        sys.exit(1)
    print("[OK] Executavel enviado com sucesso!")

    # 5. Atualizar a tabela bridge_config no Supabase
    download_url = f"{supabase_url}/storage/v1/object/public/{bucket_name}/{file_name}"
    print(f"[LINK] Link de download: {download_url}")
    print(f"\n[BANCO] Atualizando registro '{cfg_id}' na tabela 'bridge_config'...")

    update_db_url = f"{supabase_url}/rest/v1/bridge_config?id=eq.{cfg_id}"
    db_payload = {
        "version": new_version,
        "download_url": download_url
    }

    r = requests.patch(update_db_url, json=db_payload, headers=headers, timeout=10)
    if r.status_code in (200, 204):
        print("[OK] Tabela do banco atualizada com sucesso!")
    else:
        # Se nao existe, tenta inserir
        print(f"[INFO] Registro '{cfg_id}' nao encontrado. Criando um novo...")
        insert_url = f"{supabase_url}/rest/v1/bridge_config"
        db_payload_insert = {
            "id": cfg_id,
            "version": new_version,
            "download_url": download_url
        }
        r2 = requests.post(insert_url, json=db_payload_insert, headers=headers, timeout=10)
        if r2.status_code in (200, 201):
            print("[OK] Registro criado no banco com sucesso!")
        else:
            print(f"[ERRO] Erro ao registrar nova versao no banco de dados: {r2.status_code} - {r2.text}")
            sys.exit(1)

    print("\n[SUCESSO] ATUALIZACAO PUBLICADA COM SUCESSO!")
    print(f"Versao {new_version} do componente '{file_name}' ja esta ativa na nuvem!")
    print("-" * 60)

if __name__ == "__main__":
    main()

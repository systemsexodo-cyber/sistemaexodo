import os
import re
import sys
import subprocess
import requests

def main():
    print("=" * 60)
    print("   PUBLICADOR AUTOMÁTICO DE ATUALIZAÇÃO - SISTEMA ÊXODO")
    print("=" * 60)
    print()

    # 1. Carregar variáveis de ambiente do arquivo .env
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
        print("❌ Erro: SUPABASE_URL ou SUPABASE_ANON_KEY não definidos no seu arquivo .env!")
        sys.exit(1)

    # 2. Solicitar número da nova versão
    new_version = input("Digite a nova versão do aplicativo (ex: 1.0.9): ").strip()
    if not re.match(r"^\d+\.\d+\.\d+(\.\d+)?$", new_version):
        print("❌ Versão inválida! Use o formato numérico X.Y.Z (ex: 1.0.9).")
        sys.exit(1)

    # 3. Atualizar a versão no código (app_update_service.dart)
    update_service_path = "lib/services/app_update_service.dart"
    if not os.path.exists(update_service_path):
        print(f"❌ Erro: Arquivo não encontrado: {update_service_path}")
        sys.exit(1)

    print("📝 Atualizando versão local no código do app...")
    with open(update_service_path, "r", encoding="utf-8") as f:
        content = f.read()

    new_content = re.sub(
        r'static const String currentAppVersion = "[^"]+";',
        f'static const String currentAppVersion = "{new_version}";',
        content
    )

    with open(update_service_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"✅ Código atualizado para a versão {new_version}!")

    # 4. Compilar o Flutter em modo Release para Windows
    print("\n🔨 Compilando aplicativo Flutter para Windows (Release)...")
    build_result = subprocess.run(["flutter", "build", "windows", "--release"], shell=True)

    if build_result.returncode != 0:
        print("❌ Erro na compilação do Flutter! O processo foi abortado.")
        sys.exit(1)
    print("✅ Compilação concluída com sucesso!")

    # 5. Fazer upload do executável para o Supabase Storage
    local_exe_path = r"build\windows\x64\runner\Release\sistema_exodo_novo.exe"
    if not os.path.exists(local_exe_path):
        print(f"❌ Erro: Executável compilado não encontrado em {local_exe_path}!")
        sys.exit(1)

    bucket_name = "atualizacoes"
    file_name = "sistema_exodo_novo.exe"

    # Criar/garantir bucket
    print("\n📦 Verificando/Criando bucket 'atualizacoes' no Supabase...")
    bucket_url = f"{supabase_url}/storage/v1/bucket"
    headers = {
        "Authorization": f"Bearer {supabase_key}",
        "apikey": supabase_key,
        "Content-Type": "application/json"
    }
    try:
        r = requests.post(bucket_url, json={"id": bucket_name, "name": bucket_name, "public": True}, headers=headers)
        if r.status_code in (200, 201):
            print("✅ Bucket 'atualizacoes' criado!")
        elif r.status_code == 409:
            print("ℹ️ Bucket 'atualizacoes' já existe.")
        else:
            print(f"⚠️ Resposta ao configurar bucket: {r.status_code} - {r.text}")
    except Exception as e:
        print(f"⚠️ Não foi possível verificar/criar o bucket: {e}")

    # Upload do executável
    print("📤 Fazendo upload do executável para o Supabase Storage (isso pode levar alguns segundos)...")
    upload_url = f"{supabase_url}/storage/v1/object/{bucket_name}/{file_name}"
    headers_upload = {
        "Authorization": f"Bearer {supabase_key}",
        "apikey": supabase_key,
        "x-upsert": "true",
        "Content-Type": "application/octet-stream"
    }

    with open(local_exe_path, "rb") as f:
        file_data = f.read()

    r = requests.post(upload_url, data=file_data, headers=headers_upload)
    if r.status_code not in (200, 201):
        print(f"❌ Falha ao subir arquivo para o Storage: {r.status_code} - {r.text}")
        sys.exit(1)
    print("✅ Executável enviado com sucesso!")

    # 6. Atualizar a tabela bridge_config no Supabase
    download_url = f"{supabase_url}/storage/v1/object/public/{bucket_name}/{file_name}"
    print(f"🔗 Link gerado: {download_url}")
    print("\n💾 Atualizando registro 'app_latest' na tabela 'bridge_config'...")

    update_db_url = f"{supabase_url}/rest/v1/bridge_config?id=eq.app_latest"
    db_payload = {
        "version": new_version,
        "download_url": download_url
    }

    r = requests.patch(update_db_url, json=db_payload, headers=headers)
    if r.status_code in (200, 204):
        print("✅ Tabela do banco atualizada com sucesso!")
    else:
        # Se não existe, tenta inserir
        print("ℹ️ Registro 'app_latest' não encontrado. Criando um novo...")
        insert_url = f"{supabase_url}/rest/v1/bridge_config"
        db_payload_insert = {
            "id": "app_latest",
            "version": new_version,
            "download_url": download_url
        }
        r2 = requests.post(insert_url, json=db_payload_insert, headers=headers)
        if r2.status_code in (200, 201):
            print("✅ Registro criado no banco com sucesso!")
        else:
            print(f"❌ Erro ao registrar nova versão no banco de dados: {r2.status_code} - {r2.text}")
            sys.exit(1)

    print("\n🎉 ATUALIZAÇÃO PUBLICADA COM SUCESSO!")
    print(f"Versão {new_version} já está ativa e será baixada pelos clientes no próximo boot!")
    print("-" * 60)

if __name__ == "__main__":
    main()

import os
import subprocess
import sys

def run_command(command):
    print(f"Executando: {command}")
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    while True:
        line = process.stdout.readline()
        if not line:
            break
        try:
            print(line.decode('utf-8').strip())
        except UnicodeDecodeError:
            print(line.decode('latin-1').strip())
    process.wait()
    return process.returncode

print("==================================================")
print("   INSTALADOR DO SERVIÇO DE NFC-e EXODO (WIN)    ")
print("==================================================")

# 1. Instalar dependências
print("\n--- Instalando bibliotecas Python necessárias ---")
run_command(f"pip install -r {os.path.join('backend_nfce', 'requirements.txt')}")

# 2. Criar Executável com PyInstaller
# print("\n--- Gerando executável do serviço (Isso pode demorar) ---")
# run_command("pyinstaller --onefile --noconsole backend_nfce/windows_service.py")

# 2. Corrigir pywin32 se necessário (post-install)
print("\n--- Configurando extensões do Windows (pywin32) ---")
try:
    import pywin32_system32
    print("pywin32_system32 encontrado.")
except ImportError:
    # Tentar rodar o post-install script
    scripts_path = os.path.join(os.path.dirname(sys.executable), "Scripts")
    post_install = os.path.join(scripts_path, "pywin32_postinstall.py")
    if os.path.exists(post_install):
        run_command(f'"{sys.executable}" "{post_install}" -install')
    else:
        # Tentar em AppData se for instalação user
        appdata_scripts = os.path.join(os.environ.get("APPDATA", ""), "Python", f"Python{sys.version_info.major}{sys.version_info.minor}", "Scripts")
        post_install = os.path.join(appdata_scripts, "pywin32_postinstall.py")
        if os.path.exists(post_install):
            run_command(f'"{sys.executable}" "{post_install}" -install')

# 2. Criar Executável com PyInstaller
print("\n--- Gerando executável do servidor (Isso pode demorar alguns minutos) ---")
# Usamos o main.py diretamente para simplicidade, rodando em background
main_script = os.path.abspath("backend_nfce/main.py")
dist_path = os.path.abspath("dist")
icon_path = os.path.abspath("exodo_logo.ico")
build_cmd = f'"{sys.executable}" -m PyInstaller --onefile --noconsole --collect-all lxml --collect-all uvicorn --collect-all multiprocessing --hidden-import multiprocessing --hidden-import _multiprocessing --hidden-import uvicorn --icon="{icon_path}" --name ExodoNfceBridge "{main_script}"'

if run_command(build_cmd) == 0:
    print("\n[OK] Executável gerado com sucesso!")
    exe_path = os.path.join(dist_path, "ExodoNfceBridge.exe")
    
    # Garantir que o executável também esteja em backend_nfce/dist
    target_dir = os.path.abspath("backend_nfce/dist")
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
    
    import shutil
    shutil.copy2(exe_path, os.path.join(target_dir, "ExodoNfceBridge.exe"))
    
    # Copiar credenciais do Firebase para ambas as pastas dist
    cred_src = os.path.abspath("backend_nfce/firebase-credentials.json")
    if os.path.exists(cred_src):
        shutil.copy2(cred_src, os.path.join(dist_path, "firebase-credentials.json"))
        shutil.copy2(cred_src, os.path.join(target_dir, "firebase-credentials.json"))
        print("[OK] Credenciais do Firebase copiadas para as pastas dist.")
    else:
        print("[WARN] firebase-credentials.json NÃO ENCONTRADO para cópia!")

    print(f"[OK] Cópia atualizada em: {target_dir}")
    
    # 3. Registrar no Windows para iniciar com o sistema (HKCU - Não precisa admin)
    print("\n--- Configurando para iniciar automaticamente ---")
    reg_cmd = f'REG ADD "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /V "ExodoNfceBridge" /T REG_SZ /D "{exe_path}" /F'
    
    if run_command(reg_cmd) == 0:
        print("\n[OK] Configurado para iniciar com o Windows!")
        # Iniciar agora
        subprocess.Popen([exe_path], shell=True)
        print("\n[OK] Servidor iniciado em segundo plano!")
    else:
        print("\n[ERRO] Falha ao registrar no Registro do Windows.")
else:
    print("\n[ERRO] Falha ao gerar o executável. Verifique os erros acima.")

print("\n==================================================")
print("Instalação Concluída!")
print("O emissor rodará sempre em segundo plano.")
print("Acesse http://localhost:8000 para verificar.")
print("==================================================")

#!/usr/bin/env python3
"""Script para gerar a versão v351 do Bridge NFC-e"""

import subprocess
import sys
import os
import shutil

def run(cmd, cwd=None):
    """Executa comando e mostra saída"""
    print(f">>> {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(f"ERR: {result.stderr}")
    return result.returncode == 0

def main():
    print("="*50)
    print("GERANDO BRIDGE v351")
    print("="*50)
    
    base_dir = os.path.dirname(os.path.abspath(__file__))
    backend_dir = os.path.join(base_dir, "backend_nfce")
    
    # Verificar Python
    if not run("python --version"):
        print("❌ Python não encontrado!")
        return 1
    
    # Criar/ativar venv
    venv_path = os.path.join(backend_dir, "venv")
    if not os.path.exists(venv_path):
        print("📦 Criando venv...")
        run(f"python -m venv \"{venv_path}\"")
    
    pip_exe = os.path.join(venv_path, "Scripts", "pip.exe")
    pyinst_exe = os.path.join(venv_path, "Scripts", "pyinstaller.exe")
    
    # Instalar dependências
    print("📦 Instalando dependências...")
    deps = "pyinstaller fastapi uvicorn pydantic requests pynfe signxml lxml cryptography pystray Pillow firebase-admin"
    run(f"\"{pip_exe}\" install -q {deps}")
    
    # Limpar builds
    print("🧹 Limpando builds...")
    for folder in ["build", "dist"]:
        path = os.path.join(backend_dir, folder)
        if os.path.exists(path):
            try:
                shutil.rmtree(path, ignore_errors=True)
            except:
                pass  # Ignora se estiver em uso
    
    # Compilar
    print("🔨 Compilando v351...")
    spec_file = os.path.join(backend_dir, "ExodoNfceBridge_v351.spec")
    if run(f"\"{pyinst_exe}\" \"{spec_file}\" --clean --noconfirm", cwd=backend_dir):
        # Copiar resultado
        src = os.path.join(backend_dir, "dist", "ExodoNfceBridge_v351.exe")
        dst = os.path.join(base_dir, "ExodoNfceBridge_v351.exe")
        if os.path.exists(src):
            shutil.copy2(src, dst)
            print(f"✅ Gerado: {dst}")
            print(f"   Tamanho: {os.path.getsize(dst) / 1024 / 1024:.1f} MB")
        else:
            print("❌ Arquivo não gerado!")
            return 1
    else:
        print("❌ Erro na compilação!")
        return 1
    
    print("\n✅ Bridge v351 gerado com sucesso!")
    print(f"   Local: {base_dir}\\ExodoNfceBridge_v351.exe")
    return 0

if __name__ == "__main__":
    sys.exit(main())

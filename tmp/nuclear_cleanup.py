import os
import subprocess
import time

def nuclear_cleanup():
    print("Iniciando limpeza nuclear...")
    
    # 1. Matar processos
    subprocess.run('taskkill /F /IM ExodoNfceBridge* /T', shell=True, capture_output=True)
    subprocess.run('taskkill /F /IM python.exe /T', shell=True, capture_output=True)
    
    time.sleep(2)
    
    # 2. Apagar arquivos v*.exe da raiz
    files = os.listdir('.')
    for f in files:
        if f.startswith('ExodoNfceBridge') and '_v' in f and f.endswith('.exe'):
            try:
                os.remove(f)
                print(f"Removido: {f}")
            except:
                print(f"Falha ao remover: {f}")

    if os.path.exists('ExodoNfceBridge.exe.new'): os.remove('ExodoNfceBridge.exe.new')
    if os.path.exists('ExodoNfceBridge.exe.old'): os.remove('ExodoNfceBridge.exe.old')

    print("Limpeza concluída.")

if __name__ == "__main__":
    nuclear_cleanup()

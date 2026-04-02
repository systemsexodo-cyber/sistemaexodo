import os
import subprocess

def check_startup():
    print("--- Verificando Tarefas Agendadas ---")
    res = subprocess.run(['schtasks', '/query', '/tn', 'ExodoNfceBridgeTask', '/fo', 'LIST', '/v'], capture_output=True, text=True)
    print(res.stdout)
    
    print("\n--- Verificando Registro (Run) ---")
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_READ)
        val, type = winreg.QueryValueEx(key, "ExodoNfceBridge")
        print(f"Registro Run: {val}")
        winreg.CloseKey(key)
    except Exception as e:
        print(f"Erro ao ler registro: {e}")

    print("\n--- Verificando Processos Rodando ---")
    res = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq ExodoNfceBridge*'], capture_output=True, text=True)
    print(res.stdout)

check_startup()

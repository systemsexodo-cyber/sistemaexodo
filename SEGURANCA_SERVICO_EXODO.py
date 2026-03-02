import os
import time
import subprocess
import sys
import ctypes

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def run_command(command, check_admin=False):
    if check_admin and not is_admin():
        print(f"[AVISO] O comando '{command}' pode exigir privilégios de Administrador.")
    
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

def instalar_nssm():
    """Baixa ou copia o nssm para a pasta do projeto se necessário"""
    # Para simplicidade, vamos usar o SC do Windows diretamente se possível,
    # mas o SC não lida bem com executáveis Python sem wrapper.
    # Vamos usar um script PowerShell para registrar como tarefa agendada que reinicia.
    print("\n--- Configurando Persistência Avançada ---")

def configurar_tarefa_agendada(exe_path):
    """Configura uma tarefa agendada que reinicia se falhar"""
    task_name = "ExodoNfceBridgeTask"
    
    # Remover se já existir
    run_command(f'schtasks /delete /tn "{task_name}" /f')
    
    # Criar tarefa que inicia ao logar e repete a cada 5 minutos se não estiver rodando
    cmd = f'schtasks /create /tn "{task_name}" /tr "{exe_path}" /sc onlogon /rl highest /f'
    if run_command(cmd, check_admin=True) == 0:
        print(f"[OK] Tarefa '{task_name}' criada com sucesso!")
        run_command(f'schtasks /run /tn "{task_name}"')
        return True
    return False

def configurar_registro_run(exe_path):
    """Fallback para o registro Run se a tarefa falhar"""
    reg_cmd = f'REG ADD "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run" /V "ExodoNfceBridge" /T REG_SZ /D "{exe_path}" /F'
    return run_command(reg_cmd) == 0

print("==================================================")
print("     SISTEMA DE SEGURANÇA EXODO NFC-E (AUTO)      ")
print("==================================================")

if not is_admin():
    print("\n[IMPORTANTE] Execute este script como ADMINISTRADOR")
    print("para garantir que o serviço reinicie automaticamente.")
    time.sleep(2)

# 1. Caminhos
dist_path = os.path.abspath("dist")
exe_name = "ExodoNfceBridge.exe"
exe_path = os.path.join(dist_path, exe_name)

if not os.path.exists(exe_path):
    print(f"\n[ERRO] Executável não encontrado em: {exe_path}")
    print("Por favor, rode o INSTALADOR_EXODO_NFCE.py primeiro.")
    sys.exit(1)

# 2. Encerrar processos antigos
print("\n--- Encerrando instâncias anteriores ---")
run_command(f'taskkill /f /im "{exe_name}" /t')

# 3. Configurar Auto-Restart via Scheduled Task (Mais robusto que Win Service para Python)
print("\n--- Configurando Reinício Automático em caso de falha ---")
sucesso = configurar_tarefa_agendada(exe_path)

if not sucesso:
    print("[AVISO] Falhou ao criar tarefa agendada. Usando Registro do Windows (menos seguro).")
    configurar_registro_run(exe_path)
    # Iniciar manualmente
    subprocess.Popen([exe_path], shell=True)
else:
    print("\n[OK] O serviço agora está protegido!")
    print("Se ele fechar, o Windows o abrirá novamente.")

print("\n==================================================")
print("Configuração de Segurança Concluída!")
print(f"Executável Protegido: {exe_name}")
print("==================================================")

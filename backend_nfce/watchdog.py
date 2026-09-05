"""
ExodoNfceBridge Watchdog
========================
Processo leve e independente que monitora o ExodoNfceBridge.exe
e o reinicia automaticamente sempre que ele fechar ou travar.

Instalado como Tarefa Agendada separada (ExodoNfceBridgeWatchdog).
"""

import sys
import os
import time
import subprocess
import logging
import json
from datetime import datetime

# --- Configuração ---
BRIDGE_EXE_NAME = "ExodoNfceBridge.exe"
CHECK_INTERVAL = 15        # Checar a cada 15 segundos
MAX_RESTART_DELAY = 120    # Máx. 2 min de espera antes de tentar novamente
RESTART_DELAY = 5          # Aguardar 5s antes de reiniciar

# Versão do Watchdog
WATCHDOG_VERSION = "2.5"

def get_base_path():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    # Quando rodando como .py, assume que está na mesma pasta do Bridge
    return os.path.dirname(os.path.abspath(__file__))

BASE_PATH = get_base_path()
LOG_PATH  = os.path.join(BASE_PATH, "watchdog_log.txt")
STATUS_PATH = os.path.join(BASE_PATH, "watchdog_status.json")

logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    filemode="a"
)

def log(msg, level="INFO"):
    print(f"[WATCHDOG] {msg}")
    if level == "INFO":    logging.info(msg)
    elif level == "ERROR": logging.error(msg)
    elif level == "WARN":  logging.warning(msg)

def is_bridge_running():
    """Verifica se o processo ExodoNfceBridge.exe está ativo."""
    try:
        result = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {BRIDGE_EXE_NAME}", "/NH"],
            capture_output=True, text=True, timeout=10,
            creationflags=0x08000000  # CREATE_NO_WINDOW
        )
        return BRIDGE_EXE_NAME.lower() in result.stdout.lower()
    except Exception as e:
        log(f"Erro ao checar processo: {e}", "ERROR")
        return False  # Assume que não está rodando para tentar iniciar

def start_bridge():
    """Inicia o ExodoNfceBridge.exe em background."""
    exe_path = os.path.join(BASE_PATH, BRIDGE_EXE_NAME)
    if not os.path.exists(exe_path):
        log(f"Executável não encontrado: {exe_path}", "ERROR")
        return False
    try:
        subprocess.Popen(
            [exe_path, "--silent"],
            cwd=BASE_PATH,
            creationflags=0x08000000 | 0x00000008,  # NO_WINDOW + DETACHED
        )
        log(f"Bridge iniciado: {exe_path}")
        return True
    except Exception as e:
        log(f"Falha ao iniciar Bridge: {e}", "ERROR")
        return False

def write_status(estado: str, reinicios: int, firebase_active=False):
    """Grava o status do watchdog em JSON para leitura pelo app."""
    try:
        with open(STATUS_PATH, "w") as f:
            json.dump({
                "estado": estado,
                "reinicios": reinicios,
                "firebase": firebase_active,
                "versao": WATCHDOG_VERSION,
                "timestamp": datetime.now().isoformat()
            }, f)
    except Exception:
        pass

# --- Firebase Integration for Remote Control ---
def setup_firebase():
    """Inicializa o Firebase no Watchdog (se credenciais existirem)."""
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
        import platform

        cred_file = os.path.join(BASE_PATH, "firebase-credentials.json")
        if not os.path.exists(cred_file): return None

        try:
            firebase_admin.get_app("watchdog")
        except ValueError:
            cred = credentials.Certificate(cred_file)
            firebase_admin.initialize_app(cred, name="watchdog")

        db = firestore.client(app=firebase_admin.get_app("watchdog"))
        return db
    except Exception as e:
        log(f"Erro ao iniciar Firebase no Watchdog: {e}", "WARN")
        return None

def processar_comando_watchdog(doc_id, data, db):
    """Processa comandos específicos para o Watchdog."""
    comando = data.get('comando')
    target_pc = data.get('target_pc')
    pc_name = os.environ.get('COMPUTERNAME', 'Unknown')

    if target_pc and target_pc != pc_name: return

    log(f"Comando recebido pelo Watchdog: {comando}")
    
    if comando in ['start', 'restart', 'force_bridge_start']:
        log("Executando início forçado do Bridge via comando remoto...")
        start_bridge()
        
        from firebase_admin import firestore
        db.collection('bridge_commands').document(doc_id).update({
            'status': 'concluido',
            'resultado': 'Início forçado executado pelo Watchdog',
            'sucesso': True,
            'finished_at': firestore.SERVER_TIMESTAMP
        })

def main():
    log("=" * 40)
    log("ExodoNfceBridge Watchdog INICIADO")
    log(f"Monitorando: {BRIDGE_EXE_NAME}")
    log("=" * 40)

    reinicios = 0
    db = setup_firebase()
    pc_name = os.environ.get('COMPUTERNAME', 'Unknown_PC')

    if db:
        log("Firebase ativo no Watchdog (Controle Remoto Disponível)")
        # Listener de comandos
        def on_snapshot(col_snapshot, changes, read_time):
            for change in changes:
                if change.type.name == 'ADDED':
                    data = change.document.to_dict()
                    if data.get('status') == 'pendente':
                        processar_comando_watchdog(change.document.id, data, db)

        db.collection('bridge_commands').where('status', '==', 'pendente').on_snapshot(on_snapshot)

    while True:
        try:
            # Heartbeat do Watchdog para o app saber que a proteção está ativa
            if db:
                from firebase_admin import firestore
                db.collection('bridge_status').document(f"watchdog_{pc_name}").set({
                    'pc_name': pc_name,
                    'online': True,
                    'last_seen': firestore.SERVER_TIMESTAMP,
                    'tipo': 'watchdog',
                    'versao': WATCHDOG_VERSION,
                    'bridge_running': is_bridge_running(),
                    'reinicios_feitos': reinicios
                }, merge=True)

            if not is_bridge_running():
                log(f"Bridge não encontrado! Reiniciando...", "WARN")
                write_status("offline", reinicios, db is not None)
                
                if start_bridge():
                    reinicios += 1
                    time.sleep(15) 
                else:
                    time.sleep(60)
            else:
                write_status("online", reinicios, db is not None)
        except Exception as e:
            log(f"Erro no loop principal: {e}", "ERROR")

        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()

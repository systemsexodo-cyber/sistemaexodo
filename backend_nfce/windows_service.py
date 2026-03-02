import win32serviceutil
import win32service
import win32event
import servicemanager
import socket
import sys
import os
import uvicorn

# Adicionar a pasta do backend ao path e mudar diretório de trabalho
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(BASE_DIR)
os.chdir(BASE_DIR)

try:
    from main import app
except Exception as e:
    # Se falhar o import, o serviço não inicia
    with open("service_error.log", "a") as f:
        f.write(f"Erro ao importar app: {e}\n")
    raise

class NfceBridgeService(win32serviceutil.ServiceFramework):
    _svc_name_ = "ExodoNfceBridge"
    _svc_display_name_ = "Exodo - Ponte de Emissão NFC-e"
    _svc_description_ = "Serviço de comunicação entre o PDV Exodo e a SEFAZ para emissão de notas."

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        self.hWaitStop = win32event.CreateEvent(None, 0, 0, None)
        socket.setdefaulttimeout(60)

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.hWaitStop)

    def SvcDoRun(self):
        # Iniciar o servidor FastAPI
        # Rodando em thread separada ou processo
        uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

if __name__ == '__main__':
    if len(sys.argv) == 1:
        servicemanager.Initialize()
        servicemanager.PrepareToHostSingle(NfceBridgeService)
        servicemanager.StartServiceCtrlDispatcher()
    else:
        win32serviceutil.HandleCommandLine(NfceBridgeService)

from fastapi import FastAPI, HTTPException, Request, Header, Depends
from pydantic import BaseModel
from typing import List, Optional
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import threading
import subprocess
import time
import os
import secrets
import ctypes
from nfce_handler import emitir_nfce_pynfe

app = FastAPI(title="Ponte de Emissão NFC-e Exodo")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Chave de segurança para acesso via Túnel
API_KEY_FILE = "exodo_bridge_key.txt"

def get_or_create_api_key():
    if os.path.exists(API_KEY_FILE):
        with open(API_KEY_FILE, "r") as f:
            return f.read().strip()
    key = secrets.token_hex(16)
    with open(API_KEY_FILE, "w") as f:
        f.write(key)
    return key

BRIDGE_API_KEY = get_or_create_api_key()

async def verify_api_key(x_api_key: str = Header(None)):
    if x_api_key != BRIDGE_API_KEY:
        raise HTTPException(status_code=403, detail="Chave de API inválida ou ausente")
    return x_api_key

class ConfigEmpresa(BaseModel):
    cnpj: str
    razao_social: str
    nome_fantasia: str
    inscricao_estadual: str
    codigo_municipio: str
    uf: str
    logradouro: str
    numero: str
    bairro: str
    cep: str
    municipio: str
    certificado_base64: str  # Certificado enviado em Base64 pelo App
    senha_certificado: str
    ambiente: int # 1 ou 2

class ItemVenda(BaseModel):
    codigo: str
    descricao: str
    ncm: str
    cfop: str
    quantidade: float
    valor_unitario: float
    valor_total: float

class RequisicaoEmissao(BaseModel):
    venda_numero: int
    data_emissao: str
    cpf_cliente: Optional[str] = None
    itens: List[ItemVenda]
    valor_total: float
    empresa: ConfigEmpresa

@app.post("/emitir", dependencies=[Depends(verify_api_key)])
async def emitir(req: RequisicaoEmissao):
    try:
        # O handler agora recebe tudo da requisição
        resultado = emitir_nfce_pynfe(req)
        return resultado
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
@app.get("/health")
def home():
    return {"status": "online", "message": "Emissor NFC-e Exodo rodando!"}

def self_install():
    try:
        import sys
        import winreg
        import ctypes
        
        # Obter o caminho do executável atual
        if getattr(sys, 'frozen', False):
            current_exe = sys.executable
        else:
            return # Se não for executável, ignore
            
        # Nome para o registro
        app_name = "ExodoNfceBridge"
        
        # Registrar no Windows
        key = winreg.HKEY_CURRENT_USER
        key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
        
        with winreg.OpenKey(key, key_path, 0, winreg.KEY_SET_VALUE) as reg_key:
            winreg.SetValueEx(reg_key, app_name, 0, winreg.REG_SZ, f'"{current_exe}"')
            
        # Mostrar mensagem apenas se rodado manualmente (opcional)
        if len(sys.argv) == 1:
            ctypes.windll.user32.MessageBoxW(0, "Emissor NFC-e Exodo iniciado com sucesso!", "Exodo NFC-e", 0x40)
        
    except Exception as e:
        print(f"Erro na auto-instalação: {e}")

def start_tunnel():
    """Tenta iniciar um túnel SSH em segundo plano de forma TOTALMENTE INVISÍVEL."""
    def run_ssh():
        import subprocess
        # Flags para esconder a janela no Windows
        CREATE_NO_WINDOW = 0x08000000
        
        # Caminho para salvar o status
        status_file = "STATUS_BRIDGE.txt"
        
        # Limpar processos antigos para não acumular janelas
        try:
            subprocess.run(["taskkill", "/F", "/IM", "ssh.exe"], capture_output=True, creationflags=CREATE_NO_WINDOW)
        except:
            pass

        print(f"[INFO] Iniciando túnel seguro invisível...")
        
        # Parâmetros:
        # StrictHostKeyChecking=no: Não pergunta se confia no servidor
        # UserKnownHostsFile=NUL: Não tenta gravar no arquivo de hosts do Windows (evita erro de permissão)
        cmd = [
            "ssh", 
            "-o", "StrictHostKeyChecking=no", 
            "-o", "UserKnownHostsFile=NUL", 
            "-R", "80:localhost:8000", 
            "nokey@localhost.run"
        ]
        
        while True:
            try:
                process = subprocess.Popen(
                    cmd, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.STDOUT, 
                    text=True,
                    creationflags=CREATE_NO_WINDOW # ESTA LINHA ESCONDE A JANELA PRETA
                )
                
                for line in process.stdout:
                    if "https://" in line:
                        url = line.strip()
                        print(f"[OK] Link gerado: {url}")
                        # Salva o link no arquivo para o usuário ver
                        with open(status_file, "w") as f:
                            f.write("=== STATUS DO EMISSOR EXODO ===\n\n")
                            f.write(f"LINK PUBLICO: {url}\n")
                            f.write(f"CHAVE DE API: {BRIDGE_API_KEY}\n\n")
                            f.write("Copie esses dados para as configuracoes da empresa no seu App.")
                process.wait()
            except Exception as e:
                with open(status_file, "w") as f:
                    f.write(f"ERRO NO TUNEL: {e}\nTentando reconectar em 60s...")
            time.sleep(60)

    thread = threading.Thread(target=run_ssh, daemon=True)
    thread.start()

if __name__ == "__main__":
    # Auto-instalação ao abrir
    self_install()
    
    # Iniciar túnel se não estiver em modo debug
    start_tunnel()
    
    # Configuração de log simplificada
    log_config = {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "format": "%(asctime)s - %(message)s",
            },
        },
        "handlers": {
            "default": {
                "formatter": "default",
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stderr",
            },
        },
        "loggers": {
            "uvicorn": {"handlers": ["default"], "level": "INFO"},
        },
    }
    uvicorn.run(app, host="0.0.0.0", port=8000, log_config=log_config)

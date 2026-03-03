import sys
import multiprocessing

# Suporte crítico para PyInstaller + Windows
if __name__ == '__main__':
    multiprocessing.freeze_support()
    try:
        multiprocessing.set_start_method('spawn', force=True)
    except RuntimeError:
        pass

try:
    import _multiprocessing
    import multiprocessing.resource_tracker
    import multiprocessing.popen_spawn_win32
except ImportError:
    pass

import uvicorn
import threading
import subprocess
import time
import os
import re
import secrets
import ctypes
import pynfe.utils # Importar para correção de caminhos
import sys
import platform
import re
from datetime import datetime
import json

# Correção de caminhos para pynfe quando compilado com PyInstaller
if getattr(sys, 'frozen', False):
    import os
    import sys
    import pynfe.utils
    # sys._MEIPASS é o diretório temporário onde o PyInstaller extrai tudo
    meipass = getattr(sys, '_MEIPASS', os.path.dirname(sys.executable))
    
    # Tentativa 1: Pasta 'pynfe/data' (Layout padrão que configuramos no spec)
    pynfe_data = os.path.join(meipass, "pynfe", "data")
    if not os.path.exists(pynfe_data):
        # Tentativa 2: Fallback (algumas versões do PyInstaller mudam o layout)
        pynfe_data = os.path.join(meipass, "data")
    
    pynfe.utils.CAMINHO_DATA = pynfe_data
    pynfe.utils.CAMINHO_MUNICIPIOS = os.path.join(pynfe_data, "MunIBGE")
    
    # DEBUG: Validar se o arquivo crítico existe
    test_file = os.path.join(pynfe.utils.CAMINHO_MUNICIPIOS, "MunIBGE-UF35.txt")
    if os.path.exists(test_file):
        print(f"[OK] MunIBGE localizado: {pynfe.utils.CAMINHO_MUNICIPIOS}")
    else:
        print(f"[AVISO] Arquivo MunIBGE-UF35.txt não encontrado em: {test_file}")
        # Forçar busca no diretório do executável como última alternativa
        base_dir = os.path.dirname(sys.executable)
        alt_data = os.path.join(base_dir, "pynfe", "data")
        if os.path.exists(alt_data):
            pynfe.utils.CAMINHO_DATA = alt_data
            pynfe.utils.CAMINHO_MUNICIPIOS = os.path.join(alt_data, "MunIBGE")
            print(f"[OK] Usando MunIBGE externo: {alt_data}")
from fastapi import FastAPI, HTTPException, Request, Header, Depends
from pydantic import BaseModel
from typing import List, Optional
from fastapi.middleware.cors import CORSMiddleware
from nfce_handler import emitir_nfce_pynfe
import firebase_admin
from firebase_admin import credentials, firestore

app = FastAPI(title="Ponte de Emissão NFC-e Exodo")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- EVENTOS DE STARTUP ---
@app.on_event("startup")
async def startup_event():
    print("="*40)
    print("INICIANDO EMISSOR EXODO - MODO BACKGROUND")
    print("="*40)
    
    # Criar arquivo de status local
    update_local_status()
    
    # Iniciar Listener do Firebase (Modo Sem Link)
    print("[INFO] Iniciando Listener do Firebase (Modo Sem Link)...")
    start_firebase_listener()
    
    # Auto-instalação no registro do Windows para iniciar com o PC
    try:
        self_install()
    except Exception as e:
        print(f"[WARN] Falha na auto-instalação: {e}")
    
    print("="*40)
    print("SISTEMA PRONTO PARA OPERAR")
    print("="*40)

# Chave de segurança (DESATIVADA A PEDIDO - ACESSO TOTAL)
async def verify_api_key(x_api_key: str = Header(None)):
    return x_api_key

class ConfigEmpresa(BaseModel):
    cnpj: str
    razao_social: Optional[str] = ""
    nome_fantasia: Optional[str] = ""
    inscricao_estadual: Optional[str] = ""
    codigo_municipio: Optional[str] = ""
    uf: str
    logradouro: Optional[str] = ""
    numero: Optional[str] = ""
    bairro: Optional[str] = ""
    cep: Optional[str] = ""
    municipio: Optional[str] = ""
    certificado_base64: str
    senha_certificado: str
    ambiente: int = 2
    csc: Optional[str] = ""
    csc_id: Optional[str] = ""

class ItemVenda(BaseModel):
    codigo: str
    descricao: str
    ncm: Optional[str] = "00000000"
    cfop: Optional[str] = "5102"
    quantidade: float
    valor_unitario: float
    valor_total: float

class RequisicaoEmissao(BaseModel):
    empresa: ConfigEmpresa
    itens: List[ItemVenda]
    valor_total: float
    data_emissao: Optional[str] = None
    venda_numero: Optional[int] = 0
    cpf_cliente: Optional[str] = None
    observacoes: Optional[str] = ""
    serie: Optional[int] = 1

@app.post("/emitir")
async def emitir(req: RequisicaoEmissao):
    try:
        # Garantir que venda_numero não seja None
        if req.venda_numero is None or req.venda_numero == 0:
            req.venda_numero = int(time.time()) % 100000000
            
        # DEBUG: Logar os dados da requisição HTTP
        print(f"[HTTP] Recebido (nº {req.venda_numero}): {req.model_dump_json()}")
        
        # O handler agora recebe tudo da requisição
        resultado = emitir_nfce_pynfe(req)
        return resultado
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        print(f"[HTTP ERRO] {e}\n{tb}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
@app.get("/health")
def home():
    return {"status": "online", "message": "Emissor NFC-e Exodo rodando!"}

# --- FIREBASE LISTENER ---
FIREBASE_ACTIVE = False

def processar_requisicao_firebase(db, doc_id, data):
    try:
        print(f"[FIREBASE] Processando {doc_id}...")
        doc_ref = db.collection('nfce_requests').document(doc_id)
        doc_ref.update({'status': 'processando'})
        
        # Garantir que campos vindos do Firebase via snapshots sejam convertidos
        if 'venda_numero' not in data and 'numero' in data:
            data['venda_numero'] = data['numero']
            
        if data.get('venda_numero') is None:
            # Gerar um número baseado no timestamp se não houver número da venda
            data['venda_numero'] = int(time.time()) % 100000000 # Max 9 digits
            print(f"[FIREBASE] venda_numero era None, gerado fallback: {data['venda_numero']}")
        
        try:
            req = RequisicaoEmissao(**data)
            print(f"[FIREBASE] Requisição validada.")
        except Exception as ve:
             print(f"[FIREBASE VALIDATION ERROR] {ve}")
             raise ve
        
        resultado = emitir_nfce_pynfe(req)
        
        if resultado.get('status') == 'sucesso':
            doc_ref.update({
                'status': 'autorizada',
                'resultado': resultado,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
            print(f"[FIREBASE] ✓ Sucesso: {doc_id}")
        else:
            doc_ref.update({
                'status': 'erro',
                'resultado': resultado,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
            print(f"[FIREBASE] ✗ Erro: {resultado.get('mensagem')}")
            
    except Exception as e:
        print(f"[FIREBASE] ✗ Erro interno ao processar {doc_id}: {e}")
        try:
            db.collection('nfce_requests').document(doc_id).update({
                'status': 'erro',
                'resultado': {'status': 'erro', 'mensagem': str(e)},
                'updated_at': firestore.SERVER_TIMESTAMP
            })
        except:
            pass

def processar_comando_remoto(db, doc_id, data):
    """Processa comandos recebidos via Firebase (update, restart, etc)"""
    try:
        comando = data.get('comando')
        print(f"[CMD] Recebido: {comando}")
        doc_ref = db.collection('bridge_commands').document(doc_id)
        doc_ref.update({'status': 'processando', 'started_at': firestore.SERVER_TIMESTAMP})
        
        resultado = "Comando desconhecido"
        sucesso = False
        
        if comando == 'update':
            print("[CMD] Executando Git Pull...")
            # Detecta diretório
            orig_dir = os.getcwd()
            try:
                # Tenta ir para a raiz do projeto (um nível acima de backend_nfce geralmente)
                os.chdir("..")
                res = subprocess.run(["git", "pull"], capture_output=True, text=True, timeout=30)
                resultado = f"Git Pull:\n{res.stdout}\n{res.stderr}"
                sucesso = res.returncode == 0
                print(f"[CMD] Update result: {sucesso}")
            finally:
                os.chdir(orig_dir)
        
        elif comando == 'restart':
            print("[CMD] Reiniciando serviço em 3 segundos...")
            doc_ref.update({'status': 'concluido', 'resultado': 'Reiniciando...', 'sucesso': True})
            time.sleep(3)
            # Função de restart definida no final do arquivo
            restart_action_silent()
            return

        elif comando == 'identify':
            pc_name = platform.node()
            os_info = platform.platform()
            resultado = f"PC: {pc_name} | OS: {os_info}"
            sucesso = True

        doc_ref.update({
            'status': 'concluido',
            'resultado': resultado,
            'sucesso': sucesso,
            'finished_at': firestore.SERVER_TIMESTAMP
        })
        
    except Exception as e:
        print(f"[CMD] ✗ Erro ao processar comando: {e}")
        try:
            db.collection('bridge_commands').document(doc_id).update({
                'status': 'erro',
                'resultado': str(e),
                'sucesso': False
            })
        except: pass

def start_firebase_listener():
    global FIREBASE_ACTIVE
    
    if getattr(sys, 'frozen', False):
        base_path = os.path.dirname(sys.executable)
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    cred_file = os.path.join(base_path, "firebase-credentials.json")
    status_file = os.path.join(base_path, "STATUS_BRIDGE.txt")
    
    if not os.path.exists(cred_file):
        cred_file = "firebase-credentials.json"
        if not os.path.exists(cred_file):
            print(f"[ERRO] firebase-credentials.json não encontrado.")
            return
            
    try:
        try:
            firebase_admin.get_app()
        except ValueError:
            cred = credentials.Certificate(cred_file)
            firebase_admin.initialize_app(cred)

        db = firestore.client()
        FIREBASE_ACTIVE = True
        print(f"[OK] Firebase Listener ativo!")

        # 0. Registrar heartbeat (online) no Firestore de forma segura
        def _safe_heartbeat():
            import time as _time
            while FIREBASE_ACTIVE:
                try:
                    _registrar_heartbeat(db)
                except Exception as e:
                    print(f"[DEBUG] Erro heartbeat: {e}")
                _time.sleep(60)
        
        threading.Thread(target=_safe_heartbeat, daemon=True).start()
        # Registrar o primeiro imediatamente
        _registrar_heartbeat(db)

        # 1. Listener de Notas Fiscais
        def on_snapshot(col_snapshot, changes, read_time):
            print(f">>> [DEBUG] Snapshot recebido! {len(changes)} alterações detectadas.")
            for change in changes:
                doc = change.document
                data = doc.to_dict()
                print(f">>> [DEBUG] Doc: {doc.id} | Status: {data.get('status')} | Tipo: {change.type.name}")
                
                if change.type.name == 'ADDED' or (change.type.name == 'MODIFIED' and data.get('status') == 'pendente'):
                    if data.get('status') == 'pendente':
                        print(f">>> [FIREBASE] 🔔 Nova nota recebida: {doc.id}")
                        threading.Thread(
                            target=processar_requisicao_firebase, 
                            args=(db, doc.id, data),
                            daemon=True
                        ).start()

        db.collection('nfce_requests').where('status', '==', 'pendente').on_snapshot(on_snapshot)
        
        # 2. Listener de Comandos Remotos
        def on_command_snapshot(col_snapshot, changes, read_time):
            for change in changes:
                if change.type.name == 'ADDED':
                    doc = change.document
                    data = doc.to_dict()
                    if data.get('status') == 'pendente':
                        threading.Thread(
                            target=processar_comando_remoto, 
                            args=(db, doc.id, data),
                            daemon=True
                        ).start()
        
        db.collection('bridge_commands').where('status', '==', 'pendente').on_snapshot(on_command_snapshot)
        print(f"[OK] Listener de Comandos Remotos ativo!")
        
    except Exception as e:
        print(f"[ERRO] Falha ao iniciar Firebase Listener: {e}")
        FIREBASE_ACTIVE = False

# --- UTILITÁRIOS ---
def _registrar_heartbeat(db):
    """Registra/atualiza o heartbeat do Bridge no Firestore."""
    try:
        import platform as _plt
        pc_name = _plt.node()
        # Higienizar id do documento
        import re as _re
        doc_id = _re.sub(r'[^a-zA-Z0-9_-]', '_', pc_name) or 'bridge'
        
        db.collection('bridge_status').document(doc_id).set({
            'online': True,
            'pc_name': pc_name,
            'last_seen': firestore.SERVER_TIMESTAMP,
            'versao': '2.1'
        }, merge=True)
        print(f">>> [OK] Sinal de vida (Heartbeat) enviado com sucesso: {pc_name}")
    except Exception as e:
        print(f">>> [AVISO] Falha ao enviar sinal de vida ao servidor: {e}")

def update_local_status():
    if getattr(sys, 'frozen', False):
        base_path = os.path.dirname(sys.executable)
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    status_file = os.path.join(base_path, "STATUS_BRIDGE.txt")
    with open(status_file, "w") as f:
        f.write("=== STATUS DO EMISSOR EXODO ===\n")
        f.write(f"Última inicialização: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n")
        f.write(f"Porta Local: 8000\n")
        f.write(f"Firebase: ATIVO\n")

def self_install():
    if not getattr(sys, 'frozen', False): return
    import winreg
    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE)
    winreg.SetValueEx(key, "ExodoNfceBridge", 0, winreg.REG_SZ, f'"{sys.executable}" --silent')
    winreg.CloseKey(key)

# --- TRAY ICON ---
def restart_action_silent():
    if getattr(sys, 'frozen', False):
        subprocess.Popen([sys.executable, "--silent"])
    else:
        subprocess.Popen([sys.executable] + sys.argv + ["--silent"])
    subprocess.run(["taskkill", "/F", "/PID", str(os.getpid())], creationflags=0x08000000)

def setup_tray():
    import pystray
    from PIL import Image, ImageDraw
    
    width, height = 64, 64
    image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    dc = ImageDraw.Draw(image)
    dc.rounded_rectangle([2, 2, 62, 62], radius=15, fill=(255, 152, 0))
    dc.rectangle([18, 16, 28, 48], fill="white")
    dc.rectangle([28, 16, 46, 23], fill="white")
    dc.rectangle([28, 28, 40, 35], fill="white")
    dc.rectangle([28, 40, 46, 47], fill="white")
    
    def quit_app(icon):
        icon.stop()
        os._exit(0)

    menu = pystray.Menu(
        pystray.MenuItem("Exodo Bridge Rodando", lambda: None, enabled=False),
        pystray.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
        pystray.MenuItem("Sair", lambda icon, item: quit_app(icon))
    )
    return pystray.Icon("exodo_bridge", image, "Exodo NFC-e Bridge", menu)

def run_server():
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info", reload=False, workers=1)

if __name__ == "__main__":
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    try:
        icon = setup_tray()
        icon.run()
    except Exception as e:
        print(f"Erro Tray: {e}")
        while True: time.sleep(1)

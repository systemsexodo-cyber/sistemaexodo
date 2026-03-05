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
import platform
import re
import shutil
from datetime import datetime
import json
import logging

# Configuração de Logs para Arquivo
logging.basicConfig(
    filename='bridge_log.txt',
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    filemode='a'
)

def log_message(msg, level="INFO"):
    print(f"[{level}] {msg}")
    if level == "INFO": logging.info(msg)
    elif level == "ERROR": logging.error(msg)
    elif level == "WARN": logging.warning(msg)

def get_pystray():
    import pystray
    return pystray

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

# Variáveis globais para rastreamento
LAST_PROCESSED_COMPANY = {"cnpj": None, "nome": None, "timestamp": None}

def get_base_path():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

IDENTITY_FILE = os.path.join(get_base_path(), "bridge_identity.json")

def load_identity():
    global LAST_PROCESSED_COMPANY
    if os.path.exists(IDENTITY_FILE):
        try:
            with open(IDENTITY_FILE, "r") as f:
                data = json.load(f)
                if data: LAST_PROCESSED_COMPANY = data
        except: pass

def save_identity():
    try:
        with open(IDENTITY_FILE, "w") as f:
            json.dump(LAST_PROCESSED_COMPANY, f)
    except: pass

# Carregar identidade ao iniciar
load_identity()

# --- EVENTOS DE STARTUP ---
@app.on_event("startup")
async def startup_event():
    log_message("="*40)
    log_message("INICIANDO EMISSOR EXODO - MODO BACKGROUND")
    log_message("="*40)
    
    # Criar arquivo de status local
    update_local_status()
    
    # Iniciar Listener do Firebase (Modo Sem Link)
    log_message("Iniciando Listener do Firebase (Modo Sem Link)...")
    start_firebase_listener()
    
    # Auto-instalação no registro do Windows para iniciar com o PC
    try:
        self_install()
    except Exception as e:
        log_message(f"Falha na auto-instalação: {e}", "WARN")
    
    log_message("="*40)
    log_message("SISTEMA PRONTO PARA OPERAR")
    log_message("="*40)

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

        # Atualizar rastreamento da empresa
        global LAST_PROCESSED_COMPANY
        LAST_PROCESSED_COMPANY = {
            "cnpj": req.empresa.cnpj,
            "nome": req.empresa.nome_fantasia or req.empresa.razao_social,
            "timestamp": datetime.now().isoformat()
        }
        save_identity()
        
        # Atualizar ícone da bandeja se disponível
        if GLOBAL_TRAY_ICON:
            try:
                empresa_nome = LAST_PROCESSED_COMPANY["nome"]
                cnpj = LAST_PROCESSED_COMPANY["cnpj"]
                ps = get_pystray()
                
                menu_items = [
                    ps.MenuItem(f"Empresa: {empresa_nome}", lambda: None, enabled=False),
                    ps.MenuItem(f"CNPJ: {cnpj}", lambda: None, enabled=False),
                    ps.Menu.SEPARATOR,
                    ps.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
                    ps.MenuItem("Sair", lambda icon, item: quit_app(icon))
                ]
                GLOBAL_TRAY_ICON.menu = ps.Menu(*menu_items)
                GLOBAL_TRAY_ICON.title = f"Exodo Bridge - {empresa_nome}"
            except Exception as tray_err: 
                print(f"[TRAY ERROR] {tray_err}")

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
        
        # Atualizar rastreamento da empresa
        global LAST_PROCESSED_COMPANY
        LAST_PROCESSED_COMPANY = {
            "cnpj": req.empresa.cnpj,
            "nome": req.empresa.nome_fantasia or req.empresa.razao_social,
            "timestamp": datetime.now().isoformat()
        }
        save_identity()

        # Atualizar ícone da bandeja se disponível
        if GLOBAL_TRAY_ICON:
            try:
                empresa_nome = LAST_PROCESSED_COMPANY["nome"]
                cnpj = LAST_PROCESSED_COMPANY["cnpj"]
                ps = get_pystray()
                
                menu_items = [
                    ps.MenuItem(f"Empresa: {empresa_nome}", lambda: None, enabled=False),
                    ps.MenuItem(f"CNPJ: {cnpj}", lambda: None, enabled=False),
                    ps.Menu.SEPARATOR,
                    ps.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
                    ps.MenuItem("Sair", lambda icon, item: quit_app(icon))
                ]
                GLOBAL_TRAY_ICON.menu = ps.Menu(*menu_items)
                GLOBAL_TRAY_ICON.title = f"Exodo Bridge - {empresa_nome}"
            except: pass

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
        target_pc = data.get('target_pc')
        pc_name = platform.node()
        
        # Se um target_pc foi definido e não for o meu PC, ignorar o comando
        if target_pc and target_pc != pc_name:
            print(f"[CMD] Ignorado comando para outra máquina: {target_pc} (Sou: {pc_name})")
            return
            
        print(f"[CMD] Recebido: {comando} para {target_pc or 'Todos'}")
        doc_ref = db.collection('bridge_commands').document(doc_id)
        
        # Tentar reivindicar e atualizar o status usando transaction (ou update genérico)
        doc_ref.update({'status': 'processando', 'started_at': firestore.SERVER_TIMESTAMP, 'processor_pc': pc_name})
        
        resultado = "Comando desconhecido"
        sucesso = False
        
        if comando == 'update':
            log_message("[CMD] Iniciando Processo de Atualização...")
            
            # Tenta Git primeiro (Se disponível na máquina)
            git_sucesso = False
            try:
                import subprocess
                # Verifica se git existe e se há um .git
                orig_dir = os.getcwd()
                git_dir = ".." if os.path.exists("../.git") else "."
                os.chdir(git_dir)
                
                res = subprocess.run(["git", "--version"], capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    log_message("[CMD] Git detectado. Tentando atualização via Git...")
                    subprocess.run(["git", "fetch", "--all"], capture_output=True, text=True, timeout=30)
                    res = subprocess.run(["git", "reset", "--hard", "origin/modo-dev"], capture_output=True, text=True, timeout=30)
                    
                    if res.returncode != 0:
                        res = subprocess.run(["git", "reset", "--hard", "origin/main"], capture_output=True, text=True, timeout=30)
                    
                    if res.returncode == 0:
                        log_message("[CMD] Atualização via Git concluída com sucesso.")
                        git_sucesso = True
                        resultado = f"Atualizado via Git:\n{res.stdout}"
                os.chdir(orig_dir)
            except Exception as e:
                log_message(f"[CMD] Git não disponível ou erro: {e}")
                try: os.chdir(orig_dir)
                except: pass

            # Se Git falhou ou não existe, tenta download via HTTP
            if not git_sucesso:
                log_message("[CMD] Git indisponível. Tentando Download Direto (HTTP)...")
                # URLs do GitHub - Nota: Se o repo for privado, isso dará 404 sem um Token
                BASE_URL = "https://raw.githubusercontent.com/systemsexodo-cyber/sistemaexodo/modo-dev/backend_nfce/"
                
                if getattr(sys, 'frozen', False):
                    # Modo Executável
                    exe_url = "https://github.com/systemsexodo-cyber/sistemaexodo/raw/modo-dev/ExodoNfceBridge.exe"
                    target_exe = sys.executable
                    new_exe = target_exe + ".new"
                    
                    try:
                        import requests
                        r = requests.get(exe_url, stream=True, timeout=60)
                        if r.status_code == 200:
                            with open(new_exe, 'wb') as f:
                                for chunk in r.iter_content(chunk_size=8192): f.write(chunk)
                            
                            bat_path = os.path.join(os.path.dirname(target_exe), "update_bridge.bat")
                            with open(bat_path, "w") as f:
                                f.write(f'@echo off\ntimeout /t 3\ntaskkill /F /PID {os.getpid()}\nmove /Y "{new_exe}" "{target_exe}"\nstart "" "{target_exe}"\ndel "%~f0"')
                            
                            doc_ref.update({'status': 'concluido', 'resultado': 'Atualizado via Download. Reiniciando.', 'sucesso': True})
                            subprocess.Popen([bat_path], shell=True)
                            return
                        else:
                            resultado = f"Erro HTTP {r.status_code}. Repositório pode ser privado."
                            git_sucesso = False
                    except Exception as e:
                        resultado = f"Erro no download: {e}"
                else:
                    # Modo Script
                    try:
                        import requests
                        files = ["main.py", "nfce_handler.py"]
                        for f_name in files:
                            r = requests.get(BASE_URL + f_name, timeout=30)
                            if r.status_code == 200:
                                with open(os.path.join(os.path.dirname(__file__), f_name), "wb") as f:
                                    f.write(r.content)
                            else:
                                raise Exception(f"Erro {r.status_code} no arquivo {f_name}")
                        git_sucesso = True
                        resultado = "Arquivos atualizados via HTTP."
                    except Exception as e:
                        resultado = f"Falha no download: {e}"
            
            sucesso = git_sucesso
            if sucesso:
                notify_user("Atualização Concluída", "O sistema foi atualizado com sucesso!")
                # Reiniciar par aplicar
                if not getattr(sys, 'frozen', False):
                    restart_action_silent()
            else:
                log_message(f"[CMD] Falha na atualização: {resultado}", "ERROR")
                notify_user("Falha na Atualização", "Não foi possível baixar os arquivos. Verifique a conexão.")
        
        elif comando == 'restart':
            log_message("[CMD] Comando Reiniciar recebido.")
            notify_user("Reiniciando", "O sistema do Emissor NFC-e será reiniciado remotamente agora.")
            doc_ref.update({'status': 'concluido', 'resultado': 'Reiniciando...', 'sucesso': True})
            time.sleep(3)
            restart_action_silent()
            return

        elif comando == 'identify':
            log_message("[CMD] Comando Identificar recebido.")
            pc_name = platform.node()
            os_info = platform.platform()
            empresa = LAST_PROCESSED_COMPANY.get('nome') or "Não Identificada"
            resultado = f"PC: {pc_name} | Empresa: {empresa} | Versão Bridge: 2.2 | OS: {os_info}"
            sucesso = True
            notify_user("Sinal Recebido", "A máquina foi identificada remotamente pelo Admin!")
            log_message(f"[CMD] Identificação enviada: {resultado}")

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
        log_message("Firebase Listener ativo!")

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
        log_message("Listener de Comandos Remotos ativo!")
        
    except Exception as e:
        log_message(f"Falha ao iniciar Firebase Listener: {e}", "ERROR")
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
            'versao': '2.2',
            'ultima_empresa': LAST_PROCESSED_COMPANY.get('nome'),
            'ultimo_cnpj': LAST_PROCESSED_COMPANY.get('cnpj'),
            'ultimo_processamento': LAST_PROCESSED_COMPANY.get('timestamp')
        }, merge=True)
        log_message(f"Sinal de vida (Heartbeat) enviado com sucesso: {pc_name}")
    except Exception as e:
        log_message(f"Falha ao enviar sinal de vida ao servidor: {e}", "WARN")

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
    exe_path = os.path.abspath(sys.executable)
    
    try:
        # Registrar o caminho atual para iniciar com o Windows
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, "ExodoNfceBridge", 0, winreg.REG_SZ, f'"{exe_path}" --silent')
        winreg.CloseKey(key)
        # log_message(f"Auto-inicialização configurada para: {exe_path}")
    except Exception as e:
        log_message(f"Erro ao configurar inicialização automática: {e}", "ERROR")

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

    def update_menu(icon):
        empresa_nome = LAST_PROCESSED_COMPANY.get('nome') or "Nenhuma"
        cnpj = LAST_PROCESSED_COMPANY.get('cnpj') or "Aguardando..."
        
        menu_items = [
            pystray.MenuItem(f"Exodo Bridge: {empresa_nome}", lambda: None, enabled=False),
            pystray.MenuItem(f"CNPJ: {cnpj}", lambda: None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
            pystray.MenuItem("Sair", lambda icon, item: quit_app(icon))
        ]
        icon.menu = pystray.Menu(*menu_items)

    icon = pystray.Icon("exodo_bridge", image, "Exodo NFC-e Bridge")
    icon.menu = pystray.Menu(
        pystray.MenuItem("Exodo Bridge Rodando", lambda: None, enabled=False),
        pystray.MenuItem("Aguardando empresa...", lambda: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
        pystray.MenuItem("Sair", lambda icon, item: quit_app(icon))
    )
    return icon

def run_server():
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info", reload=False, workers=1)

GLOBAL_TRAY_ICON = None

def notify_user(title, message):
    try:
        if GLOBAL_TRAY_ICON:
            GLOBAL_TRAY_ICON.notify(message, title=title)
    except Exception as e:
        print(f"Erro notificação: {e}")

if __name__ == "__main__":
    # Tentar auto-instalação se for a primeira vez
    if getattr(sys, 'frozen', False):
        self_install()
        
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    try:
        GLOBAL_TRAY_ICON = setup_tray()
        GLOBAL_TRAY_ICON.run()
    except Exception as e:
        print(f"Erro Tray: {e}")
        while True: time.sleep(1)

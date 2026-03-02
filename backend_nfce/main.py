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
import secrets
import ctypes
import pynfe.utils # Importar para correção de caminhos
import sys

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
    
    # Iniciar túnel SSH (DESATIVADO A PEDIDO)
    # print("[INFO] Iniciando Túnel SSH (Link Público)...")
    # start_tunnel()
    
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
        
        # DEBUG: Identificar qual campo tem 'N'
        for k, v in data.items():
            if v == 'N' or (hasattr(v, 'startswith') and v.startswith('N')):
                print(f"[FIREBASE DEBUG] Campo suspeito: {k} = {v}")
        
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

def start_firebase_listener():
    global FIREBASE_ACTIVE
    
    # Se estiver rodando como EXE compilado, buscar na pasta do executável
    if getattr(sys, 'frozen', False):
        base_path = os.path.dirname(sys.executable)
    else:
        # Se estiver rodando como script .py
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    cred_file = os.path.join(base_path, "firebase-credentials.json")
    status_file = os.path.join(base_path, "STATUS_BRIDGE.txt")
    
    if not os.path.exists(cred_file):
        print(f"[WARN] {cred_file} não encontrado. Buscando em caminhos alternativos...")
        # Fallback para o diretorio atual por garantia
        if not os.path.exists("firebase-credentials.json"):
            print(f"[ERRO] firebase-credentials.json não encontrado.")
            if os.path.exists(status_file):
                with open(status_file, "a") as f:
                    f.write("\nFIREBASE: ERRO (firebase-credentials.json não encontrado)")
            return
        cred_file = "firebase-credentials.json"
        
    try:
        # Tenta inicializar apenas se não houver um app padrão
        try:
            firebase_admin.get_app()
            print("[INFO] Firebase já possui um app ativo.")
        except ValueError:
            cred = credentials.Certificate(cred_file)
            firebase_admin.initialize_app(cred)
            print("[OK] Firebase App Inicializado!")

        db = firestore.client()
        FIREBASE_ACTIVE = True
        print(f"[OK] Firebase Listener ativo!")
        
        # Atualiza o arquivo de status para avisar que o Firebase está ativo
        if os.path.exists(status_file):
            with open(status_file, "r") as f:
                content = f.read()
            if "FIREBASE:" not in content:
                with open(status_file, "w") as f:
                    f.write("=== STATUS DO EMISSOR EXODO ===\n\n")
                    f.write("FIREBASE: CONECTADO (Modo Sem Link Ativo)\n\n")
                    f.write(content.replace("=== STATUS DO EMISSOR EXODO ===\n\n", ""))

        def on_snapshot(col_snapshot, changes, read_time):
            for change in changes:
                if change.type.name == 'ADDED':
                    doc = change.document
                    data = doc.to_dict()
                    # Apenas processa se for novo e estiver pendente
                    if data.get('status') == 'pendente':
                        # Rodar em uma thread separada para não travar o listener
                        threading.Thread(
                            target=processar_requisicao_firebase, 
                            args=(db, doc.id, data),
                            daemon=True
                        ).start()

        col_query = db.collection('nfce_requests').where('status', '==', 'pendente')
        col_query.on_snapshot(on_snapshot)
        
    except Exception as e:
        error_msg = f"[ERRO] Falha ao iniciar Firebase Listener: {e}"
        print(error_msg)
        FIREBASE_ACTIVE = False
        if os.path.exists(status_file):
            with open(status_file, "a") as f:
                f.write(f"\nFIREBASE: ERRO ({e})")

def self_install():
    """
    Auto-instalação robusta e silenciosa.
    """
    try:
        import sys
        import winreg
        import subprocess
        
        # Obter o caminho do executável atual
        if getattr(sys, 'frozen', False):
            current_exe = sys.executable
            base_dir = os.path.dirname(current_exe)
        else:
            return # Se não for executável, ignore
            
        app_name = "ExodoNfceBridge"
        marker_file = os.path.join(base_dir, ".installed_v1") # Versão do instalador
        
        # Se já estiver instalado silenciosamente, pula
        if os.path.exists(marker_file) and "--force-install" not in sys.argv:
            return

        # --- 1. REGISTRO DO WINDOWS ---
        try:
            key = winreg.HKEY_CURRENT_USER
            key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
            with winreg.OpenKey(key, key_path, 0, winreg.KEY_SET_VALUE) as reg_key:
                winreg.SetValueEx(reg_key, app_name, 0, winreg.REG_SZ, f'"{current_exe}"')
        except:
            pass
            
        # --- 2. TAREFA AGENDADA (Monitoria silenciosa) ---
        # Flags para esconder janelas de comando
        HIDDEN = 0x08000000
        try:
            task_name = "ExodoNfceBridgeMonitor"
            # Criar tarefa de monitoria a cada 5 minutos
            # Se já existir, o /f sobrescreve
            cmd = f'schtasks /create /tn "{task_name}" /tr "\'{current_exe}\'" /sc minute /mo 5 /rl highest /f'
            subprocess.run(cmd, shell=True, capture_output=True, creationflags=HIDDEN)
        except:
            pass
            
        # Marca como instalado
        with open(marker_file, "w") as f: f.write(str(time.time()))
        
        # Notificar o usuário apenas se não for um reinício automático
        if "--silent" not in sys.argv:
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, 
                "O Emissor Exodo foi otimizado! \n\nEle agora inicia com o Windows e se recupera sozinho se fechar.", 
                "Êxodo NFC-e - Blindagem Ativada", 0x40)
        
    except Exception as e:
        print(f"Erro na auto-instalação: {e}")

def update_local_status():
    """Cria o arquivo de status para modo local sem segurança."""
    status_file = "STATUS_BRIDGE.txt"
    try:
        with open(status_file, "w") as f:
            f.write("=== STATUS DO EMISSOR EXODO (MODO LOCAL) ===\n\n")
            f.write("ACESSO: http://localhost:8000\n")
            f.write("SEGURANÇA: Desativada (Acesso Livre)\n")
            f.write("MODO: Apenas rede local / Rede Interna\n\n")
            f.write("Configure o IP desta máquina no seu Aplicativo.")
    except:
        pass

def start_tunnel():
    """Tenta iniciar um túnel SSH (DESATIVADO)"""
    pass

import sys

def open_logs():
    # Abre o arquivo de status com o bloco de notas
    status_file = "STATUS_BRIDGE.txt"
    if os.path.exists(status_file):
        os.startfile(status_file)
    else:
        ctypes.windll.user32.MessageBoxW(0, "O Emissor ainda está iniciando e o arquivo não foi gerado. Aguarde alguns segundos.", "Exodo NFC-e", 0x40)

def quit_action(icon, item):
    icon.stop()
    # Mata forçosamente via Taskkill para garantir fechamento de tudo
    subprocess.run(["taskkill", "/F", "/PID", str(os.getpid())], creationflags=0x08000000)
    sys.exit(0)

def restart_action(icon, item):
    """Reinicia o aplicativo lançando uma nova instância e fechando a atual"""
    # Obter o comando de execução (funciona para script ou exe)
    if getattr(sys, 'frozen', False):
        subprocess.Popen([sys.executable, "--silent"])
    else:
        subprocess.Popen([sys.executable] + sys.argv + ["--silent"])
    
    # Fechar a instância atual
    quit_action(icon, item)

def setup_tray():
    import pystray
    from PIL import Image, ImageDraw
    
    # Cria um ícone visual profissional (Quadrado laranja arredondado com um E branco)
    width = 64
    height = 64
    image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    dc = ImageDraw.Draw(image)
    
    # Fundo Laranja (Cor padrão do Exodo)
    orange_color = (255, 152, 0) # #FF9800
    dc.rounded_rectangle([2, 2, 62, 62], radius=15, fill=orange_color)
    
    # Desenhar um "E" estilizado e grosso para ser visivel em 16x16 (area da bandeja)
    # Haste Vertical
    dc.rectangle([18, 16, 28, 48], fill="white")
    # Barras horizontais
    dc.rectangle([28, 16, 46, 23], fill="white") # Topo
    dc.rectangle([28, 28, 40, 35], fill="white") # Meio
    dc.rectangle([28, 40, 46, 47], fill="white") # Base
    
    menu = pystray.Menu(
        pystray.MenuItem("Exodo Bridge Rodando", lambda text: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Copiar Dados / Ver Status", open_logs),
        pystray.MenuItem("Reiniciar Serviço", restart_action),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Sair (Desliga emissões)", quit_action)
    )
    
    icon = pystray.Icon("exodo_bridge", image, "Exodo NFC-e Bridge", menu)
    return icon

def run_server():
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
    uvicorn.run(app, host="0.0.0.0", port=8000, log_config=log_config, reload=False, workers=1)

if __name__ == "__main__":
    # Rodar servidor web em uma thread para não travar a bandeja
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    
    # Inicia a Bandeja do Sistema
    try:
        icon = setup_tray()
        # O icon.run() é bloqueante, manterá o script vivo
        icon.run()
    except Exception as e:
        print(f"Erro ao iniciar bandeja: {e}")
        # Se falhar, pelo menos o servidor já está rodando via thread
        # Mas vamos entrar em loop infinito pra manter o exe vivo
        while True:
            time.sleep(1)

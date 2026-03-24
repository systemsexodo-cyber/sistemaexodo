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
import unicodedata # Correção para erro ModuleNotFoundError detectado no Charles

# Configuração de Logs para Arquivo com Rotação (Evita travar o app se o log for gigante)
def _get_log_path():
    if getattr(sys, 'frozen', False):
        return os.path.join(os.path.dirname(sys.executable), 'bridge_log.txt')
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bridge_log.txt')

LOG_FILE_PATH = _get_log_path()

# Se o log for maior que 10MB, rotacionar para não travar o Bridge
try:
    if os.path.exists(LOG_FILE_PATH) and os.path.getsize(LOG_FILE_PATH) > 10 * 1024 * 1024:
        bak_file = LOG_FILE_PATH + ".bak"
        if os.path.exists(bak_file): os.remove(bak_file)
        os.rename(LOG_FILE_PATH, bak_file)
except: pass

logging.basicConfig(
    filename=LOG_FILE_PATH,
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


# --- MODELOS ---
class ConfigEmpresa(BaseModel):
    cnpj: str
    razao_social: str
    nome_fantasia: Optional[str] = None
    inscricao_estadual: Optional[str] = None
    logradouro: Optional[str] = ""
    numero: Optional[str] = ""
    bairro: Optional[str] = ""
    municipio: Optional[str] = ""
    codigo_municipio: Optional[str] = ""
    uf: Optional[str] = ""
    cep: Optional[str] = ""
    crt: Optional[str | int] = "1"
    ambiente: int = 2
    certificado_base64: str
    senha_certificado: str
    csc: Optional[str] = ""
    csc_id: Optional[str] = ""

class ItemVenda(BaseModel):
    codigo: str
    descricao: str
    ncm: str = "00000000"
    cfop: str = "5102"
    quantidade: float
    valor_unitario: float
    valor_total: float
    icms_csosn: Optional[str] = "102"
    icms_cst: Optional[str] = "00"
    origem: Optional[str] = "0"
    icms_origem: Optional[int | str] = 0
    icms_aliquota: Optional[float] = 0.0

class RequisicaoEmissao(BaseModel):
    empresa: ConfigEmpresa
    itens: List[ItemVenda]
    valor_total: float
    venda_numero: Optional[str | int] = None
    cpf_cliente: Optional[str] = None

# --- AUXILIARES ---
def get_base_path():
    if getattr(sys, 'frozen', False): return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

def save_identity():
    try:
        path = os.path.join(get_base_path(), "bridge_identity.json")
        with open(path, "w", encoding='utf-8') as f:
            json.dump(LAST_PROCESSED_COMPANY, f)
    except: pass

def load_identity():
    global LAST_PROCESSED_COMPANY
    try:
        path = os.path.join(get_base_path(), "bridge_identity.json")
        if os.path.exists(path):
            with open(path, "r", encoding='utf-8') as f:
                LAST_PROCESSED_COMPANY = json.load(f)
    except: pass

# --- GLOBAIS ---
BRIDGE_VERSION = "3.4.6"

# Custom encoder for Firestore objects
def json_serial(obj):
    if hasattr(obj, 'isoformat'):
        return obj.isoformat()
    return str(obj)
LAST_PROCESSED_COMPANY = {"cnpj": "", "nome": "Aguardando...", "timestamp": ""}
load_identity()
GLOBAL_TRAY_ICON = None

@app.post("/api/nfce/emitir")
async def emitir_nfce_endpoint(req: RequisicaoEmissao):
    try:
        resultado = emitir_nfce_pynfe(req)
        
        # Sincronizar identidade da empresa processada
        global LAST_PROCESSED_COMPANY
        LAST_PROCESSED_COMPANY = {
            "cnpj": req.empresa.cnpj,
            "nome": req.empresa.nome_fantasia or req.empresa.razao_social,
            "timestamp": datetime.now().isoformat()
        }
        save_identity()
        
        try: update_tray_menu()
        except: pass

        return resultado
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        print(f"[HTTP ERRO EMISSAO] {e}\n{tb}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/nfce/cancelar")
async def cancelar_nfce_endpoint(req: Request):
    from nfce_handler import cancelar_nfce_pynfe
    try:
        data = await req.json()
        log_message(f">>> [DEBUG CANCEL] Dados recebidos: {json.dumps(data)[:500]}...")
        resultado = cancelar_nfce_pynfe(data)
        
        # O aplicativo Flutter espera os mesmos formatos (success=True/False)
        return resultado
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        print(f"[HTTP ERRO CANCELAMENTO] {e}\n{tb}")
        # Retornar 200 com success=False para tratar graciosamente no front
        return {"success": False, "error": str(e), "traceback": tb}

@app.post("/api/nfce/consultar")
async def consultar_nfce_endpoint(req: Request):
    from nfce_handler import consultar_nfce_pynfe
    try:
        data = await req.json()
        resultado = consultar_nfce_pynfe(data)
        return resultado
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/api/certificado/validar")
async def validar_certificado_endpoint(req: Request):
    from nfce_handler import validar_certificado_pynfe
    try:
        data = await req.json()
        resultado = validar_certificado_pynfe(data)
        return resultado
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/")
@app.get("/health")
def home():
    return {"status": "online", "message": "Emissor NFC-e Exodo rodando!"}

# --- FIREBASE LISTENER ---
FIREBASE_ACTIVE = False

def processar_requisicao_firebase(db, doc_id, data):
    try:
        log_message(f"[FIREBASE] ➜ Iniciando processamento: {doc_id}...")
        log_message(f"[FIREBASE] Dados recebidos (parcial): {json.dumps(data, default=json_serial)[:300]}...")
        doc_ref = db.collection('nfce_requests').document(doc_id)
        
        # Tentar atualizar status com timeout curto para não travar
        try:
            doc_ref.update({'status': 'processando'})
            log_message(f"[FIREBASE] {doc_id} marcado como 'processando'")
        except Exception as e_up:
            log_message(f"[FIREBASE WARNING] Nao conseguiu marcar como processando: {e_up}")
        
        # Garantir que campos vindos do Firebase via snapshots sejam convertidos
        if 'venda_numero' not in data and 'numero' in data:
            data['venda_numero'] = data['numero']
            
        if data.get('venda_numero') is None:
            # Não gerar mais timestamp, buscar do campo de numero se existir ou falhar
            data['venda_numero'] = data.get('numero', '1')
            print(f"[FIREBASE] venda_numero era None, usando fallback: {data['venda_numero']}")
        
        try:
            operacao = data.get('operacao', 'emissao')
            if operacao == 'cancelamento':
                from nfce_handler import cancelar_nfce_pynfe
                print(f"[FIREBASE] Operação: CANCELAMENTO do doc {doc_id}")
                resultado = cancelar_nfce_pynfe(data)
                # Normalizar resultado para o Firebase esperar sucesso/autorizada
                if resultado.get('success'):
                    resultado['status'] = 'sucesso' # O listener abaixo espera 'sucesso'
                else:
                    resultado['status'] = 'erro'
            else:
                req = RequisicaoEmissao(**data)
                print(f"[FIREBASE] Operação: EMISSAO do doc {doc_id}")
                resultado = emitir_nfce_pynfe(req)
        except Exception as ve:
             print(f"[FIREBASE VALIDATION ERROR] {ve}")
             raise ve
        
        # Atualizar rastreamento da empresa
        global LAST_PROCESSED_COMPANY
        LAST_PROCESSED_COMPANY = {
            "cnpj": data.get('empresa', {}).get('cnpj'),
            "nome": data.get('empresa', {}).get('nome_fantasia') or data.get('empresa', {}).get('razao_social'),
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
                    ps.MenuItem(f"Versão: {BRIDGE_VERSION}", lambda: None, enabled=False),
                    ps.MenuItem(f"Empresa: {empresa_nome}", lambda: None, enabled=False),
                    ps.MenuItem(f"CNPJ: {cnpj}", lambda: None, enabled=False),
                    ps.Menu.SEPARATOR,
                    ps.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
                    ps.MenuItem("Sair", lambda icon, item: quit_app(icon))
                ]
                GLOBAL_TRAY_ICON.menu = ps.Menu(*menu_items)
                GLOBAL_TRAY_ICON.title = f"Exodo Bridge v{BRIDGE_VERSION} - {empresa_nome}"
            except: pass

        log_message(f"[FIREBASE] Doc {doc_id} processado. Status do resultado: {resultado.get('status')}")

        if str(resultado.get('status')).lower() in ['sucesso', 'autorizada']:
            resultado_json = json.loads(json.dumps(resultado, default=json_serial))
            
            doc_ref.update({
                'status': 'autorizada',
                'resultado': resultado_json,
                'processed_at': firestore.SERVER_TIMESTAMP
            })
            log_message(f"[FIREBASE] ✓ Sucesso (Autorizada): {doc_id}")
        else:
            resultado_json = json.loads(json.dumps(resultado, default=json_serial))
            doc_ref.update({
                'status': 'erro',
                'resultado': resultado_json,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
            log_message(f"[FIREBASE] ✗ Erro: {resultado.get('error') or resultado.get('mensagem') or 'Erro genérico'}")
            
    except Exception as e:
        print(f"[FIREBASE] ✗ Erro interno ao processar {doc_id}: {e}")
        resultado_json = json.loads(json.dumps(resultado if 'resultado' in locals() else {'status': 'erro', 'mensagem': str(e)}, default=json_serial))
        try:
            db.collection('nfce_requests').document(doc_id).update({
                'status': 'erro',
                'resultado': resultado_json,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
        except:
            pass

def processar_comando_remoto(db, doc_id, data):
    """Processa comandos recebidos via Firebase (update, restart, etc)"""
    global LAST_PROCESSED_COMPANY
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
            log_message("[CMD] Iniciando Processo de Atualização Direto (Firebase)...")
            sucesso = False
            resultado = "Iniciando..."
            
            try:
                # Buscar configurações de atualização na nova coleção segura
                config_ref = db.collection('bridge_config').document('latest').get()
                if not config_ref.exists:
                    raise Exception("Configuração de atualização não encontrada no banco (bridge_config/latest). Suba a atualização pelo aplicativo primeiro.")
                
                update_data = config_ref.to_dict()
                download_url = update_data.get('download_url')
                nova_versao = update_data.get('version', 'Desconhecida')
                
                if not download_url:
                    raise Exception("A URL de download não está presente no banco de dados.")
                
                log_message(f"[CMD] Baixando a versão {nova_versao} da nuvem Exodo...")
                
                import requests
                if getattr(sys, 'frozen', False):
                    # Modo Executável
                    target_exe = sys.executable
                    new_exe = target_exe + ".new"
                    
                    r = requests.get(download_url, stream=True, timeout=120)
                    if r.status_code == 200:
                        with open(new_exe, 'wb') as f:
                            for chunk in r.iter_content(chunk_size=8192): 
                                f.write(chunk)
                                
                        bat_path = os.path.join(os.path.dirname(target_exe), "update_bridge.bat")
                        with open(bat_path, "w") as f:
                            # Adicionamos taskkill para o watchdog também para evitar conflitos de arquivo durante o 'move'
                            f.write(f'@echo off\ntimeout /t 3\ntaskkill /F /IM ExodoNfceBridgeWatchdog.exe\ntaskkill /F /PID {os.getpid()}\ntimeout /t 1\nmove /Y "{new_exe}" "{target_exe}"\nstart "" "{target_exe}"\ndel "%~f0"')
                        
                        doc_ref.update({'status': 'concluido', 'resultado': f'Baixado v{nova_versao} com sucesso. Reiniciando para aplicar.', 'sucesso': True})
                        subprocess.Popen([bat_path], shell=True)
                        return
                    else:
                        raise Exception(f"Erro HTTP ao baixar: {r.status_code}")
                else:
                    # Modo Dev/Script
                    raise Exception("A atualização remota agora só suporta arquivos .exe compilados. Em ambiente de script faça git pull manualmente.")
                    
            except Exception as e:
                resultado = f"Falha na atualização: {e}"
                log_message(f"[CMD] {resultado}")
            
            sucesso = False
            if sucesso:
                notify_user("Atualização Concluída", "O sistema foi atualizado com sucesso!")
                # Reiniciar par aplicar
                if not getattr(sys, 'frozen', False):
                    restart_action_silent()
            else:
                log_message(f"[CMD] Falha na atualização: {resultado}", "ERROR")
                notify_user("Falha na Atualização", "Não foi possível baixar ou aplicar. Contate o suporte.")
        
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
            resultado = f"PC: {pc_name} | Empresa: {empresa} | Versão Bridge: {BRIDGE_VERSION} | OS: {os_info}"
            sucesso = True
            notify_user("Sinal Recebido", "A máquina foi identificada remotamente pelo Admin!")
            log_message(f"[CMD] Identificação enviada: {resultado}")

        elif comando == 'set_identity':
            log_message("[CMD] Comando Vincular Empresa recebido.")
            new_cnpj = data.get('cnpj')
            new_nome = data.get('nome')
            if new_cnpj and new_nome:
                LAST_PROCESSED_COMPANY = {
                    "cnpj": new_cnpj,
                    "nome": new_nome,
                    "timestamp": datetime.now().isoformat()
                }
                save_identity()
                resultado = f"Este PC foi VINCULADO à empresa: {new_nome} ({new_cnpj})"
                sucesso = True
                notify_user("Vínculo Realizado", f"Este computador agora pertence à empresa: {new_nome}")
                # Forçar atualização imediata no painel
                _registrar_heartbeat(db)
                log_message(f"[CMD] {resultado}")
            else:
                resultado = "Erro: CNPJ ou Nome da empresa não fornecidos para o vínculo."
                sucesso = False

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
        meipass = getattr(sys, '_MEIPASS', base_path)
        possiveis = [
            os.path.join(base_path, "firebase-credentials.json"),
            os.path.join(meipass, "firebase-credentials.json"),
            os.path.join(base_path, "..", "firebase-credentials.json"),
            "firebase-credentials.json"
        ]
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
        possiveis = [os.path.join(base_path, "firebase-credentials.json"), "firebase-credentials.json"]
    
    cred_file = None
    for p in possiveis:
        if os.path.exists(p):
            cred_file = p
            break
            
    if not cred_file:
        log_message("[ERRO] firebase-credentials.json não encontrado em nenhum dos diretórios esperados.", "ERROR")
        return
            
    try:
        try:
            firebase_admin.get_app()
        except ValueError:
            cred = credentials.Certificate(cred_file)
            firebase_admin.initialize_app(cred)

        db = firestore.client()
        FIREBASE_ACTIVE = True
        log_message("Conexão com Firebase estabelecida. Iniciando listeners...")

        # 1. Listener de Notas Fiscais (Inicia AGORA para já receber pedidos)
        def on_snapshot(col_snapshot, changes, read_time):
            try:
                print(f">>> [DEBUG] Snapshot recebido! {len(changes)} alterações detectadas.")
                global LAST_HEARTBEAT_TS
                import time as _time
                LAST_HEARTBEAT_TS = _time.time()
                
                for change in changes:
                    doc = change.document
                    data = doc.to_dict()
                    if change.type.name == 'ADDED' or (change.type.name == 'MODIFIED' and data.get('status') == 'pendente'):
                        if data.get('status') == 'pendente':
                            log_message(f"🔔 Nova nota recebida: {doc.id}")
                            threading.Thread(
                                target=processar_requisicao_firebase, 
                                args=(db, doc.id, data),
                                daemon=True
                            ).start()
            except Exception as e:
                log_message(f"Erro no snapshot listener: {e}", "ERROR")

        nfce_query = db.collection('nfce_requests').where('status', '==', 'pendente')
        nfce_watch = nfce_query.on_snapshot(on_snapshot)
        
        # 2. Listener de Comandos Remotos
        def on_command_snapshot(col_snapshot, changes, read_time):
            try:
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
            except Exception as e:
                log_message(f"Erro no comando listener: {e}", "ERROR")
        
        cmd_query = db.collection('bridge_commands').where('status', '==', 'pendente')
        cmd_watch = cmd_query.on_snapshot(on_command_snapshot)
        log_message("Listeners de Notas e Comandos ativos!")

        # 3. Registrar heartbeat (Status Online) em PARALELO
        # Isso evita que o app fique travado em "Conectando..." se o Firebase demorar a responder o primeiro sinal
        def _safe_heartbeat_loop():
            import time as _time
            while FIREBASE_ACTIVE:
                try:
                    _registrar_heartbeat(db)
                except Exception as e:
                    print(f"[DEBUG] Erro heartbeat: {e}")
                _time.sleep(60)
        
        threading.Thread(target=_safe_heartbeat_loop, daemon=True).start()

        # 3. WATCHDOG: Garante que os listeners não morram em silêncio
        def _watchdog_loop():
            import time as _time
            nonlocal nfce_watch, cmd_watch
            
            error_count = 0
            while FIREBASE_ACTIVE:
                _time.sleep(300) # Checar a cada 5 minutos
                agora = _time.time()
                # Se não recebemos nada (nem heartbeat interno) em 15 minutos, algo está errado
                if (agora - LAST_HEARTBEAT_TS) > 900: 
                    log_message("[WATCHDOG] Detectada inatividade prolongada. Reiniciando listeners...", "WARN")
                    try:
                        nfce_watch.unsubscribe()
                        cmd_watch.unsubscribe()
                    except: pass
                    
                    # Reiniciar
                    nfce_watch = nfce_query.on_snapshot(on_snapshot)
                    cmd_watch = cmd_query.on_snapshot(on_command_snapshot)
                    LAST_HEARTBEAT_TS = _time.time()
                    log_message("[WATCHDOG] Listeners reiniciados com sucesso.")
        
        threading.Thread(target=_watchdog_loop, daemon=True).start()
        
    except Exception as e:
        log_message(f"Falha ao iniciar Firebase Listener: {e}", "ERROR")
        import traceback
        log_message(traceback.format_exc(), "ERROR")
        FIREBASE_ACTIVE = False
        global FIREBASE_STATUS_MSG
        FIREBASE_STATUS_MSG = "🔴 Falha Crítica / Offline"
        update_tray_menu()

def kill_zombies():
    """Versão passiva: apenas tenta matar o watchdog para não causar suicídio."""
    try:
        log_message("Limpando Watchdog (passivo)...")
        os.system('taskkill /F /IM ExodoNfceBridgeWatchdog* /T >nul 2>&1')
    except: pass

# --- UTILITÁRIOS ---
LAST_HEARTBEAT_TS = time.time()

def _registrar_heartbeat(db):
    """Registra/atualiza o heartbeat do Bridge no Firestore."""
    global LAST_HEARTBEAT_TS, FIREBASE_STATUS_MSG
    try:
        import platform as _plt
        pc_name = _plt.node()
        # Higienizar id do documento
        import re as _re
        doc_id_clean = _re.sub(r'[^a-zA-Z0-9_-]', '_', pc_name) or 'bridge'
        
        LAST_HEARTBEAT_TS = time.time() # Atualiza marca de tempo local

        db.collection('bridge_status').document(doc_id_clean).set({
            'online': True,
            'pc_name': pc_name,
            'last_seen': firestore.SERVER_TIMESTAMP,
            'versao': BRIDGE_VERSION,
            'status_cpu': f"{platform.processor()}",
            'ultima_empresa': LAST_PROCESSED_COMPANY.get('nome'),
            'ultimo_cnpj': LAST_PROCESSED_COMPANY.get('cnpj'),
            'ultimo_processamento': LAST_PROCESSED_COMPANY.get('timestamp')
        }, merge=True)
        log_message(f"Sinal de vida (Heartbeat) enviado com sucesso: {pc_name}")
        
        FIREBASE_STATUS_MSG = "🟢 Conectado e Operacional"
        update_tray_menu()
    except Exception as e:
        err_msg = str(e)
        log_message(f"Falha ao enviar sinal de vida ao servidor: {err_msg}", "WARN")
        if "iat" in err_msg or "Invalid JWT Signature" in err_msg or "expired" in err_msg.lower():
            FIREBASE_STATUS_MSG = "🔴 Erro de Relógio (Hora do Windows Errada)"
            # Tentar sincronizar a hora automaticamente se for admin
            try:
                log_message("Detectado erro de relógio. Tentando sincronizar com servidor NTP...", "WARN")
                os.system('w32tm /resync /force >nul 2>&1')
                # Se falhar, tentar ligar o serviço de hora
                os.system('net start w32time >nul 2>&1')
                os.system('w32tm /resync /force >nul 2>&1')
            except: pass
        elif "403" in err_msg or "Permission" in err_msg:
            FIREBASE_STATUS_MSG = "🔴 Erro de Permissão / Chave Off"
        else:
            FIREBASE_STATUS_MSG = f"🔴 Offline: {err_msg[:20]}..."
        update_tray_menu()

FIREBASE_STATUS_MSG = "🟠 Conectando..."

def update_tray_menu():
    import pystray
    global GLOBAL_TRAY_ICON, FIREBASE_STATUS_MSG, LAST_PROCESSED_COMPANY
    if not GLOBAL_TRAY_ICON: return
    
    empresa_nome = LAST_PROCESSED_COMPANY.get('nome') or "Nenhuma"
    cnpj = LAST_PROCESSED_COMPANY.get('cnpj') or "Aguardando..."
    
    # Atualizar Ícone baseado no Status
    try:
        from PIL import Image
        meipass = getattr(sys, '_MEIPASS', None)
        base_path = get_base_path()
        
        icon_name = "icon_orange.ico"
        if "Conectado" in FIREBASE_STATUS_MSG:
            icon_name = "icon_green.ico"
        elif "Offline" in FIREBASE_STATUS_MSG or "Erro" in FIREBASE_STATUS_MSG:
            icon_name = "icon_red.ico"
            
        full_path = None
        # Busca no MEIPASS primeiro
        if meipass:
            p = os.path.join(meipass, icon_name)
            if os.path.exists(p): full_path = p
            
        if not full_path:
            p = os.path.join(base_path, icon_name)
            if os.path.exists(p): full_path = p
            
        if full_path:
            GLOBAL_TRAY_ICON.icon = Image.open(full_path)
    except: pass

    def quit_app(icon):
        icon.stop()
        os._exit(0)

    menu_items = [
        pystray.MenuItem(f"Versão: {BRIDGE_VERSION}", lambda: None, enabled=False),
        pystray.MenuItem(f"Firebase: {FIREBASE_STATUS_MSG}", lambda: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem(f"Exodo Bridge: {empresa_nome}", lambda: None, enabled=False),
        pystray.MenuItem(f"CNPJ: {cnpj}", lambda: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
        pystray.MenuItem("Sair", lambda icon, item: quit_app(icon))
    ]
    GLOBAL_TRAY_ICON.menu = pystray.Menu(*menu_items)
    
    status_icon = "Ativo" if "Conectado" in FIREBASE_STATUS_MSG else "Falha"
    GLOBAL_TRAY_ICON.title = f"Exodo Bridge v{BRIDGE_VERSION} - ({status_icon})"

def update_local_status():
    if getattr(sys, 'frozen', False):
        base_path = os.path.dirname(sys.executable)
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    status_file = os.path.join(base_path, "STATUS_BRIDGE.txt")
    with open(status_file, "w") as f:
        f.write("=== STATUS DO EMISSOR EXODO ===\n")
        f.write(f"Versão: {BRIDGE_VERSION}\n")
        f.write(f"Última inicialização: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n")
        f.write(f"Porta Local: 8000\n")
        f.write(f"Firebase: ATIVO\n")

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def self_install():
    """Configura o Bridge para iniciar e REINICIAR sozinho no Windows."""
    if not getattr(sys, 'frozen', False): return
    
    # Marcador de instalação para evitar lentidão em todo boot
    install_marker = os.path.join(os.path.dirname(sys.executable), ".installed")
    
    try:
        if os.path.exists(install_marker):
            with open(install_marker, "r") as f:
                if f.read().strip() == BRIDGE_VERSION:
                    return # Já está instalado nesta versão
    except: pass

    log_message(f"Instalando/Atualizando serviços de inicialização (v{BRIDGE_VERSION})...")

    exe_path = os.path.abspath(sys.executable)
    task_name = "ExodoNfceBridgeTask"
    
    # 1. TENTAR TAREFA AGENDADA (Robusta - Reinicia se Fechar)
    try:
        # 1.1 TAREFA DO BRIDGE (Início no Logon)
        subprocess.run(['schtasks', '/delete', '/tn', task_name, '/f'], 
                      capture_output=True, creationflags=0x08000000)
        
        cmd = [
            'schtasks', '/create', '/tn', task_name, 
            '/tr', f'"{exe_path}" --silent', 
            '/sc', 'onlogon'
        ]
        if is_admin(): cmd += ['/rl', 'highest']
        subprocess.run(cmd + ['/f'], capture_output=True, text=True, creationflags=0x08000000)

        # 1.2 TAREFA DO WATCHDOG
        watchdog_exe = os.path.join(os.path.dirname(exe_path), "ExodoNfceBridgeWatchdog.exe")
        watchdog_task = "ExodoNfceBridgeWatchdog"

        if os.path.exists(watchdog_exe):
            subprocess.run(['schtasks', '/delete', '/tn', watchdog_task, '/f'], 
                          capture_output=True, creationflags=0x08000000)
            
            cmd_watch = ['schtasks', '/create', '/tn', watchdog_task, '/tr', f'"{watchdog_exe}"', '/sc', 'onlogon']
            if is_admin(): cmd_watch += ['/rl', 'highest']
            subprocess.run(cmd_watch + ['/f'], capture_output=True, text=True, creationflags=0x08000000)

        # Criar marcador para não repetir isso todo boot
        with open(install_marker, "w") as f: f.write(BRIDGE_VERSION)
        log_message(f"Sistema de auto-inicialização configurado.")
    except Exception as e:
        log_message(f"Falha ao configurar inicialização: {e}", "WARN")

    # 2. FALLBACK: REGISTRO RUN (Apenas Início com Windows)
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, "ExodoNfceBridge", 0, winreg.REG_SZ, f'"{exe_path}" --silent')
        winreg.CloseKey(key)
        log_message(f"Proteção básica ativa no Registro: {exe_path}")
    except Exception as e:
        log_message(f"Erro ao configurar inicialização básica: {e}", "ERROR")

    # 3. TRIPLE FALLBACK: PASTA INICIALIZAR (STARTUP FOLDER)
    try:
        startup_path = os.path.join(os.environ['APPDATA'], r"Microsoft\Windows\Start Menu\Programs\Startup")
        shortcut_path = os.path.join(startup_path, "ExodoNfceBridge.bat")
        # Cria um arquivo .bat simples que aponta para o exe
        with open(shortcut_path, "w") as f:
            f.write(f'@echo off\nstart "" "{exe_path}" --silent')
        log_message(f"Atalho de inicialização criado na pasta Startup.")
    except Exception as e:
        log_message(f"Erro ao criar atalho na pasta Startup: {e}", "WARN")

# --- TRAY ICON ---
def restart_action_silent():
    if getattr(sys, 'frozen', False):
        subprocess.Popen([sys.executable, "--silent"])
    else:
        subprocess.Popen([sys.executable] + sys.argv + ["--silent"])
    subprocess.run(["taskkill", "/F", "/PID", str(os.getpid())], creationflags=0x08000000)

def setup_tray():
    import pystray
    from PIL import Image
    
    # Prioridade para arquivos internos (MEIPASS) se estiver compilado
    meipass = getattr(sys, '_MEIPASS', None)
    base_path = get_base_path()
    
    def find_icon(name):
        # 1. Tenta no MEIPASS (interno ao EXE)
        if meipass:
            p = os.path.join(meipass, name)
            if os.path.exists(p): return p
        # 2. Tenta na pasta do executável
        p = os.path.join(base_path, name)
        if os.path.exists(p): return p
        return None

    icon_file = find_icon("icon_orange.ico")
    
    if icon_file:
        try:
            log_message(f"Usando arquivo de ícone: {icon_file}")
            image = Image.open(icon_file)
        except Exception as e:
            log_message(f"Erro ao abrir ícone {icon_file}: {e}. Usando fallback.", "WARN")
            icon_file = None
    
    if not icon_file:
        log_message("Usando fallback de desenho para o ícone da bandeja.")
        # Fallback se o arquivo não existir
        from PIL import ImageDraw
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

    import secrets
    icon_id = f"exodo_bridge_{secrets.token_hex(2)}"
    icon = pystray.Icon(icon_id, image, f"Exodo Bridge v{BRIDGE_VERSION}")
    
    menu_items = [
        pystray.MenuItem(f"Versão: {BRIDGE_VERSION}", lambda: None, enabled=False),
        pystray.MenuItem(f"Firebase: {FIREBASE_STATUS_MSG}", lambda: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem(f"Aguardando empresa...", lambda: None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Reiniciar Serviço", lambda icon, item: restart_action_silent()),
        pystray.MenuItem("Sair", lambda icon, item: quit_app(icon))
    ]
    icon.menu = pystray.Menu(*menu_items)
    return icon

def run_server():
    try:
        log_message("Iniciando Uvicorn...")
        # log_config=None usa o padrão do uvicorn, o que evita erros de formatação no PyInstaller
        uvicorn.run(app, host="0.0.0.0", port=8000, log_config=None, reload=False, workers=1)
    except Exception as e:
        log_message(f"ERRO CRÍTICO NO SERVIDOR HTTP: {e}", "ERROR")
        # Se falhar a porta 8000, o sistema continuará funcionando via Firebase
        # Não encerramos o app aqui.

GLOBAL_TRAY_ICON = None

def notify_user(title, message):
    try:
        if GLOBAL_TRAY_ICON:
            GLOBAL_TRAY_ICON.notify(message, title=title)
    except Exception as e:
        print(f"Erro notificação: {e}")

def run_background_tasks():
    """Roda as tarefas pesadas (Firebase, Servidor, Instalação, Cleanup) em segundo plano."""
    try:
        # 1. Limpeza de processos antigos (Zumbis)
        # Rodamos aqui para o ícone sumir das instâncias velhas enquanto este sobe
        if getattr(sys, 'frozen', False):
            kill_zombies()

        # 2. Configurações de sistema (Auto-start)
        if getattr(sys, 'frozen', False):
            self_install()
            
        # 3. Iniciar Firebase (Conexão de rede)
        log_message("Conectando ao Firebase em segundo plano...")
        start_firebase_listener()
        
        # 4. Iniciar Servidor HTTP
        run_server()
    except Exception as e:
        log_message(f"Erro nas tarefas de background: {e}", "ERROR")

if __name__ == "__main__":
    multiprocessing.freeze_support()
    log_message(">>> INICIO DO PROCESSO PRINCIPAL <<<")
    
    # 1. Iniciar as tarefas pesadas (incluindo limpeza) em Thread separada
    bg_thread = threading.Thread(target=run_background_tasks, daemon=True, name="BgInitThread")
    bg_thread.start()
    
    # 2. Subir a Interface de Bandeja IMEDIATAMENTE (Não bloqueia o início)
    try:
        log_message("Subindo ícone da bandeja...")
        GLOBAL_TRAY_ICON = setup_tray()
        if GLOBAL_TRAY_ICON:
            GLOBAL_TRAY_ICON.run()
        else:
            log_message("Falha ao criar ícone da bandeja", "ERROR")
            while True: time.sleep(60)
    except Exception as e:
        log_message(f"Erro fatal na interface da bandeja: {e}", "ERROR")
        # Se a bandeja falhar, manter o processo vivo em loop
        while True:
            time.sleep(60)

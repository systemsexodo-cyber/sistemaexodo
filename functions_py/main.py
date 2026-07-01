from firebase_functions import https_fn
from firebase_admin import initialize_app, firestore
import json
from datetime import datetime
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import os
import sys

# Adicionar o diretório atual ao path para importar o nfce_handler
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from nfce_handler import emitir_nfce_pynfe, cancelar_nfce_pynfe, consultar_nfce_pynfe, validar_certificado_pynfe

# Inicializar Firebase Admin
initialize_app()

app = FastAPI()

# Configurar CORS para permitir chamadas do seu app Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- MODELOS DE DADOS ---

class ConfigEmpresa(BaseModel):
    id: Optional[str] = None
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
    crt: Optional[str] = "1"
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
    icms_origem: Optional[int] = 0
    icms_aliquota: Optional[float] = 0.0

class RequisicaoEmissao(BaseModel):
    empresa: ConfigEmpresa
    itens: List[ItemVenda]
    valor_total: float
    venda_numero: Optional[str] = None
    cpf_cliente: Optional[str] = None

# --- ENDPOINTS ---

@app.post("/emitir")
async def emitir(req: RequisicaoEmissao):
    try:
        resultado = emitir_nfce_pynfe(req)
        return resultado
    except Exception as e:
        return {"status": "erro", "mensagem": str(e)}

@app.post("/cancelar")
async def cancelar(req: Request):
    try:
        data = await req.json()
        resultado = cancelar_nfce_pynfe(data)
        return resultado
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/health")
async def health():
    return {
        "status": "online", 
        "service": "Exodo NFCE Cloud Bridge",
        "version": "3.4.6-cloud",
        "timestamp": datetime.now().isoformat()
    }

# Exportar para o Firebase Functions
@https_fn.on_request(region="us-central1", memory=512)
def api(req: https_fn.Request) -> https_fn.Response:
    with https_fn.as_fastapi(app) as (app_handler):
        return app_handler(req)

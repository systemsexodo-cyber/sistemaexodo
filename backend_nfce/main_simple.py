#!/usr/bin/env python3
"""
Bridge NFC-e - Versão SIMPLIFICADA (apenas HTTP)
Sem Firebase, sem bandeja, sem ícones - apenas o servidor HTTP
"""

import os
import sys
import json
import logging
from datetime import datetime

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Adicionar caminhos
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from fastapi import FastAPI, HTTPException
    from fastapi.middleware.cors import CORSMiddleware
    from pydantic import BaseModel
    from typing import List, Optional
    import uvicorn
    logger.info("✅ FastAPI/Uvicorn importados com sucesso")
except ImportError as e:
    logger.error(f"❌ Erro ao importar dependências: {e}")
    logger.error("Instale com: pip install fastapi uvicorn pydantic")
    sys.exit(1)

# Importar handler de NFC-e
try:
    from nfce_handler import emitir_nfce_pynfe
    logger.info("✅ nfce_handler importado")
except Exception as e:
    logger.error(f"❌ Erro ao importar nfce_handler: {e}")
    emitir_nfce_pynfe = None

# Criar app FastAPI
app = FastAPI(
    title="Bridge NFC-e - Modo Simples",
    description="Versão simplificada sem Firebase/bandeja",
    version="3.5.1-simple"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Modelos
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

class RequisicaoEmissao(BaseModel):
    empresa: ConfigEmpresa
    itens: List[ItemVenda]
    valor_total: float
    venda_numero: Optional[str | int] = None
    cpf_cliente: Optional[str] = None

# Endpoints
@app.get("/")
async def root():
    return {
        "status": "online",
        "modo": "simples (sem firebase)",
        "version": "3.5.1-simple",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
async def health():
    return {"status": "ok", "nfce_handler": "disponivel" if emitir_nfce_pynfe else "indisponivel"}

@app.post("/api/nfce/emitir")
async def emitir_nfce_endpoint(req: RequisicaoEmissao):
    if not emitir_nfce_pynfe:
        raise HTTPException(status_code=503, detail="NFC-e handler não disponível")
    
    try:
        resultado = emitir_nfce_pynfe(req)
        logger.info(f"✅ NFC-e emitida: {resultado.get('numero', 'N/A')}")
        return resultado
    except Exception as e:
        logger.error(f"❌ Erro ao emitir NFC-e: {e}")
        import traceback
        raise HTTPException(status_code=500, detail=f"{str(e)}\n\n{traceback.format_exc()}")

@app.get("/api/nfce/status/{chave}")
async def consultar_status(chave: str):
    """Consulta status de NFC-e na SEFAZ"""
    return {"status": "implementacao_pendente", "chave": chave}

def main():
    print("""
╔══════════════════════════════════════════════════════════╗
║     BRIDGE NFC-e - VERSÃO SIMPLIFICADA (APENAS HTTP)     ║
╠══════════════════════════════════════════════════════════╣
║  URL: http://localhost:8000                              ║
║  Health: http://localhost:8000/health                    ║
║  Modo: SEM Firebase, SEM bandeja, APENAS HTTP              ║
╚══════════════════════════════════════════════════════════╝
""")
    
    uvicorn.run(
        "main_simple:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )

if __name__ == "__main__":
    main()

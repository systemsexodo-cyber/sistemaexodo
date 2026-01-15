from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uvicorn
# from nfce_handler import emitir_nfce_pynfe  # Será implementado a seguir

app = FastAPI(title="API Emissao NFC-e PyNFe")

# Modelos de Dados (Espelham o que o Flutter vai mandar)
class ItemVenda(BaseModel):
    codigo: str
    descricao: str
    ncm: str
    cfop: str
    quantidade: float
    valor_unitario: float
    valor_total: float

class Venda(BaseModel):
    numero: int
    data_emissao: str
    cpf_cliente: Optional[str] = None
    itens: List[ItemVenda]
    valor_total: float
    valor_desconto: float = 0.0

@app.get("/")
def read_root():
    return {"status": "online", "message": "Backend NFC-e com PyNFe rodando"}

@app.post("/emitir_nfce")
def emitir_nfce_endpoint(venda: Venda):
    try:
        # Aqui chamaremos a função do PyNFe
        # resultado = emitir_nfce_pynfe(venda)
        
        # Mock de resposta por enquanto
        return {
            "status": "sucesso",
            "chave_acesso": "41230112345678000123650010000000011000000010",
            "protocolo": "141230000000000",
            "xml_url": "http://localhost:8000/xml/nota_1.xml",
            "mensagem": "Nota emitida com sucesso (Simulação)"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)

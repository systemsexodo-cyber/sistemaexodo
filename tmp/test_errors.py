from typing import List, Optional
from pydantic import BaseModel

class ConfigEmpresa(BaseModel):
    ambiente: int = 2
    cnpj: str
    razao_social: str = ""
    certificado_base64: str = ""
    senha_certificado: str = ""
    uf: str = ""

class ItemVenda(BaseModel):
    codigo: str
    descricao: str
    quantidade: float
    valor_unitario: float
    valor_total: float

class RequisicaoEmissao(BaseModel):
    empresa: ConfigEmpresa
    itens: List[ItemVenda]
    valor_total: float
    venda_numero: Optional[int] = 0

print("Testando Pydantic com 'N' em venda_numero...")
try:
    data = {
        "empresa": {"cnpj": "000", "ambiente": 2},
        "itens": [],
        "valor_total": 0.0,
        "venda_numero": "N"
    }
    req = RequisicaoEmissao(**data)
except Exception as e:
    print(f"Erro Pydantic: {e}")

print("\nTestando int('N'|'None'|'null')...")
try:
    int('N')
except Exception as e:
    print(f"int('N') -> {e}")

try:
    int('None')
except Exception as e:
    print(f"int('None') -> {e}")

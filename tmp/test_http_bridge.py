import requests
import json
import base64

# Mock data
payload = {
    "empresa": {
        "cnpj": "04829400000165",
        "razao_social": "BMJ PETSHOP",
        "uf": "SP",
        "certificado_base64": "dummy",
        "senha_certificado": "dummy",
        "ambiente": 2
    },
    "itens": [
        {
            "codigo": "123",
            "descricao": "PRODUTO TESTE",
            "quantidade": 1.0,
            "valor_unitario": 10.0,
            "valor_total": 10.0
        }
    ],
    "valor_total": 10.0,
    "venda_numero": 1
}

try:
    response = requests.post("http://localhost:8000/emitir", json=payload, timeout=10)
    print(f"Status: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Erro: {e}")

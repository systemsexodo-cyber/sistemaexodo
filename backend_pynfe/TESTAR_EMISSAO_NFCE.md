# 🧪 Como Testar Emissão de NFC-e com PyNFe/nfelib

## 📋 Pré-requisitos

1. ✅ Python 3.8+ instalado
2. ✅ Certificado digital A1 (.pfx) com senha
3. ✅ Dados da empresa configurados no sistema Flutter
4. ✅ Backend Python rodando

## 🚀 Passo a Passo

### 1. Instalar Dependências

```bash
cd backend_pynfe
pip install -r requirements.txt
pip install nfelib signxml cryptography flask flask-cors python-dotenv
```

### 2. Iniciar o Servidor Backend

**Opção A: Usando script batch (Windows)**
```bash
start_local.bat
```

**Opção B: Manualmente**
```bash
cd backend_pynfe
python app.py
```

O servidor iniciará em: `http://localhost:5000`

### 3. Verificar se o Servidor Está Funcionando

Abra no navegador ou use curl:
```bash
curl http://localhost:5000/health
```

Deve retornar:
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando",
  "local": true,
  "pynfe_disponivel": true
}
```

### 4. Configurar URL do Backend no Flutter

O Flutter já está configurado para usar `http://localhost:5000` por padrão.

**Para Android Emulator**, você precisa alterar para `http://10.0.2.2:5000`:
- Edite `lib/services/nfce_backend_service.dart`
- Altere `_getDefaultUrl()` para retornar `'http://10.0.2.2:5000'`

**Para dispositivo físico**, use o IP da sua máquina:
- Exemplo: `'http://192.168.1.100:5000'`

### 5. Testar Emissão pelo Flutter

1. Abra o sistema Flutter
2. Vá para o PDV (Venda Direta)
3. Adicione produtos ao carrinho
4. Clique em "FINALIZAR"
5. Clique em "Emitir NFC-e"

### 6. Verificar Logs

O servidor Python mostrará logs detalhados no terminal:
- ✅ Preparação do certificado
- ✅ Geração do XML
- ✅ Assinatura digital
- ✅ Envio para SEFAZ
- ✅ Resposta da SEFAZ

## 🔍 Troubleshooting

### Erro: "nfelib não está instalado"

```bash
pip install nfelib signxml cryptography
```

### Erro: "Backend não está disponível"

1. Verifique se o servidor está rodando: `http://localhost:5000/health`
2. Verifique se a porta 5000 está livre
3. Verifique firewall/antivírus

### Erro: "Certificado digital não fornecido"

1. Verifique se o certificado está configurado na empresa
2. Verifique se a senha está correta
3. Verifique se o certificado está em base64

### Erro: "Connection refused" (Android)

- Use `10.0.2.2:5000` em vez de `localhost:5000`
- Ou use o IP da máquina no dispositivo físico

## 📝 Exemplo de Teste Manual (Python)

```python
import requests
import json

# Dados de teste
data = {
    "empresa": {
        "cnpj": "12345678000190",
        "razao_social": "EMPRESA TESTE LTDA",
        "uf": "PR",
        "codigo_municipio_ibge": "4118402",
        "certificado_base64": "SEU_CERTIFICADO_BASE64",
        "senhaCertificado": "SUA_SENHA",
        "ambienteHomologacao": True
    },
    "produtos": [
        {
            "codigo": "PROD001",
            "descricao": "Produto Teste",
            "ncm": "00000000",
            "cfop": "5102",
            "quantidade": 1.0,
            "valorUnitario": 10.00,
            "valorTotal": 10.00
        }
    ],
    "pagamentos": [
        {"tipo": "01", "valor": 10.00}  # 01 = Dinheiro
    ]
}

# Fazer requisição
response = requests.post(
    'http://localhost:5000/api/nfce/emitir',
    json=data,
    headers={'Content-Type': 'application/json'}
)

print(response.json())
```

## ✅ Checklist

- [ ] Python 3.8+ instalado
- [ ] Dependências instaladas (`nfelib`, `signxml`, `cryptography`)
- [ ] Servidor backend rodando (`python app.py`)
- [ ] Health check funcionando (`/health`)
- [ ] Certificado digital configurado na empresa
- [ ] URL do backend configurada no Flutter
- [ ] Ambiente de homologação configurado

## 🎯 Próximos Passos

Após testar com sucesso:
1. Configurar ambiente de produção
2. Configurar certificado de produção
3. Testar com dados reais
4. Verificar numeração sequencial
5. Configurar backup de NFC-e emitidas










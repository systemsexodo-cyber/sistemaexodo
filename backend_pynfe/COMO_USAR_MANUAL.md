# 🔧 COMO USAR - SOLUÇÃO 100% LOCAL (SEM APIs)

## ✅ O que esta solução faz

Esta solução é **100% LOCAL** e faz TUDO no seu código:

1. ✅ **Gera o XML** da NFC-e manualmente
2. ✅ **Assina o XML** usando `cryptography` (sem signxml problemático)
3. ✅ **Envia para SEFAZ** usando `zeep` (SOAP)
4. ✅ **Processa a resposta** e retorna o resultado

**SEM APIs de terceiros! Tudo no seu código!**

## 📋 Passo a Passo

### **1. Instalar Dependências**

```bash
cd backend_pynfe
.\instalar_manual.bat
```

Ou manualmente:
```bash
pip install Flask Flask-CORS python-dotenv lxml cryptography zeep
```

### **2. Iniciar Servidor**

```bash
python app_manual.py
```

### **3. Emitir NFC-e**

**URL:** `POST http://localhost:5000/api/nfce/emitir`

**Exemplo de requisição:**
```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "razao_social": "Empresa Teste LTDA",
    "nome_fantasia": "Teste",
    "inscricao_estadual": "123456789",
    "codigo_municipio_ibge": "3550308",
    "uf": "SP",
    "crt": "3",
    "numero_nfce": 1,
    "serie_nfce": 1,
    "endereco": {
      "logradouro": "Rua Teste",
      "numero": "123",
      "bairro": "Centro",
      "cidade": "São Paulo",
      "cep": "01000-000"
    },
    "telefone": "11999999999",
    "certificado_base64": "BASE64_DO_CERTIFICADO_PFX",
    "senha_certificado": "senha123",
    "ambiente_homologacao": true
  },
  "produtos": [
    {
      "codigo": "001",
      "descricao": "Produto Teste",
      "ncm": "21069090",
      "cfop": "5102",
      "unidade": "UN",
      "quantidade": 1.0,
      "valor_unitario": 10.00,
      "valor_total": 10.00,
      "icms": {
        "origem": "0",
        "cst": "102",
        "aliquota": 0.0
      }
    }
  ],
  "pagamentos": [
    {
      "tipo": "01",
      "valor": 10.00
    }
  ],
  "consumidor": {
    "nome": "CONSUMIDOR FINAL"
  }
}
```

## 🎯 Vantagens

1. ✅ **100% Local** - funciona no seu servidor
2. ✅ **Sem APIs pagas** - não depende de serviços externos
3. ✅ **Controle total** - você vê todo o código
4. ✅ **Bibliotecas estáveis** - `cryptography`, `lxml`, `zeep`
5. ✅ **Sem signxml** - usa apenas `cryptography` para assinatura

## 📋 Requisitos

- Python 3.7+
- Certificado digital A1 (.pfx)
- Senha do certificado
- Dados da empresa e produtos
- Número sequencial da NFC-e (você controla)

## 🔧 Como funciona

1. **Geração de XML**: O código monta o XML conforme layout oficial da SEFAZ
2. **Assinatura**: Usa `cryptography` para assinar com RSA-SHA1
3. **Envio SEFAZ**: Usa `zeep` para comunicação SOAP
4. **Processamento**: Parse da resposta e retorno do resultado

---

**Esta é a solução 100% LOCAL que você pediu!** 🚀





















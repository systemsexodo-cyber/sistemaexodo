# 🆓 COMO USAR PyTrustNFe - SOLUÇÃO 100% GRATUITA

## ✅ Por que PyTrustNFe?

- ✅ **100% GRATUITO** - biblioteca open source
- ✅ **Funciona localmente** - sem APIs pagas
- ✅ **Tudo no seu código** - controle total
- ✅ **Mais simples** que nfelib+signxml
- ✅ **Focada em NFC-e** - especializada

## 📋 Passo a Passo

### **1. Instalar Dependências**

```bash
cd backend_pynfe
.\instalar_gratuito.bat
```

Ou manualmente:
```bash
pip install Flask Flask-CORS python-dotenv requests lxml zeep PyTrustNFe
```

### **2. Iniciar Servidor**

```bash
python app_gratuito.py
```

### **3. Usar o Endpoint**

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

1. ✅ **100% Gratuito** - sem custos
2. ✅ **Funciona localmente** - sem depender de serviços externos
3. ✅ **Controle total** - tudo no seu código
4. ✅ **Mais simples** - PyTrustNFe cuida de XML e assinatura
5. ✅ **Open source** - código aberto

## 📚 Documentação PyTrustNFe

- GitHub: https://github.com/pytrustnfe/pytrustnfe
- PyPI: https://pypi.org/project/PyTrustNFe/

---

**Esta é a solução GRATUITA e SIMPLES!** 🚀





















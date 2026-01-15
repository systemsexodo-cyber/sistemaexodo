# 🚀 COMO USAR Focus NFe API - SOLUÇÃO MAIS SIMPLES

## ✅ Por que Focus NFe API?

- ✅ **MUITO MAIS SIMPLES** - apenas chamadas HTTP
- ✅ Não precisa lidar com certificados, assinatura XML, etc
- ✅ Ambiente de homologação **GRATUITO**
- ✅ Documentação excelente
- ✅ A API faz TUDO para você!

## 📋 Passo a Passo

### **1. Criar Conta na Focus NFe**

1. Acesse: https://focusnfe.com.br
2. Clique em "Criar Conta"
3. Faça cadastro (tem plano gratuito para testes)
4. Após login, vá em "Tokens" e copie seu token

### **2. Configurar Token**

Crie um arquivo `.env` na pasta `backend_pynfe`:

```env
FOCUSNFE_TOKEN=seu_token_aqui
```

Ou configure como variável de ambiente:
```bash
export FOCUSNFE_TOKEN=seu_token_aqui
```

### **3. Instalar Dependências**

```bash
cd backend_pynfe
.\instalar_focus_simples.bat
```

Ou manualmente:
```bash
pip install Flask Flask-CORS python-dotenv requests
```

### **4. Iniciar Servidor**

```bash
python app_simples_focus.py
```

### **5. Testar Emissão**

O servidor estará rodando em: `http://localhost:5000`

**Endpoint:** `POST /api/nfce/emitir`

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

1. **Não precisa de certificado digital** - a API cuida disso
2. **Não precisa assinar XML** - a API faz tudo
3. **Não precisa lidar com SOAP** - apenas REST simples
4. **Ambiente de homologação gratuito** - pode testar à vontade
5. **Documentação completa** - https://doc.focusnfe.com.br

## 💰 Preços

- **Homologação:** GRATUITO
- **Produção:** Pago (consulte planos em https://focusnfe.com.br/precos)

## 📚 Documentação Completa

https://doc.focusnfe.com.br/nfce

---

**Esta é a forma MAIS FÁCIL de emitir NFC-e!** 🚀





















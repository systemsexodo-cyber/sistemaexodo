# 🚀 SISTEMA COMPLETO DE EMISSÃO NFC-e

## ✅ Características

- ✅ **100% Local** - funciona no seu servidor
- ✅ **Produção e Homologação** - suporta ambos os ambientes
- ✅ **Sem APIs de terceiros** - tudo no seu código
- ✅ **Bibliotecas estáveis** - `lxml`, `cryptography`, `zeep`
- ✅ **Fácil de usar** - API REST simples

## 📋 O que o sistema faz

1. **Gera XML** da NFC-e conforme layout oficial da SEFAZ
2. **Assina digitalmente** usando certificado A1 (.pfx)
3. **Envia para SEFAZ** via SOAP
4. **Processa resposta** e retorna resultado

## 🚀 Instalação

```bash
cd backend_pynfe
.\instalar_completo.bat
```

Ou manualmente:
```bash
pip install Flask Flask-CORS lxml zeep cryptography
```

## 🎯 Como Usar

### 1. Iniciar Servidor

```bash
python app_nfce_completo.py
```

### 2. Emitir NFC-e

**Endpoint:** `POST http://localhost:5000/api/nfce/emitir`

**Exemplo de requisição:**

```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "razaoSocial": "Empresa Teste LTDA",
    "nomeFantasia": "Teste",
    "inscricaoEstadual": "123456789",
    "codigoIBGE": "3550308",
    "uf": "SP",
    "endereco": "Rua Teste",
    "numero": "123",
    "bairro": "Centro",
    "cidade": "São Paulo",
    "cep": "01000-000",
    "telefone": "11999999999",
    "crt": 3,
    "serie_nfce": 1,
    "ambienteHomologacao": true,
    "certificado_base64": "BASE64_DO_CERTIFICADO_PFX",
    "senhaCertificado": "senha123"
  },
  "produtos": [
    {
      "codigo": "001",
      "descricao": "Produto Teste",
      "ncm": "21069090",
      "cfop": "5102",
      "unidade": "UN",
      "quantidade": 1.0,
      "valorUnitario": 10.00,
      "valorTotal": 10.00,
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
  },
  "numero_nfce": 1
}
```

## 📋 Dados Obrigatórios da Empresa

- `cnpj` - CNPJ da empresa (14 dígitos)
- `razaoSocial` - Razão social
- `nomeFantasia` - Nome fantasia
- `inscricaoEstadual` - Inscrição estadual
- `codigoIBGE` - Código IBGE do município (7 dígitos)
- `uf` - Estado (SP, RJ, MG, etc)
- `endereco` - Logradouro
- `numero` - Número
- `bairro` - Bairro
- `cidade` - Cidade
- `cep` - CEP
- `telefone` - Telefone
- `crt` - Código de Regime Tributário (1, 2 ou 3)
- `serie_nfce` - Série da NFC-e (geralmente 1)
- `ambienteHomologacao` - true para homologação, false para produção
- `certificado_base64` - Certificado digital em base64 (.pfx)
- `senhaCertificado` - Senha do certificado

## 🎯 Estados Suportados

O sistema suporta todos os estados que usam SVRS (Serviço Virtual da Receita Estadual) e tem suporte específico para:
- SP (São Paulo)
- RJ (Rio de Janeiro)
- MG (Minas Gerais)
- PR (Paraná)
- RS (Rio Grande do Sul)
- SC (Santa Catarina)
- BA (Bahia)
- GO (Goiás)
- DF (Distrito Federal)

Outros estados usam SVRS automaticamente.

## 📝 Formas de Pagamento

- `01` - Dinheiro
- `02` - Cheque
- `03` - Cartão de Crédito
- `04` - Cartão de Débito
- `05` - Crédito Loja
- `10` - Vale Alimentação
- `11` - Vale Refeição
- `12` - Vale Presente
- `13` - Vale Combustível
- `99` - Outros (PIX)

## ✅ Resposta de Sucesso

```json
{
  "success": true,
  "autorizada": true,
  "status": "autorizada",
  "chave_acesso": "35240112345678000190650000000000012345678901",
  "protocolo": "123456789012345",
  "mensagem": "Autorizado o uso da NF-e",
  "xml": "..."
}
```

## ❌ Resposta de Erro

```json
{
  "success": false,
  "autorizada": false,
  "status": "rejeitada",
  "error": "Mensagem de erro da SEFAZ",
  "codigo_erro": "225",
  "error_type": "SEFAZRejection"
}
```

## 🔧 Estrutura do Código

- `nfce_completo.py` - Classe principal com toda a lógica
- `app_nfce_completo.py` - API REST Flask
- `requirements_completo.txt` - Dependências
- `instalar_completo.bat` - Script de instalação

## 📚 Documentação

O código está bem documentado e comentado. Cada método explica o que faz.

---

**Sistema completo e pronto para uso em produção!** 🚀





















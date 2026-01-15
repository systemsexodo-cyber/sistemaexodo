# Backend PHP para Emissão de NFC-e

Backend PHP usando a biblioteca [SPED-NFe](https://github.com/nfephp-org/sped-nfe) para emissão de NFC-e.

## 📋 Requisitos

- PHP 7.4 ou superior (recomendado PHP 8.0+)
- Composer
- Extensões PHP:
  - ext-curl
  - ext-dom
  - ext-json
  - ext-mbstring
  - ext-openssl
  - ext-soap
  - ext-xml
  - ext-zip

## 🚀 Instalação

### 1. Instalar dependências

```bash
cd backend_php
composer install
```

### 2. Configurar variáveis de ambiente

```bash
cp .env.example .env
# Edite o .env conforme necessário
```

### 3. Configurar servidor web

#### Usando PHP Built-in Server (desenvolvimento)

```bash
php -S localhost:8000 -t .
```

#### Usando Apache

Certifique-se de que o módulo `mod_rewrite` está habilitado e que o `.htaccess` está funcionando.

#### Usando Nginx

Configure o servidor para redirecionar todas as requisições para `index.php`:

```nginx
location / {
    try_files $uri $uri/ /index.php?$query_string;
}
```

## 📡 Endpoints

### Health Check

```http
GET /health
```

**Resposta:**
```json
{
    "status": "ok",
    "message": "Backend PHP NFC-e está funcionando",
    "backend": "php",
    "library": "sped-nfe",
    "version": "5.0"
}
```

### Emitir NFC-e

```http
POST /api/nfce/emitir
Content-Type: application/json
```

**Body:**
```json
{
    "empresa": {
        "id": "1",
        "cnpj": "12345678000190",
        "razao_social": "Empresa Teste LTDA",
        "nome_fantasia": "Empresa Teste",
        "inscricao_estadual": "123456789",
        "uf": "SP",
        "codigo_municipio_ibge": "3550308",
        "serie_nfce": "1",
        "ambienteHomologacao": true,
        "certificado_base64": "...",
        "senhaCertificado": "...",
        "endereco": {
            "logradouro": "Rua Teste",
            "numero": "123",
            "bairro": "Centro",
            "cidade": "São Paulo",
            "cep": "01234567"
        }
    },
    "produtos": [
        {
            "id": "1",
            "codigo": "001",
            "nome": "Produto Teste",
            "ncm": "12345678",
            "cfop": "5102",
            "unidade": "UN",
            "quantidade": 1,
            "preco": 10.00
        }
    ],
    "pagamentos": [
        {
            "tipo": "dinheiro",
            "valor": 10.00
        }
    ],
    "consumidor": {
        "cpf": "12345678900",
        "nome": "Consumidor Teste"
    },
    "observacoes": "Observações da venda",
    "numero_nfce": 1
}
```

**Resposta (Sucesso):**
```json
{
    "success": true,
    "autorizada": true,
    "chave": "35251142417114000181550010000000123456789012",
    "protocolo": "123456789012345",
    "numero": 1,
    "qr_code": "https://nfce.sefaz.sp.gov.br/qrCode?p=35251142417114000181550010000000123456789012",
    "xml": "...",
    "xml_retorno": "...",
    "status": "autorizada"
}
```

**Resposta (Erro):**
```json
{
    "success": false,
    "autorizada": false,
    "error": "Mensagem de erro",
    "codigo_erro": "000",
    "status": "rejeitada"
}
```

## 🔧 Integração com Flutter

O serviço Flutter (`lib/services/nfce_backend_service.dart`) pode ser configurado para usar este backend PHP:

```dart
// Em nfce_backend_service.dart, altere a URL:
NFCeBackendService(baseUrl: 'http://localhost:8000')
```

## 📁 Estrutura de Arquivos

```
backend_php/
├── src/
│   ├── App.php              # Classe principal da aplicação
│   ├── Router.php           # Roteador de requisições
│   └── Services/
│       └── NFCeService.php  # Serviço de emissão de NFC-e
├── storage/
│   ├── certs/               # Certificados temporários
│   └── xml/                 # XMLs salvos (organizados por empresa)
├── logs/                    # Logs da aplicação
├── composer.json            # Dependências
├── index.php                # Ponto de entrada
├── .htaccess               # Configuração Apache
└── README.md               # Este arquivo
```

## 🔒 Segurança

- Certificados são processados em memória e arquivos temporários são removidos
- XMLs são salvos apenas após autorização
- Logs não contêm informações sensíveis (senhas, certificados)
- CORS configurável via `.env`

## 📝 Logs

Logs são salvos em `logs/app.log` com diferentes níveis:
- DEBUG: Informações detalhadas
- INFO: Operações importantes
- ERROR: Erros e exceções

## 🐛 Troubleshooting

### Erro: "Class 'NFePHP\NFe\Make' not found"

Execute:
```bash
composer install
```

### Erro: "Certificate read error"

Verifique:
- Certificado está em base64 válido
- Senha do certificado está correta
- Certificado está no formato PFX/PKCS12

### Erro: "CORS"

Configure CORS no `.htaccess` ou no `.env`:

```env
CORS_ORIGINS=http://localhost:5000,https://seu-dominio.com
```

## 📚 Documentação SPED-NFe

Documentação completa da biblioteca: https://github.com/nfephp-org/sped-nfe












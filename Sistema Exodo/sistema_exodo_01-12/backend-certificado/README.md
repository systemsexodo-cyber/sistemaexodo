# Backend para Processamento de Certificados PKCS12

Este backend processa certificados PKCS12 (.pfx) que não podem ser processados pela biblioteca `asn1lib` no Flutter.

## Instalação

1. Certifique-se de ter Node.js instalado (versão 14 ou superior)

2. Instale as dependências:
```bash
cd backend-certificado
npm install
```

## Execução

Para iniciar o servidor:
```bash
npm start
```

O servidor irá rodar na porta 3001 por padrão.

## Endpoints

### POST /api/certificado/processar

Processa um certificado PKCS12 e retorna a chave privada e certificado em formato PEM.

**Request Body:**
```json
{
  "certificadoBase64": "base64_do_certificado",
  "senha": "senha_do_certificado"
}
```

**Response (Sucesso):**
```json
{
  "sucesso": true,
  "chavePrivadaPem": "-----BEGIN PRIVATE KEY-----...",
  "certificadoPem": "-----BEGIN CERTIFICATE-----...",
  "informacoes": {
    "cnpj": "12.345.678/0001-90",
    "validade": {
      "de": "2024-01-01T00:00:00.000Z",
      "ate": "2025-01-01T00:00:00.000Z"
    }
  }
}
```

**Response (Erro):**
```json
{
  "erro": "Erro ao processar certificado",
  "mensagem": "Senha do certificado incorreta",
  "detalhes": "..."
}
```

### GET /api/health

Verifica se o servidor está rodando.

## Segurança

⚠️ **IMPORTANTE**: Este servidor processa certificados digitais. Em produção:

1. Use HTTPS
2. Adicione autenticação
3. Valide e sanitize todas as entradas
4. Use rate limiting
5. Execute em ambiente seguro

## Integração com Flutter

O Flutter irá chamar este endpoint quando o `asn1lib` falhar ao processar um certificado.


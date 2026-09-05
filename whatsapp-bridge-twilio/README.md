# Twilio WhatsApp Bridge for Exodo

Este serviço serve como uma ponte segura entre o sistema Exodo e a API do WhatsApp do Twilio.

## Configuração no Render

Ao criar o serviço no Render, adicione as seguintes variáveis de ambiente:

1.  `TWILIO_ACCOUNT_SID`: Encontrado no dashboard do Twilio.
2.  `TWILIO_AUTH_TOKEN`: Encontrado no dashboard do Twilio.
3.  `TWILIO_PHONE_NUMBER`: Seu número de WhatsApp do Twilio (ex: `+14155238886`).
4.  `BRIDGE_API_SECRET`: Uma senha forte que você criará para proteger sua ponte.

## Endpoints

### POST `/send-message`
Envia uma mensagem de WhatsApp.

**Headers:**
- `x-api-key`: Sua `BRIDGE_API_SECRET`
- `Content-Type`: `application/json`

**Corpo (JSON):**
```json
{
  "to": "5511999998888",
  "message": "Olá, tudo bem?"
}
```

## Como rodar localmente (para teste)

1. Crie um arquivo `.env` baseado no `.env.example`.
2. `npm install`
3. `npm start`
4. O servidor rodará em `http://localhost:3000`.

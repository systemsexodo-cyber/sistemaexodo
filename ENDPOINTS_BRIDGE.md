# 📋 Endpoints do Bridge NFC-e

## 🔄 Compatibilidade de Endpoints

### Endpoints Atuais (provavelmente no bridge):
```
GET  /                           - Status check
POST /emitir                     - Emitir NFC-e
```

### Endpoints Esperados (novo NFCeBackendService):
```
GET  /                           - Status check
POST /api/nfce/emitir           - Emitir NFC-e
POST /api/nfce/cancelar         - Cancelar NFC-e
POST /api/nfce/consultar         - Consultar NFC-e
```

### Endpoints Esperados (NfceService antigo):
```
GET  /                           - Status check
POST /emitir                     - Emitir NFC-e
```

## 🚨 Ações Necessárias:

### Opção 1: Atualizar Bridge (Recomendado)
Adicionar novos endpoints ao bridge:
- `POST /api/nfce/emitir`
- `POST /api/nfce/cancelar`
- `POST /api/nfce/consultar`

### Opção 2: Adaptar App (Rápido)
Manter endpoints antigos no NFCeBackendService:
- Mudar de `/api/nfce/emitir` para `/emitir`
- Implementar cancelamento/consulta separadamente

## 📝 Payload Esperado:

### Emitir NFC-e:
```json
{
  "empresa": {
    "cnpj": "12345678901234",
    "razao_social": "Empresa LTDA",
    "nome_fantasia": "Fantasia",
    "inscricao_estadual": "123456789",
    "logradouro": "Rua A",
    "numero": "123",
    "bairro": "Centro",
    "municipio": "São Paulo",
    "codigo_municipio": "3550308",
    "uf": "SP",
    "cep": "01234567",
    "crt": 1,
    "ambiente": 2,
    "certificado_base64": "BASE64...",
    "senha_certificado": "senha123",
    "csc": "CSC_TOKEN",
    "csc_id": "CSC_ID"
  },
  "itens": [
    {
      "codigo": "001",
      "descricao": "Produto 1",
      "ncm": "00000000",
      "cfop": "5102",
      "quantidade": 1.0,
      "valor_unitario": 10.50,
      "valor_total": 10.50
    }
  ],
  "pagamentos": [
    {
      "tipo": "01",
      "valor": 10.50
    }
  ],
  "valor_total": 10.50,
  "venda_numero": "001",
  "cpf_cliente": "12345678901",
  "serie": "1"
}
```

### Resposta Esperada:
```json
{
  "id": "123456",
  "numero": "001",
  "serie": "1",
  "chave_acesso": "4321...",
  "protocolo": "123456789",
  "status": "autorizada",
  "xml_autorizado": "<?xml...",
  "qr_code": "https://...",
  "data_emissao": "2024-01-01T12:00:00Z"
}
```

## 🧪 Testes:

### Verificar Bridge Atual:
```bash
curl http://localhost:8000/
```

### Testar Emissão:
```bash
curl -X POST http://localhost:8000/emitir \
  -H "Content-Type: application/json" \
  -d @payload.json
```

### Testar Novo Endpoint:
```bash
curl -X POST http://localhost:8000/api/nfce/emitir \
  -H "Content-Type: application/json" \
  -d @payload.json
```

## 📋 Checklist:

- [ ] Verificar endpoints atuais do bridge
- [ ] Testar comunicação com bridge existente
- [ ] Decidir entre atualizar bridge vs adaptar app
- [ ] Implementar solução escolhida
- [ ] Testar integração completa

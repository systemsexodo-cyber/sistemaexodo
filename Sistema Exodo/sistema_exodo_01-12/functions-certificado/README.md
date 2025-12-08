# Cloud Function para Processamento de Certificados PKCS12

Esta Cloud Function processa certificados PKCS12 (.pfx) que não podem ser processados pela biblioteca `asn1lib` no Flutter.

## 🚀 Deploy

### Pré-requisitos

1. Firebase CLI instalado:
```bash
npm install -g firebase-tools
```

2. Login no Firebase:
```bash
firebase login
```

3. Inicializar Firebase Functions (se ainda não foi feito):
```bash
firebase init functions
```

### Deploy da Function

1. Navegue até a pasta da function:
```bash
cd functions-certificado
```

2. Instale as dependências:
```bash
npm install
```

3. Faça o deploy:
```bash
firebase deploy --only functions:processarCertificado
```

Ou para fazer deploy de todas as functions:
```bash
firebase deploy --only functions
```

### Verificar Deploy

Após o deploy, você pode testar a function:

```bash
firebase functions:log --only processarCertificado
```

## 📝 Uso no Flutter

A function é chamada automaticamente quando o `asn1lib` falha ao processar um certificado. O código Flutter já está configurado para usar esta Cloud Function.

## 🔒 Segurança

A function está configurada para aceitar chamadas autenticadas. Se quiser exigir autenticação, descomente as linhas de validação no arquivo `index.js`:

```javascript
if (!context.auth) {
  throw new functions.https.HttpsError(
    'unauthenticated',
    'A função deve ser chamada enquanto autenticado.'
  );
}
```

## 📊 Monitoramento

Você pode monitorar a function no Console do Firebase:
- Acesse: https://console.firebase.google.com
- Vá em Functions > processarCertificado
- Veja logs, métricas e estatísticas

## 🛠️ Desenvolvimento Local

Para testar localmente antes do deploy:

```bash
firebase emulators:start --only functions
```

A function estará disponível em: `http://localhost:5001/[PROJECT-ID]/us-central1/processarCertificado`


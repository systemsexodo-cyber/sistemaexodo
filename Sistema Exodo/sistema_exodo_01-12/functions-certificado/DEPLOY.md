# 🚀 Guia de Deploy - Cloud Function para Certificados

## Passo a Passo para Deploy

### 1. Instalar Firebase CLI (se ainda não tiver)

```bash
npm install -g firebase-tools
```

### 2. Login no Firebase

```bash
firebase login
```

### 3. Configurar o Projeto

Se ainda não configurou o Firebase Functions no projeto:

```bash
cd functions-certificado
firebase init functions
```

**Quando perguntado:**
- Use uma pasta existente? **Sim** (functions-certificado)
- Qual linguagem? **JavaScript**
- Quer usar ESLint? **Não** (ou Sim, se preferir)
- Quer instalar dependências? **Sim**

### 4. Atualizar .firebaserc

Edite o arquivo `.firebaserc` e coloque o ID do seu projeto Firebase:

```json
{
  "projects": {
    "default": "SEU-PROJETO-FIREBASE-ID"
  }
}
```

### 5. Instalar Dependências

```bash
cd functions-certificado
npm install
```

### 6. Fazer Deploy

```bash
firebase deploy --only functions:processarCertificado
```

Ou para fazer deploy de todas as functions:

```bash
firebase deploy --only functions
```

### 7. Verificar Deploy

Após o deploy, você verá uma URL como:
```
https://us-central1-SEU-PROJETO.cloudfunctions.net/processarCertificado
```

### 8. Testar

Você pode testar a function no Console do Firebase ou através do Flutter.

## 📝 Notas Importantes

- A function será executada automaticamente quando o Flutter chamar
- Não precisa iniciar manualmente - é serverless!
- A primeira execução pode demorar alguns segundos (cold start)
- Você pode ver logs em: `firebase functions:log`

## 🔒 Segurança

Por padrão, a function aceita chamadas não autenticadas. Para produção, recomenda-se:

1. Habilitar autenticação no código da function
2. Configurar regras de segurança no Firebase
3. Usar HTTPS sempre

## 💰 Custos

Cloud Functions tem um plano gratuito generoso:
- 2 milhões de invocações/mês grátis
- 400.000 GB-segundos de tempo de computação/mês grátis

Para processamento de certificados, isso é mais que suficiente.


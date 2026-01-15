# 🚀 Como Fazer Deploy do Backend PHP

## ⚠️ Importante: Firebase Functions NÃO Suporta PHP

O Firebase Functions suporta apenas Node.js, Python e Go. Para rodar PHP, você precisa usar **Google Cloud Run**.

## ✅ Opção 1: Google Cloud Run (Recomendado para PHP)

### Pré-requisitos

1. **Google Cloud SDK instalado:**
   ```bash
   # Windows: Baixe em https://cloud.google.com/sdk/docs/install
   # Ou use: choco install gcloudsdk
   ```

2. **Projeto Firebase/Google Cloud configurado**

### Passo a Passo

#### 1. Fazer Login no Google Cloud

```bash
gcloud auth login
gcloud config set project SEU_PROJETO_FIREBASE
```

#### 2. Habilitar APIs Necessárias

```bash
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable containerregistry.googleapis.com
```

#### 3. Build e Deploy

```bash
cd backend_php

# Build e deploy em um comando
gcloud run deploy backend-php-nfce \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8080
```

#### 4. Obter URL

Após o deploy, você receberá uma URL como:
```
https://backend-php-nfce-xxxxx-uc.a.run.app
```

#### 5. Configurar no Flutter

No arquivo `lib/services/nfce_backend_service.dart`:

```dart
NFCeBackendService(baseUrl: 'https://backend-php-nfce-xxxxx-uc.a.run.app')
```

## ✅ Opção 2: Usar Backend Python (Mais Simples)

**Recomendação:** Use o backend Python que já está pronto e funciona no Firebase Functions!

### Vantagens:
- ✅ Já está implementado
- ✅ Funciona nativamente no Firebase Functions
- ✅ Mais simples de fazer deploy
- ✅ Menos configuração

### Como Fazer Deploy:

```bash
cd backend_pynfe

# Configurar Firebase (se ainda não fez)
firebase init functions

# Deploy
firebase deploy --only functions
```

## 📊 Comparação

| Aspecto | PHP (Cloud Run) | Python (Functions) |
|---------|-----------------|-------------------|
| **Complexidade** | Média | Baixa |
| **Tempo de Deploy** | ~5-10 min | ~2-5 min |
| **Custo** | Pago por uso | Pago por uso |
| **Suporte Firebase** | Via Cloud Run | ✅ Nativo |
| **Manutenção** | Média | Baixa |

## 🎯 Recomendação Final

**Para produção:** Use o **Backend Python** que já está implementado e funciona no Firebase Functions.

**Para desenvolvimento local:** Use qualquer um (PHP ou Python).

**Se preferir PHP:** Use Cloud Run (mais complexo, mas funciona).

## 📝 Arquivos Criados

- ✅ `Dockerfile` - Container PHP para Cloud Run
- ✅ `.dockerignore` - Arquivos a ignorar no build
- ✅ `cloudbuild.yaml` - Build automático (opcional)
- ✅ `DEPLOY_FIREBASE_CLOUD_RUN.md` - Guia completo

## 🔧 Comandos Úteis

### Ver logs do Cloud Run:
```bash
gcloud run services logs read backend-php-nfce --region us-central1
```

### Atualizar serviço:
```bash
gcloud run deploy backend-php-nfce --source . --region us-central1
```

### Ver serviços:
```bash
gcloud run services list
```

## ❓ Problemas Comuns

### Erro: "Permission denied"
```bash
gcloud auth login
gcloud config set project SEU_PROJETO
```

### Erro: "API not enabled"
```bash
gcloud services enable run.googleapis.com
```

### Erro: "Port 80 not allowed"
O Cloud Run usa porta 8080. O Dockerfile já está configurado corretamente.

## ✅ Pronto!

Após o deploy, seu backend PHP estará rodando no Google Cloud Run e poderá ser usado pelo Flutter!












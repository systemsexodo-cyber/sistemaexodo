# Migração NFC-e Bridge para Google Cloud

Este guia ajudará você a implantar o serviço **NFC-e Bridge** (Python) na Google Cloud Platform (GCP) utilizando o **Cloud Run**. Isso permitirá que o serviço rode 24/7 na nuvem, processando pedidos do Firebase sem depender de um PC local ligado.

## 🚀 O que foi preparado
1.  **Dockerfile**: Configuração para containerizar o serviço em Linux (Python 3.10-slim).
2.  **Ajustes de Código**: O `main.py` e `nfce_handler.py` foram atualizados para serem compatíveis com Linux/Docker (removendo dependências de Windows e ajustando caminhos).
3.  **cloudbuild.yaml**: Automação para compilar e fazer o deploy direto para a GCP.

---

## 🛠️ Passo 1: Instale o Google Cloud SDK
Se ainda não tem, instale o `gcloud` CLI no seu computador:
[Instalar Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

Depois de instalar, faça o login:
```powershell
gcloud auth login
gcloud auth configure-docker
```

## 🛠️ Passo 2: Configure seu Projeto
Substitua `SEU_PROJETO_ID` pelo ID do seu projeto no Google Cloud (o nome que aparece no console):
```powershell
gcloud config set project SEU_PROJETO_ID
```

## 🛠️ Passo 3: Deploy via Cloud Build (Automático)
Execute este comando no terminal:
```powershell
cd backend_nfce
gcloud builds submit --config cloudbuild.yaml .
```

---

## ⚙️ Configurações Importantes na GCP

### 1. Permissões de Conta de Serviço
O Cloud Run precisará de permissão para ler o Firestore.
1. Vá em **IAM & Admin > Service Accounts**.
2. Localize a conta do Cloud Run (Geralmente `[project-number]-compute@developer.gserviceaccount.com`).
3. Adicione o papel (Role): **Cloud Datastore User** ou **Firebase Admin**.

### 2. Certificados A1
Como o serviço está na nuvem, ele processará os certificados que o aplicativo envia via Firebase. No sistema, garanta que os clientes enviem o certificado `.pfx` corretamente.

---

## ✅ Verificação
Após o deploy, você receberá uma URL (ex: `https://exodo-nfce-bridge-xyz.a.run.app`).
1. Acesse o endpoint `/health` para ver se está online.
2. O serviço começará automaticamente a escutar a coleção `nfce_requests` do seu Firebase!

---
> [!TIP]
> **Custo zero**: O Cloud Run tem um nível gratuito generoso. Você só paga se tiver muitos acessos simultâneos.

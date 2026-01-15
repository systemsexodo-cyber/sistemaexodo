# ☁️ Deploy para Firebase Cloud Run

## 📋 Pré-requisitos

1. **Conta Google Cloud** com billing habilitado
2. **Firebase CLI** instalado
3. **Google Cloud SDK** instalado
4. **Docker** instalado (para build local)

## 🚀 Passo a Passo

### 1. Instalar Ferramentas

```bash
# Instalar Firebase CLI
npm install -g firebase-tools

# Instalar Google Cloud SDK
# Windows: https://cloud.google.com/sdk/docs/install
# Linux/Mac: 
curl https://sdk.cloud.google.com | bash

# Login
firebase login
gcloud auth login
```

### 2. Inicializar Firebase no Projeto

```bash
cd backend_pynfe
firebase init
```

Selecione:
- ☑️ Cloud Run
- Projeto Firebase existente ou criar novo

### 3. Criar Dockerfile

O Dockerfile será criado automaticamente, mas você pode personalizar:

```dockerfile
FROM python:3.10-slim

WORKDIR /app

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    gcc \
    libxml2-dev \
    libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements
COPY requirements.txt .

# Instalar dependências Python
RUN pip install --no-cache-dir -r requirements.txt

# Instalar PyNFe do GitHub
RUN pip install git+https://github.com/TadaSoftware/PyNFe.git

# Copiar código
COPY . .

# Expor porta
EXPOSE 8080

# Variáveis de ambiente
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Comando para iniciar
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
```

### 4. Criar cloudbuild.yaml

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/nfce-backend', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$PROJECT_ID/nfce-backend']
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - 'nfce-backend'
      - '--image'
      - 'gcr.io/$PROJECT_ID/nfce-backend'
      - '--region'
      - 'us-central1'
      - '--platform'
      - 'managed'
      - '--allow-unauthenticated'
```

### 5. Atualizar app.py para Cloud Run

```python
# No início do arquivo, adicionar:
import os
port = int(os.environ.get('PORT', 8080))

# No final, alterar:
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=port, debug=False)
```

### 6. Fazer Deploy

```bash
# Build e deploy
gcloud builds submit --config cloudbuild.yaml

# Ou usar Firebase CLI
firebase deploy --only functions
```

### 7. Obter URL do Serviço

Após o deploy, você receberá uma URL como:
```
https://nfce-backend-xxxxx-uc.a.run.app
```

## 🔗 Atualizar Flutter

No Flutter, atualize a URL:

```dart
final backendService = NFCeBackendService(
  baseUrl: 'https://nfce-backend-xxxxx-uc.a.run.app',
);
```

## 🔐 Configurar Variáveis de Ambiente

No Cloud Run, configure variáveis de ambiente:

```bash
gcloud run services update nfce-backend \
  --set-env-vars="DEBUG=False,UF_PADRAO=SP"
```

## 📊 Monitoramento

```bash
# Ver logs
gcloud run services logs read nfce-backend

# Ver métricas
# Acesse: https://console.cloud.google.com/run
```

## 💰 Custos

Cloud Run cobra por:
- **Tempo de execução:** $0.00002400 por GB-segundo
- **Requisições:** $0.40 por milhão
- **Tráfego:** $0.12 por GB

Para uso moderado, geralmente fica abaixo de $10/mês.

## 🐛 Troubleshooting

### Erro de build
- Verifique se o Dockerfile está correto
- Verifique se todas as dependências estão no requirements.txt

### Erro de timeout
- Aumente o timeout no Cloud Run
- Otimize o código Python

### Erro de memória
- Aumente a memória alocada no Cloud Run
- Otimize o uso de memória

## 📝 Notas Importantes

1. **Certificados:** Em produção, não salve certificados no código. Use Secret Manager do Google Cloud.

2. **Segurança:** Configure autenticação no Cloud Run se necessário.

3. **Escalabilidade:** Cloud Run escala automaticamente, mas configure limites se necessário.

## ✅ Checklist de Deploy

- [ ] Firebase CLI instalado
- [ ] Google Cloud SDK instalado
- [ ] Projeto Firebase criado
- [ ] Dockerfile criado
- [ ] app.py atualizado para Cloud Run
- [ ] Variáveis de ambiente configuradas
- [ ] Deploy realizado
- [ ] URL obtida
- [ ] Flutter atualizado com nova URL
- [ ] Testes realizados



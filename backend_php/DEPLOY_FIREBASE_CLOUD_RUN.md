# 🚀 Deploy do Backend PHP no Google Cloud Run

## ⚠️ Importante: Firebase Functions NÃO Suporta PHP

O **Firebase Functions** suporta apenas:
- ✅ Node.js
- ✅ Python
- ✅ Go

**NÃO suporta PHP nativamente.**

## ✅ Solução: Google Cloud Run

Para rodar o backend PHP no Firebase/Google Cloud, use o **Google Cloud Run**, que suporta qualquer linguagem via containers Docker.

## 🎯 Opções de Deploy

### Opção 1: Google Cloud Run (Recomendado)

O Cloud Run permite rodar containers Docker, então podemos criar um container PHP.

#### Vantagens:
- ✅ Suporta PHP
- ✅ Escala automaticamente
- ✅ Paga apenas pelo uso
- ✅ Integra com Firebase
- ✅ HTTPS automático

#### Passo a Passo:

1. **Criar Dockerfile:**
   ```dockerfile
   FROM php:8.1-apache
   
   # Instalar extensões PHP necessárias
   RUN apt-get update && apt-get install -y \
       libxml2-dev \
       libcurl4-openssl-dev \
       libzip-dev \
       unzip \
       && docker-php-ext-install \
       xml \
       curl \
       zip \
       soap
   
   # Instalar Composer
   COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
   
   # Copiar código
   WORKDIR /var/www/html
   COPY . .
   
   # Instalar dependências
   RUN composer install --no-dev --optimize-autoloader
   
   # Configurar Apache
   RUN a2enmod rewrite
   COPY .htaccess .htaccess
   
   EXPOSE 8080
   CMD ["apache2-foreground"]
   ```

2. **Criar .dockerignore:**
   ```
   vendor/
   storage/certs/*
   storage/xml/*
   logs/*
   .env
   .git
   ```

3. **Fazer Deploy:**
   ```bash
   # Instalar Google Cloud SDK
   # https://cloud.google.com/sdk/docs/install
   
   # Fazer login
   gcloud auth login
   
   # Configurar projeto
   gcloud config set project SEU_PROJETO_FIREBASE
   
   # Build e deploy
   gcloud run deploy backend-php-nfce \
     --source . \
     --platform managed \
     --region us-central1 \
     --allow-unauthenticated
   ```

### Opção 2: Usar Backend Python (Já Funciona)

**Recomendação:** Use o backend Python que já está configurado e funciona no Firebase Functions!

O backend Python (`backend_pynfe/`) já está pronto e pode ser deployado no Firebase Functions.

#### Vantagens:
- ✅ Já está implementado
- ✅ Funciona no Firebase Functions
- ✅ Não precisa de Docker
- ✅ Mais simples de manter

#### Como Fazer Deploy:

```bash
cd backend_pynfe
firebase deploy --only functions
```

### Opção 3: Cloud Functions for Firebase (Python)

O backend Python pode ser deployado diretamente no Firebase Functions.

## 📊 Comparação

| Recurso | Backend PHP (Cloud Run) | Backend Python (Functions) |
|---------|-------------------------|----------------------------|
| **Suporte Firebase** | Via Cloud Run | ✅ Nativo |
| **Complexidade** | Média (Docker) | Baixa |
| **Custo** | Pago por uso | Pago por uso |
| **Escalabilidade** | Automática | Automática |
| **Tempo de deploy** | ~5-10 min | ~2-5 min |
| **Manutenção** | Média | Baixa |

## 🎯 Recomendação

**Use o Backend Python** que já está implementado:
- ✅ Já funciona
- ✅ Mais simples
- ✅ Suporte nativo do Firebase
- ✅ Menos configuração

O backend PHP pode ser usado como alternativa local ou se você preferir PHP, mas requer Cloud Run.

## 📝 Arquivos Necessários para Cloud Run

Criei os arquivos necessários:
- `Dockerfile` - Container PHP
- `.dockerignore` - Arquivos a ignorar
- `cloudbuild.yaml` - Build automático (opcional)

## 🔧 Configuração do Cloud Run

Após o deploy, você terá uma URL como:
```
https://backend-php-nfce-xxxxx.run.app
```

Configure no Flutter:
```dart
NFCeBackendService(baseUrl: 'https://backend-php-nfce-xxxxx.run.app')
```

## ❓ Qual Escolher?

**Para produção:** Use o **Backend Python** (já está pronto)
**Para desenvolvimento local:** Use qualquer um (PHP ou Python)
**Se preferir PHP:** Use Cloud Run (mais complexo)












# ☁️ Deploy no Firebase/Google Cloud Run

## ❓ Resposta Rápida

**Sim, você consegue rodar no Firebase/Google Cloud!**

### ✅ **NÃO precisa ficar executando nada!**

O **Google Cloud Run** é **serverless**:
- ✅ Liga automaticamente quando recebe requisição
- ✅ Desliga automaticamente quando não há uso
- ✅ Escala automaticamente (0 a N instâncias)
- ✅ Você paga apenas pelo que usa
- ✅ Sem necessidade de manter servidor rodando

## 📊 Comparação de Opções

| Opção | Precisa Rodar? | Custo | Dificuldade |
|-------|---------------|-------|-------------|
| **Cloud Run** (Recomendado) | ❌ Não (serverless) | Baixo ($0 quando parado) | Fácil |
| **Cloud Functions** | ❌ Não (serverless) | Baixo | ❌ Não suporta Python |
| **Compute Engine** | ✅ Sim (sempre rodando) | Médio/Alto | Média |
| **App Engine** | ❌ Não (serverless) | Baixo | Fácil |

## 🚀 Opção Recomendada: Cloud Run

### ✅ Vantagens:
- **Serverless**: Não precisa ficar rodando
- **Escala automática**: 0 a N instâncias
- **Paga só quando usa**: $0 quando parado
- **HTTPS gratuito**: SSL/TLS incluído
- **Fácil deploy**: Um comando
- **Integrado com Firebase**: Mesma conta Google

### 💰 Custo Estimado:
- **Quando parado**: $0
- **Primeiros 2 milhões de requisições/mês**: Grátis
- **Após isso**: ~$0.40 por milhão
- **Tempo de execução**: ~$0.00002400 por GB-segundo
- **Para uso moderado**: **$5-15/mês** ou menos

## 📋 Pré-requisitos

1. **Conta Google Cloud** (mesma do Firebase)
2. **Billing habilitado** (tem créditos grátis)
3. **Firebase CLI** instalado
4. **Docker** (opcional, para testar local)

## 🛠️ Configuração Rápida

### 1. Instalar Ferramentas

```bash
# Instalar Firebase CLI
npm install -g firebase-tools

# Login
firebase login
```

### 2. Criar Projeto (se não tiver)

```bash
# No console: https://console.cloud.google.com
# Criar novo projeto ou usar existente
```

### 3. Configurar Billing

```bash
# No console: https://console.cloud.google.com/billing
# Adicionar método de pagamento (tem créditos grátis)
```

## 📁 Arquivos Necessários

Já foram criados:
- ✅ `Dockerfile` - Para criar container
- ✅ `cloudbuild.yaml` - Para build automático
- ✅ `app.py` - Já configurado para Cloud Run

## 🚀 Deploy em 3 Passos

### Passo 1: Preparar

```bash
cd backend_pynfe
```

### Passo 2: Fazer Deploy

```bash
# Opção A: Usar script (recomendado)
deploy_cloud_run.bat  # Windows
# ou
./deploy_cloud_run.sh  # Linux/Mac

# Opção B: Manual
gcloud run deploy nfce-backend \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### Passo 3: Obter URL

Após deploy, você receberá uma URL:
```
https://nfce-backend-xxxxx-uc.a.run.app
```

## ⚙️ Como Funciona

1. **Você faz deploy** → Google cria container
2. **Quando recebe requisição** → Google inicia instância
3. **Processa requisição** → Responde
4. **Se não há mais requisições** → Google desliga instância
5. **Você paga apenas** → Pelo tempo que rodou

## 🔧 Configurações Importantes

### Variáveis de Ambiente

Configure no Cloud Run:

```bash
gcloud run services update nfce-backend \
  --set-env-vars="DEBUG=False,SECRET_KEY=sua-chave,CORS_ORIGINS=https://seu-dominio.com"
```

### Timeout

Aumentar timeout se necessário (padrão: 300s):

```bash
gcloud run services update nfce-backend \
  --timeout=600
```

### Memória

Aumentar memória se necessário (padrão: 512MB):

```bash
gcloud run services update nfce-backend \
  --memory=1Gi
```

## 📊 Monitoramento

### Ver Logs

```bash
gcloud run services logs read nfce-backend --limit=50
```

### Ver Métricas

Acesse: https://console.cloud.google.com/run

## 🔗 Integrar com Flutter

No Flutter, atualize a URL:

```dart
final backendService = NFCeBackendService(
  baseUrl: 'https://nfce-backend-xxxxx-uc.a.run.app',
);
```

## ❓ Perguntas Frequentes

### Preciso deixar rodando?
**Não!** Cloud Run é serverless. Liga/desliga automaticamente.

### Quanto custa quando parado?
**$0!** Você só paga quando há requisições.

### Tem limite de requisições?
Primeiros 2 milhões/mês são grátis. Depois ~$0.40 por milhão.

### Quanto tempo leva para "acordar"?
Primeira requisição: ~5-10 segundos (cold start)
Requisições seguintes: Instantâneo (já está "quente")

### Posso forçar sempre ligado?
Sim, mas custa mais. Configure "min instances = 1".

## 🎯 Resumo

✅ **Sim, funciona no Firebase/Google Cloud**
✅ **NÃO precisa ficar rodando** (serverless)
✅ **Custo baixo** ($0 quando parado)
✅ **Escala automaticamente**
✅ **HTTPS gratuito**

**Próximo passo:** Seguir o guia de deploy abaixo!



























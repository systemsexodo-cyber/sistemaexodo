#!/bin/bash
# ============================================
# Deploy para Google Cloud Run (Serverless)
# ============================================

set -e

echo "========================================"
echo "Deploy para Google Cloud Run"
echo "========================================"
echo ""

# Verificar se está no diretório correto
if [ ! -f "app.py" ]; then
    echo "ERRO: app.py não encontrado!"
    echo "Execute este script no diretório backend_pynfe"
    exit 1
fi

# Verificar se gcloud está instalado
if ! command -v gcloud &> /dev/null; then
    echo "ERRO: Google Cloud SDK não encontrado!"
    echo ""
    echo "Instale em: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

echo "[1/5] Verificando login..."
gcloud auth list

echo ""
echo "[2/5] Configurando projeto..."
echo ""
read -p "Digite o ID do projeto Google Cloud (ou pressione Enter para usar padrão): " PROJECT_ID
PROJECT_ID=${PROJECT_ID:-exodosystems-1541d}

gcloud config set project $PROJECT_ID

echo ""
echo "[3/5] Habilitando APIs necessárias..."
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com

echo ""
echo "[4/5] Fazendo deploy para Cloud Run..."
echo ""
echo "Isso pode levar alguns minutos..."
echo ""

gcloud run deploy nfce-backend \
    --source . \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --memory 1Gi \
    --timeout 600 \
    --max-instances 10 \
    --min-instances 0

if [ $? -ne 0 ]; then
    echo ""
    echo "ERRO: Falha no deploy!"
    echo ""
    echo "Verifique:"
    echo "  1. Billing habilitado no projeto"
    echo "  2. APIs habilitadas"
    echo "  3. Permissões corretas"
    exit 1
fi

echo ""
echo "[5/5] Obtendo URL do serviço..."
echo ""

SERVICE_URL=$(gcloud run services describe nfce-backend \
    --platform managed \
    --region us-central1 \
    --format "value(status.url)")

echo "========================================"
echo "Deploy concluído com sucesso!"
echo "========================================"
echo ""
echo "URL do serviço:"
echo "$SERVICE_URL"
echo ""
echo "Teste o health check:"
echo "$SERVICE_URL/health"
echo ""
echo "Para ver logs:"
echo "gcloud run services logs read nfce-backend --region us-central1"
echo ""



























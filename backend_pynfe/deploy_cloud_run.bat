@echo off
REM ============================================
REM Deploy para Google Cloud Run (Serverless)
REM ============================================

echo ========================================
echo Deploy para Google Cloud Run
echo ========================================
echo.

REM Verificar se está no diretório correto
if not exist "app.py" (
    echo ERRO: app.py nao encontrado!
    echo Execute este script no diretorio backend_pynfe
    pause
    exit /b 1
)

REM Verificar se gcloud está instalado
where gcloud >nul 2>&1
if errorlevel 1 (
    echo ERRO: Google Cloud SDK nao encontrado!
    echo.
    echo Instale em: https://cloud.google.com/sdk/docs/install
    echo.
    pause
    exit /b 1
)

echo [1/5] Verificando login...
gcloud auth list
if errorlevel 1 (
    echo.
    echo Fazendo login...
    gcloud auth login
)

echo.
echo [2/5] Configurando projeto...
echo.
set /p PROJECT_ID="Digite o ID do projeto Google Cloud (ou pressione Enter para usar padrao): "
if "%PROJECT_ID%"=="" set PROJECT_ID=exodosystems-1541d

gcloud config set project %PROJECT_ID%
if errorlevel 1 (
    echo ERRO: Falha ao configurar projeto
    pause
    exit /b 1
)

echo.
echo [3/5] Habilitando APIs necessarias...
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com

echo.
echo [4/5] Fazendo deploy para Cloud Run...
echo.
echo Isso pode levar alguns minutos...
echo.

gcloud run deploy nfce-backend ^
    --source . ^
    --platform managed ^
    --region us-central1 ^
    --allow-unauthenticated ^
    --memory 1Gi ^
    --timeout 600 ^
    --max-instances 10 ^
    --min-instances 0

if errorlevel 1 (
    echo.
    echo ERRO: Falha no deploy!
    echo.
    echo Verifique:
    echo   1. Billing habilitado no projeto
    echo   2. APIs habilitadas
    echo   3. Permissoes corretas
    pause
    exit /b 1
)

echo.
echo [5/5] Obtendo URL do servico...
echo.

for /f "tokens=*" %%i in ('gcloud run services describe nfce-backend --platform managed --region us-central1 --format "value(status.url)"') do set SERVICE_URL=%%i

echo ========================================
echo Deploy concluido com sucesso!
echo ========================================
echo.
echo URL do servico:
echo %SERVICE_URL%
echo.
echo Teste o health check:
echo %SERVICE_URL%/health
echo.
echo Para ver logs:
echo gcloud run services logs read nfce-backend --region us-central1
echo.
pause



























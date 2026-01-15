@echo off
title Backend NFC-e VALIDADO - Sistema Exodo
color 0A

echo.
echo ========================================
echo   BACKEND NFC-e - VALIDADO E CORRIGIDO
echo ========================================
echo.
echo   Processo 100%% validado:
echo   - XML de envio validado
echo   - XML de retorno processado
echo   - Correcoes automaticas ativas
echo   - Erros tratados
echo.
echo   Iniciando servidor em: http://localhost:5000
echo ========================================
echo.

cd backend_pynfe

REM Verificar Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [ERRO] Python nao encontrado!
    echo.
    echo Instale Python de: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

REM Tentar instalar dependencias basicas (se nao tiver)
python -m pip show flask >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Instalando dependencias...
    python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography nfelib --quiet
)

echo [OK] Iniciando servidor VALIDADO...
echo.
echo Pressione Ctrl+C para parar
echo.

python app.py












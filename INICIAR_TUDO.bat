@echo off
title Backend NFC-e - Sistema Exodo
color 0A

echo.
echo ========================================
echo   BACKEND NFC-e - SISTEMA EXODO
echo ========================================
echo.
echo   Iniciando servidor em: http://localhost:5000
echo.
echo   Pressione Ctrl+C para parar
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
    python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography --quiet
)

echo [OK] Iniciando servidor...
echo.

python app.py












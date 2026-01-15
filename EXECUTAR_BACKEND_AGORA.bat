@echo off
title Executar Backend NFC-e - Sistema Exodo
color 0A
cls

echo.
echo ========================================
echo   EXECUTAR BACKEND NFC-e
echo ========================================
echo.

REM Verificar se está na pasta correta
if not exist "backend_pynfe" (
    echo [ERRO] Pasta backend_pynfe nao encontrada!
    echo.
    echo Execute este script na raiz do projeto.
    echo.
    pause
    exit /b 1
)

REM Verificar Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [ERRO] Python nao encontrado!
    echo.
    echo Instale Python de: https://www.python.org/downloads/
    echo IMPORTANTE: Marque "Add Python to PATH" durante a instalacao!
    echo.
    pause
    exit /b 1
)

echo [OK] Python encontrado:
python --version
echo.

REM Navegar para pasta do backend
cd backend_pynfe

REM Verificar se app.py existe
if not exist "app.py" (
    color 0C
    echo [ERRO] app.py nao encontrado!
    echo.
    echo Certifique-se de que esta na pasta correta.
    echo.
    pause
    exit /b 1
)

REM Verificar dependencias
echo [INFO] Verificando dependencias...
python -m pip show flask >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Instalando dependencias (pode levar alguns minutos)...
    python -m pip install --upgrade pip --quiet
    python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography --quiet
    if %errorlevel% neq 0 (
        color 0C
        echo [ERRO] Falha ao instalar dependencias!
        echo.
        echo Tente manualmente:
        echo   python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
        echo.
        pause
        exit /b 1
    )
    echo [OK] Dependencias instaladas!
) else (
    echo [OK] Dependencias OK!
)

echo.
echo ========================================
echo   INICIANDO SERVIDOR
echo ========================================
echo.
echo   URL: http://localhost:5000
echo   Health: http://localhost:5000/health
echo.
echo   Pressione Ctrl+C para parar
echo ========================================
echo.

REM Iniciar servidor
python app.py

REM Se chegou aqui, servidor foi fechado
echo.
echo Servidor foi fechado.
pause












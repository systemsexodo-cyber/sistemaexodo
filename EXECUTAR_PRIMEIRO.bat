@echo off
echo ========================================
echo PROCESSO COMPLETO - EMISSAO NFC-e
echo ========================================
echo.
echo Este script vai:
echo   1. Verificar Python
echo   2. Instalar dependencias do backend
echo   3. Iniciar o servidor backend
echo.
pause

REM Verificar Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo ERRO: Python nao encontrado!
    echo ========================================
    echo.
    echo Instale Python 3.10+ de:
    echo   https://www.python.org/downloads/
    echo.
    echo IMPORTANTE: Marque "Add Python to PATH" durante a instalacao!
    echo.
    pause
    exit /b 1
)

echo [OK] Python encontrado!
python --version
echo.

REM Ir para pasta do backend
cd backend_pynfe

REM Instalar dependencias
echo ========================================
echo Instalando dependencias...
echo ========================================
python -m pip install --upgrade pip
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography

if %errorlevel% neq 0 (
    echo.
    echo ERRO: Falha ao instalar dependencias!
    echo Tente manualmente: pip install -r requirements.txt
    pause
    exit /b 1
)

echo.
echo ========================================
echo Dependencias instaladas com sucesso!
echo ========================================
echo.
echo Agora vamos iniciar o servidor...
echo.
pause

REM Iniciar servidor
echo ========================================
echo Iniciando servidor backend...
echo ========================================
echo.
echo O servidor vai iniciar em: http://localhost:5000
echo.
echo Pressione Ctrl+C para parar quando quiser
echo.
python app.py












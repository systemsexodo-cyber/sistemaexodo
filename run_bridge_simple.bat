@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo   BRIDGE NFC-e - VERSAO SIMPLIFICADA
echo ============================================
echo.
echo Modo: Apenas HTTP (sem Firebase/bandeja)
echo.

:: Verificar Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python nao encontrado!
    pause
    exit /b 1
)

cd /d "%~dp0backend_nfce"

:: Verificar/criar venv
if not exist "venv" (
    echo 📦 Criando ambiente virtual...
    python -m venv venv
)

:: Ativar venv
call venv\Scripts\activate.bat

:: Instalar dependencias minimas
echo 📦 Instalando dependencias...
pip install -q fastapi uvicorn pydantic requests pynfe signxml lxml cryptography 2>nul

echo.
echo ============================================
echo 🚀 Iniciando Bridge (Modo Simples)...
echo ============================================
echo.
echo URL: http://localhost:8000
echo Health Check: http://localhost:8000/health
echo.
echo Pressione CTRL+C para parar
echo.

python main_simple.py

:: Desativar venv
call venv\Scripts\deactivate.bat

echo.
echo Bridge encerrado.
pause

@echo off
chcp 65001 >nul
echo.
echo ========================================
echo   BRIDGE NFC-e - MODO DESENVOLVIMENTO
echo ========================================
echo.

:: Verificar se Python está instalado
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python nao encontrado!
    echo Por favor, instale Python 3.9 ou superior.
    pause
    exit /b 1
)

echo ✅ Python detectado
echo.

:: Mudar para pasta do backend_nfce
cd /d "%~dp0backend_nfce"

:: Verificar se existe virtual environment, se nao criar
if not exist "venv" (
    echo 📦 Criando ambiente virtual...
    python -m venv venv
    echo ✅ Ambiente virtual criado
)

:: Ativar venv
echo 🔌 Ativando ambiente virtual...
call venv\Scripts\activate.bat

:: Instalar/Atualizar dependencias
echo 📦 Verificando dependencias...
pip install -q uvicorn fastapi pynfe requests firebase_admin pystray pillow

:: Iniciar bridge
echo.
echo 🚀 Iniciando Bridge NFC-e...
echo.
echo URL: http://localhost:8000
echo Pressione CTRL+C para parar
echo.
echo ========================================

python run_bridge_local.py --reload

:: Desativar venv ao sair
call venv\Scripts\deactivate.bat

echo.
echo Bridge encerrado.
pause

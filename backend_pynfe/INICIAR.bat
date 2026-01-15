@echo off
echo ========================================
echo Iniciando Servidor Backend NFC-e
echo ========================================
echo.

cd /d "%~dp0"

echo Verificando Python...
python --version
if errorlevel 1 (
    echo ❌ Python não encontrado!
    pause
    exit /b 1
)

echo.
echo Verificando dependências...
python -c "import flask" 2>nul
if errorlevel 1 (
    echo ⚠️ Flask não encontrado. Instalando...
    pip install flask flask-cors python-dotenv
)

echo.
echo ========================================
echo Iniciando servidor...
echo ========================================
echo.
echo Servidor será iniciado em: http://localhost:5000
echo Health Check: http://localhost:5000/health
echo Pressione Ctrl+C para parar
echo.

python app.py

pause






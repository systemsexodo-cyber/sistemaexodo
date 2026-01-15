@echo off
echo ========================================
echo Iniciando Backend SIMPLIFICADO
echo ========================================
echo.

cd /d "%~dp0"

REM Verificar se o ambiente virtual existe
if not exist "venv" (
    echo ❌ Ambiente virtual não encontrado!
    echo Execute primeiro: instalar_tudo.bat
    pause
    exit /b 1
)

echo ✅ Ambiente virtual encontrado
echo.

REM Ativar ambiente virtual
call venv\Scripts\activate.bat

REM Verificar Flask
python -c "import flask; print('✅ Flask OK')" 2>nul
if errorlevel 1 (
    echo Instalando Flask...
    pip install flask flask-cors
)

echo.
echo ========================================
echo Iniciando servidor...
echo ========================================
echo.
echo Servidor será iniciado em: http://localhost:5000
echo Pressione Ctrl+C para parar
echo.

python app_simples.py

pause



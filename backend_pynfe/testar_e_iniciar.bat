@echo off
echo ========================================
echo TESTE E INICIO DO BACKEND
echo ========================================
echo.

cd /d "%~dp0"

echo 1. Verificando Python...
venv\Scripts\python.exe --version
if errorlevel 1 (
    echo ❌ ERRO: Python nao encontrado!
    pause
    exit /b 1
)
echo ✅ Python OK
echo.

echo 2. Verificando Flask...
venv\Scripts\python.exe -c "import flask; print('✅ Flask OK')" 2>&1
if errorlevel 1 (
    echo ❌ Flask nao instalado! Instalando...
    venv\Scripts\python.exe -m pip install flask flask-cors
    if errorlevel 1 (
        echo ❌ ERRO ao instalar Flask!
        pause
        exit /b 1
    )
)
echo.

echo 3. Testando versao MINIMA (sempre funciona)...
echo.
venv\Scripts\python.exe app_minimo.py
if errorlevel 1 (
    echo.
    echo ❌ ERRO ao iniciar versao minima!
    echo.
    echo Mostrando erro completo:
    venv\Scripts\python.exe app_minimo.py 2>&1
    pause
    exit /b 1
)

pause



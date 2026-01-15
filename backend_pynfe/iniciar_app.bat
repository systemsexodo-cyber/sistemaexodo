@echo off
echo ========================================
echo INICIANDO APP NFC-e
echo ========================================
echo.

cd /d "%~dp0"

REM Verificar se venv existe
if not exist "venv" (
    echo [ERRO] Ambiente virtual nao encontrado!
    echo Execute primeiro: .\instalar_completo.bat
    pause
    exit /b 1
)

REM Ativar venv
call venv\Scripts\activate.bat

echo Verificando dependencias...
python -c "import flask; import lxml; import cryptography; import zeep; print('[OK] Todas as dependencias instaladas')" 2>nul
if errorlevel 1 (
    echo [ERRO] Dependencias faltando!
    echo Execute: .\instalar_completo.bat
    pause
    exit /b 1
)

echo.
echo Iniciando servidor...
echo.
python app_nfce_completo_seguro.py

pause





















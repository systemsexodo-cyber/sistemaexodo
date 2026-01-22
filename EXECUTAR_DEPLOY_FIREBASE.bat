@echo off
echo ========================================
echo   INICIANDO DEPLOY FIREBASE
echo ========================================
echo.

REM Mudar para o diretorio do script
cd /d "%~dp0"

REM Verificar se o Powershell existe
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERRO: Powershell nao encontrado no sistema!
    pause
    exit /b 1
)

echo Executando script de deploy...
echo.

powershell -ExecutionPolicy Bypass -File "deploy_firebase_automatico.ps1"

echo.
echo ========================================
echo   PROCESSO FINALIZADO
echo ========================================
echo.
pause

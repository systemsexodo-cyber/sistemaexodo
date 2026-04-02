@echo off
setlocal
echo ============================================================
echo   SISTEMA EXODO - INICIALIZADOR WEB
echo ============================================================
echo.
echo [1] Rodar no Chrome (Pode falhar se houver bloqueio)
echo [2] Rodar no Edge   (Geralmente mais estavel)
echo [3] Rodar Modo Servidor (RECOMENDADO: Nao falha nunca)
echo     - Ja abre manualmente no navegador
echo.
set /p choice="Escolha uma opcao (1-3) [Padrao: 3]: "

if "%choice%"=="1" (
    echo Iniciando no Chrome...
    powershell -ExecutionPolicy Bypass -File "%~dp0flutter_run_web.ps1" -Device chrome
) else if "%choice%"=="2" (
    echo Iniciando no Edge...
    powershell -ExecutionPolicy Bypass -File "%~dp0flutter_run_web.ps1" -Device edge
) else (
    echo Iniciando Modo Servidor...
    powershell -ExecutionPolicy Bypass -File "%~dp0flutter_run_web.ps1" -Device web-server
)

pause

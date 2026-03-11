@echo off
:: Solicitar privilégios de Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando privilegios de administrador...
    powershell -Command "Start-Process '%0' -Verb RunAs"
    exit /b
)

echo Fechando instâncias antigas do Bridge...
taskkill /F /IM ExodoNfceBridgeWatchdog.exe >nul 2>&1
taskkill /F /IM ExodoNfceBridge.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1

echo Aguardando fechamento...
timeout /t 2 /nobreak >nul

echo === Atualizando Versao do Bridge ===
cd /d "%~dp0"
echo Construindo novo executavel...
pyinstaller ExodoNfceBridge.spec --noconfirm

if exist "dist\ExodoNfceBridge.exe" (
    echo Movendo novo executavel...
    move /Y "dist\ExodoNfceBridge.exe" "ExodoNfceBridge.exe"
    rmdir /S /Q dist
    rmdir /S /Q build
    echo Iniciando o novo Bridge...
    start "" "ExodoNfceBridge.exe"
    echo Sucesso! O novo Bridge atualizado foi iniciado.
) else (
    echo Erro ao compilar novo Bridge.
)
pause

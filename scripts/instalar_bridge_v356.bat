@echo off
setlocal

rem Solicita privilegios de administrador (o Bridge roda elevado - RunLevel HighestAvailable)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando privilegios de administrador...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set PASTA=%~dp0..
set DIST=%PASTA%\backend_nfce\dist
set DEST=C:\SistemaExodo\bridge
set LOG=%DEST%\instalacao_bridge.log

echo === Instalando Bridge v3.5.6 em %DEST% === >> "%LOG%"
echo [%DATE% %TIME%] inicio >> "%LOG%"

echo [1/5] Parando bridge e watchdog...
taskkill /F /IM ExodoNfceBridge.exe >> "%LOG%" 2>&1
taskkill /F /IM ExodoNfceBridgeWatchdog.exe >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul

echo [2/5] Copiando executaveis...
if not exist "%DIST%\ExodoNfceBridge_v356.exe" (
    echo ERRO: nao achei "%DIST%\ExodoNfceBridge_v356.exe" >> "%LOG%"
    exit /b 1
)
copy /Y "%DIST%\ExodoNfceBridge_v356.exe" "%DEST%\ExodoNfceBridge.exe" >> "%LOG%" 2>&1
copy /Y "%DIST%\ExodoNfceBridgeWatchdog_v356.exe" "%DEST%\ExodoNfceBridgeWatchdog.exe" >> "%LOG%" 2>&1

echo [3/5] Marcando versao instalada...
> "%DEST%\.installed" echo 3.5.6

echo [4/5] Limpando lixo de atualizacoes antigas...
del /Q "%DEST%\update_bridge.bat" "%DEST%\update_bridge.vbs" "%DEST%\ExodoNfceBridge.exe.new" 2>nul

echo [5/5] Iniciando bridge atualizado...
start "" "%DEST%\ExodoNfceBridge.exe" --silent

echo [%DATE% %TIME%] fim >> "%LOG%"
endlocal

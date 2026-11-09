@echo off
setlocal EnableDelayedExpansion
title Atualizar Bridge NFC-e (maquina)
:: Solicitar privilegios de Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando privilegios de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "BASE=%~dp0"
set "BASE=%BASE:~0,-1%"
set "BRIDGE_DIR=C:\ExodoNFCe"
set "APP_BRIDGE_DIR=C:\SistemaExodo\bridge"

echo.
echo ========================================================
echo   ATUALIZANDO O BRIDGE QUE RODA NA MAQUINA
echo ========================================================

echo.
echo [1/5] Encerrando instancias antigas...
taskkill /F /IM ExodoNfceBridgeWatchdog.exe >nul 2>&1
taskkill /F /IM ExodoNfceBridge.exe >nul 2>&1
timeout /t 2 /nobreak >nul

cd /d "%BASE%\backend_nfce"

:: IMPORTANTE: usar o venv do bridge. O "python" do PATH nao tem uvicorn e
:: gerava um EXE que abria com ModuleNotFoundError: No module named 'uvicorn'.
if exist "%BASE%\backend_nfce\venv\Scripts\python.exe" (
    set "PYTHON_EXE=%BASE%\backend_nfce\venv\Scripts\python.exe"
) else if exist "%BASE%\.venv\Scripts\python.exe" (
    set "PYTHON_EXE=%BASE%\.venv\Scripts\python.exe"
) else (
    set "PYTHON_EXE=python"
)

for /f "tokens=3" %%V in ('findstr /B /C:"BRIDGE_VERSION" main.py') do set "VERSION=%%~V"
set "VERSION=%VERSION:"=%"
set "VER_CLEAN=%VERSION:.=%"
echo Versao detectada: %VERSION%
echo Python do build: !PYTHON_EXE!

echo.
echo [2/5] Compilando o bridge (pode levar alguns minutos)...
"!PYTHON_EXE!" -m PyInstaller --clean --noconfirm ExodoNfceBridge.spec
if errorlevel 1 (
    echo.
    echo ERRO na compilacao. Nada foi alterado na maquina.
    pause
    exit /b 1
)

set "NEW_EXE=%BASE%\backend_nfce\dist\ExodoNfceBridge_v%VER_CLEAN%.exe"
set "NEW_WATCHDOG=%BASE%\backend_nfce\dist\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe"
if not exist "%NEW_EXE%" (
    echo ERRO: "%NEW_EXE%" nao foi gerado. Verifique o nome do EXE no .spec
    pause
    exit /b 1
)

:: Conferir que o EXE realmente tem uvicorn (evita publicar build quebrado)
"!PYTHON_EXE!" -c "import sys;d=open(sys.argv[1],'rb').read();sys.exit(0 if b'uvicorn' in d else 1)" "%NEW_EXE%"
if errorlevel 1 (
    echo ERRO: o EXE gerado nao contem uvicorn. Build abortado.
    pause
    exit /b 1
)

echo.
echo [3/5] Implantando o novo EXE...
set "STAMP=%DATE:/=-%_%TIME:~0,2%%TIME:~3,2%"
set "STAMP=%STAMP: =0%"

call :deploy "%NEW_EXE%" "%BASE%\ExodoNfceBridge.exe"
call :deploy "%NEW_EXE%" "%BASE%\ExodoNfceBridge_v%VER_CLEAN%.exe"
call :deploy "%NEW_EXE%" "%BASE%\backend_nfce\dist\ExodoNfceBridge.exe"
call :deploy "%NEW_EXE%" "%BRIDGE_DIR%\ExodoNfceBridge.exe"
call :deploy "%NEW_EXE%" "%APP_BRIDGE_DIR%\ExodoNfceBridge.exe"

if exist "%NEW_WATCHDOG%" (
    call :deploy "%NEW_WATCHDOG%" "%BASE%\ExodoNfceBridgeWatchdog.exe"
    call :deploy "%NEW_WATCHDOG%" "%BRIDGE_DIR%\ExodoNfceBridgeWatchdog.exe"
    call :deploy "%NEW_WATCHDOG%" "%APP_BRIDGE_DIR%\ExodoNfceBridgeWatchdog.exe"
)

echo.
echo [4/5] Corrigindo o auto-start para apontar sempre para %BRIDGE_DIR%...
:: Marcador: apagado para o bridge reconfigurar a inicializacao na proxima abertura
del /Q "%BRIDGE_DIR%\.installed" >nul 2>&1
del /Q "%APP_BRIDGE_DIR%\.installed" >nul 2>&1

:: Tarefas antigas apontavam para C:\SistemaExodo\bridge (rodava a copia velha)
schtasks /delete /tn ExodoNfceBridgeTask /f >nul 2>&1
schtasks /create /tn ExodoNfceBridgeTask /tr "\"%BRIDGE_DIR%\ExodoNfceBridge.exe\" --silent" /sc onlogon /rl highest /f >nul
if errorlevel 1 echo AVISO: nao foi possivel recriar a tarefa agendada ExodoNfceBridgeTask.

schtasks /delete /tn ExodoNfceBridgeWatchdog /f >nul 2>&1
if exist "%BRIDGE_DIR%\ExodoNfceBridgeWatchdog.exe" (
    schtasks /create /tn ExodoNfceBridgeWatchdog /tr "\"%BRIDGE_DIR%\ExodoNfceBridgeWatchdog.exe\"" /sc onlogon /rl highest /f >nul
    if errorlevel 1 echo AVISO: nao foi possivel recriar a tarefa ExodoNfceBridgeWatchdog.
)

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v ExodoNfceBridge /t REG_SZ /d "\"%BRIDGE_DIR%\ExodoNfceBridge.exe\" --silent" /f >nul
if errorlevel 1 echo AVISO: nao foi possivel atualizar a chave de inicializacao do Registro.

echo.
echo [5/5] Iniciando o bridge atualizado...
start "" /D "%BRIDGE_DIR%" "%BRIDGE_DIR%\ExodoNfceBridge.exe" --silent

timeout /t 8 /nobreak >nul
tasklist /FI "IMAGENAME eq ExodoNfceBridge.exe" | find /I "ExodoNfceBridge.exe" >nul
if errorlevel 1 (
    echo.
    echo ERRO: o bridge nao iniciou. Veja "%BRIDGE_DIR%\bridge_log.txt"
) else (
    echo.
    echo PRONTO! O bridge v%VERSION% esta rodando de %BRIDGE_DIR%
)
echo.
pause
exit /b 0

:deploy
if /I "%~1"=="%~2" exit /b 0
if exist "%~2" copy /Y "%~2" "%~2.bak_%STAMP%" >nul 2>&1
copy /Y "%~1" "%~2" >nul
if errorlevel 1 (
    echo AVISO: falha ao copiar para %~2
) else (
    echo   ok: %~2
)
exit /b 0

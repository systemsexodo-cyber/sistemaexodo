@echo off
echo.
echo ========================================================
echo Atualizador Manual do Bridge (Limpando Instancias)
echo ========================================================
echo.
>nul 2>&1 "%SYSTEMROOT%\system32\icacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Solicitando privilegios de administrador...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params= %*
    echo UAC.ShellExecute "cmd.exe", "/c ""%~s0"" %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

echo [1/3] Encerrando absolutamente tudo do Bridge...
taskkill /F /IM ExodoNfceBridge* /T >nul 2>&1
taskkill /F /IM python.exe /T >nul 2>&1

timeout /t 2 /nobreak >nul

echo [2/3] Buscando e instalando a versao mais recente...

set LATEST_BRIDGE=
for /f "tokens=*" %%F in ('cmd /c "dir /b /o-d backend_nfce\dist\ExodoNfceBridge_v*.exe 2^>nul"') do (
    if not defined LATEST_BRIDGE set LATEST_BRIDGE=%%F
)

set LATEST_WATCHDOG=
for /f "tokens=*" %%F in ('cmd /c "dir /b /o-d backend_nfce\dist\ExodoNfceBridgeWatchdog_v*.exe 2^>nul"') do (
    if not defined LATEST_WATCHDOG set LATEST_WATCHDOG=%%F
)

if defined LATEST_BRIDGE (
    echo Instalando %LATEST_BRIDGE%...
    copy /Y "backend_nfce\dist\%LATEST_BRIDGE%" "ExodoNfceBridge.exe" >nul
) else (
    echo ERRO: Arquivo ExodoNfceBridge_v*.exe nao encontrado em backend_nfce\dist!
)

if defined LATEST_WATCHDOG (
    echo Instalando %LATEST_WATCHDOG%...
    copy /Y "backend_nfce\dist\%LATEST_WATCHDOG%" "ExodoNfceBridgeWatchdog.exe" >nul
)

rem Faxina total: Limpa versoes intermediarias da pasta raiz para evitar confusao
del /Q ExodoNfceBridge_v*.exe 2>nul
del /Q ExodoNfceBridgeWatchdog_v*.exe 2>nul
del /Q ExodoNfceBridge.exe.new 2>nul
del /Q ExodoNfceBridge.exe.old 2>nul
del /Q bridge_log.txt.bak 2>nul

echo [3/3] Iniciando o Bridge atualizado...
start "" "ExodoNfceBridge.exe" --silent

echo.
echo PRONTO! O Bridge foi limpo e reiniciado.
echo Verifique o icone laranja no relogio.
pause

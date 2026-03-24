@echo off
echo.
echo ========================================================
echo Atualizador Manual do Bridge (Forcando permissao Admin)
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

echo Encerrando Bridge antigo...
taskkill /F /IM ExodoNfceBridge.exe >nul 2>&1
taskkill /F /IM ExodoNfceBridgeWatchdog.exe >nul 2>&1

timeout /t 2 /nobreak >nul

echo Copiando versao nova...
copy /Y backend_nfce\dist\ExodoNfceBridge_v340.exe ExodoNfceBridge.exe
copy /Y backend_nfce\dist\ExodoNfceBridgeWatchdog_v340.exe ExodoNfceBridgeWatchdog.exe


echo Iniciando novo Bridge...
start "" "ExodoNfceBridge.exe"

echo Completo! Pode fechar esta janela.
pause

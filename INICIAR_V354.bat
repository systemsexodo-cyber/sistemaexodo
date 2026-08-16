@echo off
cd /d "%~dp0"
echo ========================================
echo   INICIAR BRIDGE v354 (FIX CHAVE NF-e)
echo ========================================
echo.
echo CORRECAO: Numero da nota limitado a 9 digitos
echo             (chave de acesso 44 caracteres correta)
echo.

:: Parar versoes anteriores
taskkill /F /IM "ExodoNfceBridge_v353.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge_v352.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge_v351.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge.exe" /T 2>nul
timeout /t 2 /nobreak >nul

:: Verificar se existe v354
if exist "ExodoNfceBridge_v354.exe" (
    echo Encontrado: ExodoNfceBridge_v354.exe
    echo Iniciando...
    start "" "ExodoNfceBridge_v354.exe"
    goto :aguardar
)

echo ERRO: ExodoNfceBridge_v354.exe nao encontrado!
pause
exit /b 1

:aguardar
echo.
echo Aguardando iniciar (6 segundos)...
timeout /t 6 /nobreak >nul

:: Verificar se subiu
curl -s http://localhost:8000/health >nul 2>&1
if %errorlevel% == 0 (
    echo.
    echo Bridge v354 esta ONLINE!
    echo URL: http://localhost:8000
    echo.
    echo Agora pode emitir NF-e e NFC-e normalmente.
) else (
    echo.
    echo Bridge pode estar iniciando...
    echo Aguarde mais alguns segundos e verifique o icone na bandeja.
)
echo.
pause

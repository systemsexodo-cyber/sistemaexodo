@echo off
cd /d "%~dp0"
echo ========================================
echo   INICIAR BRIDGE v353 (SUPORTE IBS/CBS)
echo ========================================
echo.
echo NOVO: Suporte a transmissao de IBS/CBS
echo       (Reforma Tributaria NT 2025.002)
echo.

:: Parar versoes anteriores
taskkill /F /IM "ExodoNfceBridge_v352.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge_v351.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge_v350.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge.exe" /T 2>nul
timeout /t 2 /nobreak >nul

:: Verificar se existe v353
if exist "ExodoNfceBridge_v353.exe" (
    echo Encontrado: ExodoNfceBridge_v353.exe
    echo Iniciando...
    start "" "ExodoNfceBridge_v353.exe"
    goto :aguardar
)

echo ERRO: ExodoNfceBridge_v353.exe nao encontrado!
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
    echo Bridge v353 esta ONLINE!
    echo URL: http://localhost:8000
    echo.
    echo Agora pode emitir NFC-e normalmente.
) else (
    echo.
    echo Bridge pode estar iniciando...
    echo Aguarde mais alguns segundos e verifique o icone na bandeja.
)
echo.
pause

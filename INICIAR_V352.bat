@echo off
echo ========================================
echo   INICIAR BRIDGE v352 (CORRECAO HTTP 400)
echo ========================================
echo.
echo CORRECAO: XML infNFeSupl nao era malformado
echo           (bug: <infNFe versao="4.00"Supl> era gerado)
echo.

:: Parar versoes anteriores
taskkill /F /IM "ExodoNfceBridge_v351.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge_v350.exe" /T 2>nul
taskkill /F /IM "ExodoNfceBridge.exe" /T 2>nul
timeout /t 2 /nobreak >nul

:: Verificar se existe v352
if exist "ExodoNfceBridge_v352.exe" (
    echo Encontrado: ExodoNfceBridge_v352.exe
    echo Iniciando...
    start "" "ExodoNfceBridge_v352.exe"
    goto :aguardar
)

echo ERRO: ExodoNfceBridge_v352.exe nao encontrado!
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
    echo Bridge v352 esta ONLINE!
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

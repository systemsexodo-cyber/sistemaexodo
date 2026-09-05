@echo off
echo ========================================
echo INICIAR BRIDGE NFC-e
echo ========================================
echo.

:: Verificar se existe a versao v350
if exist "ExodoNfceBridge_v350.exe" (
    echo Encontrado: ExodoNfceBridge_v350.exe
    echo Iniciando bridge...
    start "" "ExodoNfceBridge_v350.exe"
    goto :fim
)

:: Verificar outras versoes
if exist "ExodoNfceBridge_v348.exe" (
    echo Encontrado: ExodoNfceBridge_v348.exe
    start "" "ExodoNfceBridge_v348.exe"
    goto :fim
)

if exist "ExodoNfceBridge.exe" (
    echo Encontrado: ExodoNfceBridge.exe
    start "" "ExodoNfceBridge.exe"
    goto :fim
)

echo ERRO: Nenhum executavel do bridge encontrado!
echo.
echo Verifique se o arquivo existe na pasta:
echo %cd%
echo.
pause
exit /b 1

:fim
echo.
echo Bridge iniciado! Aguarde 5 segundos...
timeout /t 5 /nobreak >nul
echo Verificando status...
curl -s http://localhost:8000/ >nul 2>&1
if %errorlevel% == 0 (
    echo.
    echo ✅ Bridge esta ONLINE em http://localhost:8000
) else (
    echo.
    echo ⚠️ Bridge pode estar iniciando ainda. Aguarde mais alguns segundos.
)
echo.
pause

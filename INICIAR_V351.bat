@echo off
echo ========================================
echo   INICIAR BRIDGE v351 (NOVA VERSAO)
echo ========================================
echo.

:: Verificar se existe v351
if exist "ExodoNfceBridge_v351.exe" (
    echo Encontrado: ExodoNfceBridge_v351.exe
    echo Iniciando...
    start "" "ExodoNfceBridge_v351.exe"
    goto :aguardar
)

:: Se nao existe, tentar gerar automaticamente
echo ❌ ExodoNfceBridge_v351.exe nao encontrado!
echo.
echo Deseja gerar a nova versao agora? (S/N)
set /p resposta=
if /i "%resposta%"=="S" (
    call GERAR_NOVA_VERSAO.bat
) else (
    echo.
    echo Usando versao anterior v350...
    if exist "ExodoNfceBridge_v350.exe" (
        start "" "ExodoNfceBridge_v350.exe"
        goto :aguardar
    ) else (
        echo ❌ Nenhuma versao encontrada!
        pause
        exit /b 1
    )
)

:aguardar
echo.
echo Aguardando iniciar (5 segundos)...
timeout /t 5 /nobreak >nul

:: Verificar se subiu
curl -s http://localhost:8000/ >nul 2>&1
if %errorlevel% == 0 (
    echo.
    echo ✅ Bridge v351 esta ONLINE!
    echo URL: http://localhost:8000
) else (
    echo.
    echo ⚠️ Bridge pode estar iniciando...
    echo Aguarde mais alguns segundos e verifique o icone na bandeja.
)
echo.
pause

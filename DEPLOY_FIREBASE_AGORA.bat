@echo off
setlocal
cd /d "%~dp0"

echo ========================================
echo   DEPLOY FIREBASE HOSTING - SISTEMA EXODO
echo ========================================
echo.

REM ---- 1. Login (somente se ainda nao houver conta autorizada) ----
echo [1/3] Verificando login no Firebase...
call npx firebase login:list 2>&1 | findstr /C:"No authorized accounts" >nul
if not errorlevel 1 (
    echo   Nenhuma conta autorizada. Abrindo o navegador para login...
    call npx firebase login
    if errorlevel 1 (
        echo.
        echo   ERRO: login nao concluido. Rode de novo este arquivo.
        pause
        exit /b 1
    )
) else (
    echo   OK: conta ja autorizada.
)

REM ---- 2. Build web ----
REM --no-wasm-dry-run: o dry-run do Wasm reprova o import de dart:ffi usado
REM apenas pelo app desktop (ffi/win32), quebrando o build JS sem essa flag.
echo.
echo [2/3] Gerando build web (pode levar alguns minutos)...
call flutter build web --release --no-wasm-dry-run
if errorlevel 1 (
    echo.
    echo   ERRO: falha no build web.
    pause
    exit /b 1
)

REM ---- 3. Deploy (apenas hosting: nao mexe nas Cloud Functions) ----
echo.
echo [3/3] Enviando para o Firebase Hosting...
call npx firebase deploy --only hosting --project exodosystems-1541d
if errorlevel 1 (
    echo.
    echo   ERRO: falha no deploy. Verifique se a conta tem acesso ao projeto.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   DEPLOY CONCLUIDO COM SUCESSO
echo ========================================
echo   Sistema: https://exodosystems-1541d.web.app
echo   Portal:  https://exodosystems-1541d.web.app/portal-contador
echo.
pause

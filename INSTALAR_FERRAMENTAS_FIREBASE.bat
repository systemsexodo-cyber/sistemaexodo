@echo off
echo ========================================
echo   INSTALADOR DE FERRAMENTAS FIREBASE
echo ========================================
echo.

REM Verificar Node.js
where node >nul 2>&1
if errorlevel 1 (
    echo [!] Node.js nao encontrado!
    echo [!] Por favor, instale o Node.js em: https://nodejs.org/
    echo.
    echo Pressione qualquer tecla para abrir o site do Node.js...
    pause >nul
    start https://nodejs.org/
    exit /b 1
)

echo [OK] Node.js detectado.
echo.

echo Instalando Firebase Tools globalmente...
echo Executando: npm install -g firebase-tools
echo Isso pode demorar um pouco...
echo.

call npm install -g firebase-tools

if errorlevel 1 (
    echo.
    echo [X] Erro ao instalar Firebase Tools.
    echo [!] Tente executar este script como Administrador.
) else (
    echo.
    echo [OK] Firebase Tools instalado com sucesso!
    echo.
    echo Agora voce precisa fazer login:
    echo Executando: firebase login
    call firebase login
)

echo.
echo ========================================
echo   PROCESSO FINALIZADO
echo ========================================
echo.
pause

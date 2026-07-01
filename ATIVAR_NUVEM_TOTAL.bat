@echo off
echo ========================================
echo   ATIVANDO SISTEMA 100%% NA NUVEM
echo   (VERSAO DE DIAGNOSTICO)
echo ========================================
echo.

cd /d "%~dp0"

echo [1/5] Verificando Node.js...
where node >nul 2>&1
if errorlevel 1 (
    echo [!] ERRO: Node.js nao encontrado. Instale em nodejs.org
    pause
    exit /b 1
)
echo [OK] Node encontrado.

echo.
echo [2/5] Verificando Firebase...
echo Aguarde, verificando login...
cmd /c "npx -y firebase-tools projects:list" > %temp%\fb_check.txt 2>&1
if errorlevel 1 (
    echo [!] ERRO: Voce nao esta logado ou o projeto nao existe.
    echo [!] Por favor, digite no terminal: npx firebase login
    type %temp%\fb_check.txt
    pause
    exit /b 1
)
echo [OK] Firebase autenticado.

echo.
echo [3/5] Validando scripts Python...
if not exist functions_py\main.py (
    echo [!] ERRO: Arquivo functions_py\main.py nao encontrado!
    pause
    exit /b 1
)
echo [OK] Arquivos presentes.

echo.
echo [4/5] INICIANDO DEPLOY (Isso demora 3-5 minutos)...
echo.
echo [ATENCAO] Se o deploy falhar aqui, verifique se o seu 
echo [ATENCAO] plano no Firebase e o BLAZE.
echo.

cmd /c "npx -y firebase-tools deploy --only functions --project exodosystems-1541d"

if errorlevel 0 (
    echo.
    echo ========================================
    echo   PROCESSO FINALIZADO!
    echo ========================================
    echo Verifique acima se o status foi "SUCCESS".
) else (
    echo.
    echo [!] Ocorreu um erro durante o envio para o Google.
)

echo.
echo Pressione qualquer tecla para fechar esta janela...
pause > nul

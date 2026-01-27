@echo off
setlocal enabledelayedexpansion
title SISTEMA EXODO - GIT MANAGER

:: Garantir que o script rode na pasta onde ele esta localizado
cd /d "%~dp0"

:menu
cls
echo =========================================================
echo          SISTEMA EXODO - GERENCIADOR GIT
echo =========================================================
echo.
echo Diretorio atual: %CD%
echo.
echo 1. [AUTO] Salvar e Enviar tudo
echo 2. Sincronizar (Pull)
echo 3. Ver Status
echo 4. Preparar Deploy (Main)
echo Q. Sair
echo.
set choice=
set /p choice="Escolha uma opcao: "

if "%choice%"=="1" goto autopush
if "%choice%"=="2" goto pull
if "%choice%"=="3" goto status
if "%choice%"=="4" goto deploy
if "%choice%"=="q" goto end
if "%choice%"=="Q" goto end
echo Opcao invalida!
pause
goto menu

:autopush
echo.
echo [PASSO 1] Verificando Git...
git rev-parse --is-inside-work-tree >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERRO: Esta pasta nao e um repositorio Git!
    echo Certifique-se de que o arquivo .bat esteja na pasta raiz do projeto.
    pause
    goto menu
)

echo.
echo [PASSO 2] Adicionando arquivos...
git add .
if %ERRORLEVEL% NEQ 0 (
    echo ERRO ao adicionar arquivos!
    pause
    goto menu
)

echo.
echo [PASSO 3] Criando commit...
echo Digite sua mensagem (simples, sem aspas):
set /p commit_msg="Mensagem: "
if "!commit_msg!"=="" set commit_msg=atualizacao automatica

git commit -m "feat: !commit_msg!"
if %ERRORLEVEL% NEQ 0 (
    echo AVISO: Nada novo para salvar ou erro no commit.
)

echo.
echo [PASSO 4] Enviando para o GitHub...
git push origin HEAD
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo ERRO NO PUSH! Verifique internet ou permissao.
    echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    pause
    goto menu
)

echo.
echo vv SUCESSO! Alteracoes enviadas. vv
pause
goto menu

:pull
echo.
git pull
pause
goto menu

:status
echo.
git status
echo.
echo --- ULTIMOS COMMITS ---
git log --oneline -n 5
pause
goto menu

:deploy
echo.
echo Fazendo deploy para MAIN...
for /f "tokens=*" %%i in ('git branch --show-current') do set current=%%i
git checkout main
git merge %current%
git push origin main
git checkout %current%
echo.
echo v Deploy concluido!
pause
goto menu

:end
exit

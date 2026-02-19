@echo off
chcp 1252 >nul
setlocal enabledelayedexpansion
title SISTEMA EXODO - GIT MANAGER PRO

:: Garantir que o script rode na pasta onde ele esta localizado
cd /d "%~dp0"

:menu
cls
echo =========================================================
echo          SISTEMA EXODO - GERENCIADOR GIT PRO
echo =========================================================
for /f "tokens=*" %%i in ('git branch --show-current') do set current_branch=%%i
echo Branch Atual: !current_branch!
echo Diretorio: %CD%
echo =========================================================
echo.
echo 1. [DEV] Salvar e Enviar trabalho (Commit + Push)
echo 2. [SYNC] Sincronizar (Trazer mudancas do GitHub)
echo 3. [STATUS] Ver historico e alteracoes
echo 4. [DEPLOY] Publicar para Producao (Site Online)
echo 5. [UNDO] DESFAZER ultima alteracao (Emergencia)
echo Q. Sair
echo.
set choice=
set /p choice="Escolha uma opcao: "

if "%choice%"=="1" goto autopush
if "%choice%"=="2" goto pull
if "%choice%"=="3" goto status
if "%choice%"=="4" goto deploy
if "%choice%"=="5" goto undo
if "%choice%"=="q" goto end
if "%choice%"=="Q" goto end
echo Opcao invalida!
pause
goto menu

:autopush
echo.
echo [CONFIG] Verificando identidade Git...
git config user.email >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Configurando identidade temporaria...
    git config --local user.name "Usuario Exodo"
    git config --local user.email "usuario@exodo.com"
)

echo [PASSO 1] Preparando arquivos...
rem Primeiro, tenta salvar mudanças em submodulos conhecidos
if exist "backend_pynfe\pynfe_dev\.git" (
    echo ^>^>^> Verificando submodulo backend_pynfe\pynfe_dev...
    cd backend_pynfe\pynfe_dev
    git add .
    git commit -m "atualizacao automatica submodule" >nul 2>&1
    cd ..\..
)

git add .

echo [PASSO 2] Criando ponto de salvamento...
echo Digite o que voce fez (ex: ajuste no login):
set /p commit_msg="Mensagem: "
if "!commit_msg!"=="" set commit_msg=atualizacao automatica

git commit -m "feat: !commit_msg!"
if %ERRORLEVEL% NEQ 0 (
    rem Se o commit falhou, pode ser que nao tenha nada para salvar
    git status | findstr "nothing to commit" >nul
    if !ERRORLEVEL! EQU 0 (
        echo.
        echo Sem alteracoes novas para salvar.
    ) else (
        echo.
        echo !!! ERRO AO CRIAR PONTO DE SALVAMENTO !!!
        echo Verifique os arquivos ou sua identidade git.
        pause
        goto menu
    )
)

echo [PASSO 3] Enviando para o Porto Seguro (GitHub)...
git push origin HEAD
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo !!! ERRO NO ENVIO !!!
    echo Verifique sua internet ou se ha conflitos.
    pause
    goto menu
)
echo.
echo vv SUCESSO! Trabalho salvo e enviado. vv
pause
goto menu

:pull
echo.
echo >>> Buscando novidades no GitHub...
git pull origin HEAD
pause
goto menu

:status
echo.
echo === SEUS ULTIMOS SALVAMENTOS ===
git log --oneline -n 10
echo.
echo === ARQUIVOS MUDADOS AGORA ===
git status -s
pause
goto menu

:deploy
echo.
echo !!! ATENCAO: Isso vai atualizar o SITE OFICIAL !!!
set /p conf="Tem certeza que deseja publicar? (s/n): "
if /i "!conf!" NEQ "s" goto menu

echo >>> Entrando na branch de Producao...
git checkout Produção
echo >>> Unindo seu trabalho novo...
git merge modo-dev
echo >>> Enviando para o site...
git push origin Produção
echo >>> Voltando para o modo de trabalho...
git checkout modo-dev
echo.
echo vv PUBLICADO COM SUCESSO! O site esta atualizado. vv
pause
goto menu

:undo
echo.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo    AVISO: Isso vai apagar seu ULTIMO salvamento LOCAL
echo    e voltar o seu codigo para como estava antes dele.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
set /p undoconf="Deseja mesmo DESFAZER? (s/n): "
if /i "!undoconf!" NEQ "s" goto menu

echo >>> Voltando no tempo (1 versao)...
git reset --hard HEAD~1
echo.
echo <<< VOLTOU! Seu codigo agora esta como estava antes do ultimo commit.
echo NOTA: Se voce ja tinha enviado para o GitHub, o site ainda tera a versao com erro.
echo Faca um novo salvamento (Opcao 1) para corrigir o GitHub tambem.
pause
goto menu

:end
goto :eof

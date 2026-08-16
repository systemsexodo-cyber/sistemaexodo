@echo off
title Iniciar PostgreSQL - Sistema Exodo
chcp 65001 >nul
echo ============================================
echo    INICIAR POSTGRESQL - SISTEMA EXODO
echo ============================================
echo.

rem APP = pasta onde o bat foi instalado (scripts\.. = raiz do sistema), funciona em qualquer pasta de instalacao
set "APP=%~dp0.."
set "PGC=%APP%\postgresql\bin\pg_ctl.exe"
set "PGREADY=%APP%\postgresql\bin\pg_isready.exe"
set "DATA=%APP%\pgdata"
set "LOG=%APP%\logs\postgresql.log"

echo Verificando se o PostgreSQL ja esta rodando...
netstat -ano | findstr /C:":5432 " >nul 2>&1
if %errorlevel%==0 (
    echo.
    echo PostgreSQL JA ESTA RODANDO na porta 5432. Nada a fazer.
    echo.
    goto :fim
)

echo PostgreSQL NAO esta rodando. Tentando iniciar...
echo.

if not exist "%PGC%" (
    echo ERRO: PostgreSQL nao encontrado em %PGC%
    echo Verifique se o sistema foi instalado corretamente.
    echo.
    goto :fim
)

if not exist "%DATA%\postgresql.conf" (
    echo ERRO: Cluster de dados nao encontrado em %DATA%
    echo Execute o instalador novamente para configurar o banco.
    echo.
    goto :fim
)

rem --- Remove postmaster.pid obsoleto (se o PC desligou com o banco aberto) ---
if exist "%DATA%\postmaster.pid" (
    tasklist | findstr /I "postgres.exe" >nul 2>&1
    if errorlevel 1 (
        echo       Removendo postmaster.pid obsoleto (banco nao esta rodando)...
        del /q "%DATA%\postmaster.pid" 2>nul
    )
)

echo [1/2] Tentando iniciar via servico do Windows...
sc start PostgreSQL_Exodo >nul 2>&1
if %errorlevel%==0 (
    echo       Servico iniciado!
) else (
    echo       Servico indisponivel, iniciando manualmente...
    "%PGC%" -D "%DATA%" -l "%LOG%" start -w -t 30
)

echo.
echo [2/2] Testando conexao...
"%PGREADY%" -h localhost -p 5432 -q >nul 2>&1
if %errorlevel%==0 (
    echo.
    echo ============================================
    echo    SUCESSO! PostgreSQL rodando e conectado!
    echo ============================================
    echo   Host:  localhost
    echo   Porta: 5432
    echo   Banco: exodo_db
    echo   Usuario: exodo_user
    echo   Senha: ex@#$
    echo.
    echo O Sincronizador Nuvem deve ficar verde em
    echo alguns segundos. Se continuar vermelho,
    echo reinicie o computador.
    echo ============================================
) else (
    echo.
    echo ATENCAO: PostgreSQL iniciou mas a conexao falhou.
    echo Veja o log: %LOG%
    echo Log de instalacao: %APP%\logs\postgres_install.log
)

:fim
echo.
pause

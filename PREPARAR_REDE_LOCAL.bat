@echo off
setlocal EnableExtensions
title Sistema Exodo - Preparar este PC na rede
cd /d "%~dp0"

rem ============================================================================
rem  PREPARAR_REDE_LOCAL.bat
rem
rem  Rodar ESTE arquivo em CADA computador da loja, como ADMINISTRADOR.
rem
rem  Ele faz tudo de uma vez:
rem    1. libera o PostgreSQL deste PC para a rede local
rem       listen_addresses, pg_hba.conf e a porta 5432 no Firewall
rem    2. sobe o servico do PostgreSQL se ele estiver parado
rem    3. confere se a porta 5432 ficou escutando e se o banco responde
rem
rem  Sem isso o outro PC recebe "connection refused" na porta 5432 e nunca
rem  sincroniza - que e o caso de um PC que ficou com o servico parado.
rem
rem  IMPORTANTE (cmd): nenhum ECHO dentro de bloco if/else pode ter
rem  parenteses, senao o proprio cmd quebra o arquivo INTEIRO ao parsear.
rem ============================================================================

rem --- Precisa de administrador: mexe em .conf, Firewall e servico do Windows ---
net session >nul 2>&1
if not "%errorlevel%"=="0" fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Pedindo permissao de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo ============================================================
echo    SISTEMA EXODO - PREPARAR ESTE PC PARA A REDE LOCAL
echo ============================================================
echo.
echo  1. Deixa o PostgreSQL deste PC escutando na rede local
echo  2. Libera a entrada dos outros PCs da loja
echo  3. Sobe o banco se ele estiver parado
echo  4. Confirma que ficou tudo no ar
echo.
echo  Rode este arquivo em CADA computador da loja.
echo  Nao precisa informar o IP de ninguem.
echo.

set "PS1=%~dp0scripts\configurar_lan_postgres.ps1"
if not exist "%PS1%" goto :sem_script

echo [1/4] Configurando o PostgreSQL para a rede local...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if errorlevel 1 goto :falha_config

echo.
echo [2/4] Garantindo que o servico do PostgreSQL esta no ar...
call :sobe_servico

echo.
echo [3/4] Conferindo a porta 5432...
call :confere_porta

echo.
echo [4/4] Testando o banco local...
call :testa_banco

echo.
echo ============================================================
echo    PRONTO NESTE PC
echo ============================================================
echo  Agora abra o Sistema Exodo: Configuracoes - Rede LAN -
echo  Procurar PCs, e escolha o outro computador.
echo.
echo  Para desfazer, os arquivos .conf ficaram salvos como .bak_lan.
echo.
goto :fim

rem ---------------------------- sub-rotinas ----------------------------

:sobe_servico
set "SVC="
for /f "tokens=3" %%s in ('sc query type^= service state^= all 2^>nul ^| findstr /I /C:"PostgreSQL"') do if not defined SVC set "SVC=%%s"
if not defined SVC goto :fim_sobe
rem Deixa o servico iniciar sozinho depois de reiniciar o PC. Servico em
rem "Manual" e a causa comum do banco ficar parado de um dia para o outro.
sc config "%SVC%" start= auto >nul 2>&1
sc query "%SVC%" | findstr /I "RUNNING" >nul 2>&1
if not errorlevel 1 goto :fim_sobe
echo       Iniciando o servico %SVC%...
sc start "%SVC%" >nul 2>&1
timeout /t 3 /nobreak >nul
:fim_sobe
goto :eof

:confere_porta
netstat -ano | findstr /C:":5432" | findstr /I "LISTENING" >nul 2>&1
if errorlevel 1 goto :porta_ruim
echo       Porta 5432 escutando - outros PCs ja conseguem entrar.
goto :eof
:porta_ruim
echo       AVISO: ninguem escutando na porta 5432.
echo       O outro PC ainda nao conecta. Reinicie o computador
echo       e rode este arquivo de novo.
goto :eof

:testa_banco
if not exist "%~dp0postgresql\bin\psql.exe" goto :sem_psql
set "PGPASSWORD="
set "PGUSR=exodo_user"
set "PGDB=exodo_db"
set "PGRDP=5432"
for /f "usebackq tokens=1,* delims==" %%a in (".env") do (
    if "%%a"=="DB_PASSWORD" set "PGPASSWORD=%%b"
    if "%%a"=="DB_USER" set "PGUSR=%%b"
    if "%%a"=="DB_NAME" set "PGDB=%%b"
    if "%%a"=="DB_PORT" set "PGRDP=%%b"
)
if not defined PGPASSWORD goto :sem_psql
set "PGPASSWORD=%PGPASSWORD%"
"%~dp0postgresql\bin\psql.exe" -h 127.0.0.1 -p %PGRDP% -U %PGUSR% -d %PGDB% -t -c "select 1" >nul 2>&1
if not errorlevel 1 goto :banco_ok
echo       Banco local nao respondeu - veja o log do PostgreSQL.
goto :eof
:banco_ok
echo       Banco local respondendo.
goto :eof
:sem_psql
echo       psql ou .env nao encontrado - pulando o teste do banco.
goto :eof

rem ---------------------------- erros / fim ----------------------------

:sem_script
echo.
echo ERRO: nao achei scripts\configurar_lan_postgres.ps1 nesta pasta.
echo Rode o instalador do Sistema Exodo novamente.
goto :encerra

:falha_config
echo.
echo ERRO: a configuracao do PostgreSQL falhou. Leia as mensagens acima.
goto :encerra

:encerra
echo.
pause
exit /b 1

:fim
echo.
pause
exit /b 0

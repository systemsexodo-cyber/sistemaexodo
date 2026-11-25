@echo off
REM ===========================================================================
REM  INICIAR_EVOLUTION.bat
REM
REM  Mantem a Evolution API publica depois de um reboot do PC:
REM
REM    1) espera a VM "Ubuntu-Supabase" estar rodando (o
REM       INICIAR_FUNNEL_SUPABASE.bat tambem sobe ela - a ordem nao importa);
REM    2) recria a regra de NAT 127.0.0.1:8093 -> VM:8093. A regra criada em
REM       runtime NAO fica salva na configuracao da VM e o "VBoxManage
REM       modifyvm" recusa com a VM ligada; por isso ela e refeita aqui;
REM    3) espera o nginx do container evo_proxy responder na 8093;
REM    4) (re)aplica o Funnel /evolution -> 127.0.0.1:8093.
REM
REM  Os containers (evo_api, evo_proxy, evo_postgres, evo_redis) sobem
REM  sozinhos: estao com restart=unless-stopped e o Docker esta habilitado
REM  no boot da VM.
REM
REM  INSTALACAO (uma vez so):
REM    Win+R -> shell:startup -> Enter
REM    e coloque um ATALHO deste arquivo nessa pasta.
REM
REM  Log: logs\evolution.log
REM ===========================================================================

setlocal enabledelayedexpansion

set "VBOXMANAGE=C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
set "TAILSCALE=C:\Program Files\Tailscale\tailscale.exe"
set "VM=Ubuntu-Supabase"
set "PORTA_EVO=8093"
set "ROTA_EVO=/evolution"
set "LOG=%~dp0logs\evolution.log"

if not exist "%~dp0logs" mkdir "%~dp0logs"
call :log "=========================================================="
call :log "Iniciando Evolution API (Funnel %ROTA_EVO% -> 127.0.0.1:%PORTA_EVO%)"

REM --- 1) espera a VM ---------------------------------------------------------
call :log "Esperando a VM '%VM%' ficar rodando (max 5 min)..."
set /a TENT=0
:espera_vm
"%VBOXMANAGE%" showvminfo "%VM%" --machinereadable 2>nul | findstr /b /c:"VMState=" | findstr /c:"running" >nul
if not errorlevel 1 goto vm_ok
set /a TENT+=1
if %TENT% geq 60 (
  call :log "ERRO: a VM '%VM%' nao ficou rodando em 5 minutos."
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto espera_vm
:vm_ok
call :log "VM ok."

REM --- 2) regra de NAT (refeita a cada boot) ----------------------------------
"%VBOXMANAGE%" showvminfo "%VM%" --machinereadable 2>nul | findstr /c:"evolution,tcp" >nul
if not errorlevel 1 (
  call :log "Regra de NAT da porta %PORTA_EVO% ja existe."
) else (
  call :log "Criando regra de NAT 127.0.0.1:%PORTA_EVO% -> VM:%PORTA_EVO%..."
  "%VBOXMANAGE%" controlvm "%VM%" natpf1 "evolution,tcp,127.0.0.1,%PORTA_EVO%,,%PORTA_EVO%" >> "%LOG%" 2>&1
  if errorlevel 1 (
    call :log "ERRO: nao consegui criar a regra de NAT."
    exit /b 1
  )
)

REM --- 2b) regra de NAT do bot (pausa/teste pelo app) --------------------------
"%VBOXMANAGE%" showvminfo "%VM%" --machinereadable 2>nul | findstr /c:"bot,tcp" >nul
if not errorlevel 1 (
  call :log "Regra de NAT do bot (8097) ja existe."
) else (
  call :log "Criando regra de NAT 127.0.0.1:8097 -> VM:8097 (bot)..."
  "%VBOXMANAGE%" controlvm "%VM%" natpf1 "bot,tcp,127.0.0.1,8097,,8097" >> "%LOG%" 2>&1
)

REM --- 3) espera o proxy do Evolution -----------------------------------------
call :log "Esperando a Evolution (%PORTA_EVO%) responder (max 5 min)..."
set /a TENT=0
:espera_evo
powershell -NoProfile -Command "try { (New-Object System.Net.Sockets.TcpClient('127.0.0.1',%PORTA_EVO%)).Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto evo_ok
set /a TENT+=1
if %TENT% geq 60 (
  call :log "ERRO: a porta %PORTA_EVO% nao respondeu em 5 minutos. Veja 'docker compose ps' em ~/evolution na VM."
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto espera_evo
:evo_ok
call :log "Evolution ok em 127.0.0.1:%PORTA_EVO%."

REM --- 4) Funnel --------------------------------------------------------------
call :log "Esperando o Tailscale ficar conectado..."
set /a TENT=0
:espera_ts
"%TAILSCALE%" status >nul 2>&1
if not errorlevel 1 goto ts_ok
set /a TENT+=1
if %TENT% geq 36 (
  call :log "ERRO: Tailscale nao respondeu em 3 minutos (deslogado?)."
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto espera_ts
:ts_ok
call :log "Aplicando o Funnel %ROTA_EVO%..."
"%TAILSCALE%" funnel --bg --set-path %ROTA_EVO% http://127.0.0.1:%PORTA_EVO% >> "%LOG%" 2>&1
if errorlevel 1 (
  call :log "ERRO: 'tailscale funnel' falhou. Veja o log acima."
  exit /b 1
)

call :log "Status do Funnel:"
"%TAILSCALE%" funnel status >> "%LOG%" 2>&1
call :log "Pronto: Evolution publica em https://%COMPUTERNAME%.tail9b4943.ts.net%ROTA_EVO%"
exit /b 0

REM --------------------------------------------------------------------------
:log
echo [%date% %time%] %* >> "%LOG%"
exit /b 0

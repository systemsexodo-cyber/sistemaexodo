@echo off
REM ===========================================================================
REM  INICIAR_FUNNEL_SUPABASE.bat
REM
REM  Mantem a "nuvem local" disponivel depois de um reboot do PC:
REM
REM    1) sobe a VM "Ubuntu-Supabase" (Supabase local) se nao estiver rodando;
REM    2) espera a porta 5434 (Postgres dentro da VM) responder;
REM    3) sobe o PORTAL (scripts\portal_nuvem.py) na porta 8090;
REM    4) (re)aplica o Tailscale Funnel: 10000 -> 127.0.0.1:5434;
REM    5) confere o status do Funnel no fim.
REM
REM  Sem isto, apos um reboot a VM fica desligada e o Funnel aponta para uma
REM  porta morta: o celular FORA da loja perde o fallback de nuvem.
REM
REM  POR QUE O PORTAL EXISTE
REM  O navegador (Chrome 142+) bloqueia pagina publica chamando endereco local
REM  ("Permission was denied ... local address space"). Servindo o portal e a
REM  API no MESMO host do Funnel, a requisicao vira mesma origem e o bloqueio
REM  deixa de existir. O portal entrega build\web e repassa /rest/v1 para o
REM  Kong local (127.0.0.1:8001).
REM
REM  INSTALACAO (uma vez so):
REM    Win+R  ->  shell:startup  ->  Enter
REM    e coloque um ATALHO deste arquivo nessa pasta. Roda no logon do usuario,
REM    sem precisar de administrador. (O autostart nativo do VirtualBox nao foi
REM    usado porque o VBoxAutostartSvc exige a senha do Windows guardada em
REM    arquivo - e o Funnel precisa que o usuario esteja logado de qualquer
REM    forma, ja que ele roda no tailscaled dessa sessao.)
REM
REM  Log: logs\funnel_supabase.log
REM ===========================================================================

setlocal enabledelayedexpansion

set "VBOXMANAGE=C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
set "TAILSCALE=C:\Program Files\Tailscale\tailscale.exe"
set "VM=Ubuntu-Supabase"
set "PORTA_DB=5434"
set "PORTA_FUNNEL=10000"
set "PORTA_PORTAL=8090"
set "PORTAL=%~dp0scripts\portal_nuvem.py"
set "LOG=%~dp0logs\funnel_supabase.log"

if not exist "%~dp0logs" mkdir "%~dp0logs"
call :log "=========================================================="
call :log "Iniciando VM Supabase local + Funnel (%PORTA_FUNNEL% -> %PORTA_DB%)"

REM --- 1) VM -----------------------------------------------------------------
"%VBOXMANAGE%" showvminfo "%VM%" --machinereadable 2>nul | findstr /b /c:"VMState=" | findstr /c:"running" >nul
if not errorlevel 1 (
  call :log "VM '%VM%' ja esta rodando."
) else (
  call :log "VM '%VM%' nao esta rodando - subindo em modo headless..."
  "%VBOXMANAGE%" startvm "%VM%" --type headless >> "%LOG%" 2>&1
  if errorlevel 1 (
    call :log "ERRO: nao consegui iniciar a VM. Abra o VirtualBox uma vez."
    exit /b 1
  )
)

REM --- 2) espera a porta do Postgres -----------------------------------------
call :log "Esperando a porta %PORTA_DB% responder (max 5 min)..."
set /a TENT=0
:espera_porta
powershell -NoProfile -Command "try { (New-Object System.Net.Sockets.TcpClient('127.0.0.1',%PORTA_DB%)).Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto porta_ok
set /a TENT+=1
if %TENT% geq 60 (
  call :log "ERRO: porta %PORTA_DB% nao respondeu em 5 minutos."
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto espera_porta
:porta_ok
call :log "Porta %PORTA_DB% ok."

REM --- 3) espera o Tailscale e aplica o Funnel -------------------------------
call :log "Esperando o Tailscale ficar conectado..."
set /a TENT=0
:espera_tailscale
"%TAILSCALE%" status >nul 2>&1
if not errorlevel 1 goto tailscale_ok
set /a TENT+=1
if %TENT% geq 36 (
  call :log "ERRO: Tailscale nao respondeu em 3 minutos (deslogado?)."
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto espera_tailscale
:tailscale_ok
call :log "Tailscale ok - aplicando o Funnel..."
"%TAILSCALE%" funnel --bg --tls-terminated-tcp=%PORTA_FUNNEL% tcp://127.0.0.1:%PORTA_DB% >> "%LOG%" 2>&1
if errorlevel 1 (
  call :log "ERRO: 'tailscale funnel' falhou. Veja o log acima."
  exit /b 1
)

REM --- 3b) Portal + API na MESMA origem (porta %PORTA_PORTAL%) -------------
call :log "Verificando o portal na porta %PORTA_PORTAL%..."
powershell -NoProfile -Command "try { (New-Object System.Net.Sockets.TcpClient('127.0.0.1',%PORTA_PORTAL%)).Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto portal_pronto
call :log "Portal nao esta rodando - subindo em segundo plano..."
start "" pythonw "%PORTAL%"
set /a TENT=0
:espera_portal
powershell -NoProfile -Command "try { (New-Object System.Net.Sockets.TcpClient('127.0.0.1',%PORTA_PORTAL%)).Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto portal_pronto
set /a TENT+=1
if %TENT% geq 15 (
  call :log "ERRO: o portal nao respondeu na porta %PORTA_PORTAL% em 30s."
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto espera_portal
:portal_pronto
call :log "Portal ok (http://127.0.0.1:%PORTA_PORTAL% -> build\web + /rest/v1)."

REM --- 3c) Funnel HTTPS: site e API no mesmo host --------------------------
call :log "Aplicando o Funnel HTTPS para o portal (mesma origem da API)..."
"%TAILSCALE%" funnel --bg http://127.0.0.1:%PORTA_PORTAL% >> "%LOG%" 2>&1
if errorlevel 1 (
  call :log "ERRO: 'tailscale funnel https' falhou. Veja o log acima."
  exit /b 1
)

REM --- 4) confere ------------------------------------------------------------
call :log "Status do Funnel:"
"%TAILSCALE%" funnel status >> "%LOG%" 2>&1
call :log "Pronto: %COMPUTERNAME% publica o portal + API no Funnel (porta %PORTA_FUNNEL% = Postgres)."
exit /b 0

REM --------------------------------------------------------------------------
:log
echo [%date% %time%] %* >> "%LOG%"
exit /b 0

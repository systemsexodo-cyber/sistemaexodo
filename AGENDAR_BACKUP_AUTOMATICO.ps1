<#
.SYNOPSIS
    Agenda backup automatico do PostgreSQL no Windows Task Scheduler
.DESCRIPTION
    Cria tarefas no Agendador de Tarefas do Windows para:
    - Backup DIARIO: Todos os dias as 03:00 (madrugada)
    - Backup na INICIALIZACAO: Quando o computador liga

    Os backups sao salvos em C:\ExodoBackups (fora da pasta do app,
    para sobreviver a reinstalacao do sistema).
.PARAMETER Silencioso
    Executa sem pausa no final (usado pelo instalador).
.NOTES
    Autor: Sistema Exodo
    Versao: 1.1.0
    Execute como ADMINISTRADOR!
#>

param(
    [switch]$Silencioso
)

# ============================================================
# CONFIGURACOES
# ============================================================
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptBackup = Join-Path $ProjectRoot "backup_postgresql.ps1"
$TaskNameDiario = "Exodo Backup Diario"
$TaskNameStartup = "Exodo Backup Inicializacao"
$TaskDescription = "Backup automatico do banco PostgreSQL do Sistema Exodo"
$BackupDir = "C:\ExodoBackups"

# Garantir que o diretorio de backups existe
if (-not (Test-Path $BackupDir)) {
    try { New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null }
    catch { Write-Host "AVISO: nao foi possivel criar $BackupDir - $($_.Exception.Message)" -ForegroundColor Yellow }
}

# ============================================================
# FUNCOES
# ============================================================

function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "    $Title" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message, [string]$Status = "[..]")
    Write-Host " $Status $Message" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Message)
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "   [ERRO] $Message" -ForegroundColor Red
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TaskExists {
    param([string]$TaskName)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    return ($null -ne $task)
}
function New-BackupTask {
    param(
        [string]$TaskName,
        [string]$Description,
        [string]$TriggerType,  # "daily" ou "startup"
        [string]$Hora = "03:00"  # Apenas para daily
    )

    Write-Step "Criando tarefa: $TaskName"

    # Verificar se ja existe
    if (Get-TaskExists -TaskName $TaskName) {
        Write-Step "Tarefa '$TaskName' ja existe. Removendo para recriar..." "[-]"
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-OK "Tarefa antiga removida."
    }

    # Acao: executar PowerShell com o script de backup
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptBackup`" -Modo completo -DiretorioBackup `"$BackupDir`""

    # Trigger
    if ($TriggerType -eq "daily") {
        $trigger = New-ScheduledTaskTrigger -Daily -At $Hora
        Write-Step "   Agendado para: Diario as $Hora"
    } elseif ($TriggerType -eq "startup") {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $trigger.Delay = "PT2M"  # Aguardar 2 minutos apos inicializacao
        Write-Step "   Agendado para: Na inicializacao do Windows (com delay de 2min)"
    }

    # Configuracoes
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -WakeToRun:$true `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5)

    # Criar tarefa como SYSTEM para rodar mesmo sem usuario logado
    try {
        $task = Register-ScheduledTask `
            -TaskName $TaskName `
            -Description $Description `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -RunLevel Highest `
            -User "SYSTEM" `
            -Force

        Write-OK "Tarefa '$TaskName' criada com sucesso!"

        # Mostrar detalhes
        $taskInfo = Get-ScheduledTask -TaskName $TaskName
        $taskState = $taskInfo.State
        Write-Host "      Estado: $taskState" -ForegroundColor Gray

        # Iniciar a tarefa imediatamente para teste (gera backup real)
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "      Tarefa iniciada para teste..." -ForegroundColor Gray

        return $true
    } catch {
        Write-Error "Erro ao criar tarefa '$TaskName': $_"
        return $false
    }
}

function Show-Summary {
    Write-Title "RESUMO DAS TAREFAS"

    $tarefas = @($TaskNameDiario, $TaskNameStartup)

    foreach ($tarefa in $tarefas) {
        if (Get-TaskExists -TaskName $tarefa) {
            $task = Get-ScheduledTask -TaskName $tarefa
            $nextRun = $task.NextRunTime
            $status = $task.State
            $triggers = $task.Triggers | ForEach-Object {
                if ($_.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger") {
                    "Diario as $([datetime]::Parse($_.StartBoundary).ToString('HH:mm'))"
                } elseif ($_.StartBoundary -eq $null) {
                    "Na inicializacao"
                }
            }

            Write-Host "   - $tarefa" -ForegroundColor White
            Write-Host "      Status: $status" -ForegroundColor Gray
            Write-Host "      Proxima execucao: $(if($nextRun -and $nextRun -ne [datetime]::MaxValue){$nextRun}else{'N/A'})" -ForegroundColor Gray
            Write-Host "      Gatilho: $triggers" -ForegroundColor Gray
            Write-Host ""
        }
    }

    Write-Host "   Diretorio de backups:" -ForegroundColor White
    Write-Host "      $BackupDir" -ForegroundColor Gray
    Write-Host ""
}

function Test-BackupScript {
    Write-Step "Verificando se o script de backup existe e e valido..." "[/]"

    if (-not (Test-Path $ScriptBackup)) {
        Write-Error "Script de backup nao encontrado: $ScriptBackup"
        return $false
    }

    try {
        $content = Get-Content $ScriptBackup -Raw -ErrorAction Stop
        if ($content.Length -eq 0) {
            Write-Error "Script de backup esta vazio!"
            return $false
        }
        Write-OK "Script de backup encontrado ($([math]::Round($content.Length / 1KB, 1)) KB)"
        return $true
    } catch {
        Write-Error "Erro ao ler script de backup: $_"
        return $false
    }
}
# ============================================================
# EXECUCAO PRINCIPAL
# ============================================================

Write-Title "AGENDADOR DE BACKUP AUTOMATICO"
if ($Silencioso) {
    try { Start-Transcript -Path (Join-Path $BackupDir "agendar_log.txt") -Force | Out-Null } catch {}
}

# Verificar se e administrador
if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "[ERRO] ATENCAO: Este script PRECISA ser executado como ADMINISTRADOR!" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Clique com o botao DIREITO no arquivo e selecione:" -ForegroundColor Yellow
    Write-Host "   'Executar com PowerShell (Administrador)'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Ou execute no PowerShell como Admin:" -ForegroundColor Yellow
    Write-Host "   powershell -ExecutionPolicy Bypass -File .\AGENDAR_BACKUP_AUTOMATICO.ps1" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Testar script de backup
if (-not (Test-BackupScript)) {
    exit 1
}

Write-Step "Configurando tarefas agendadas..." "[>]"

# Tarefa 1: Backup Diario as 03:00
$diarioOK = New-BackupTask `
    -TaskName $TaskNameDiario `
    -Description "$TaskDescription - Diario" `
    -TriggerType "daily" `
    -Hora "03:00"

# Tarefa 2: Backup na Inicializacao
$startupOK = New-BackupTask `
    -TaskName $TaskNameStartup `
    -Description "$TaskDescription - Inicializacao" `
    -TriggerType "startup"

# Resumo Final
Show-Summary

# Salvar arquivo .bat para facil execucao manual
$batPath = Join-Path $ProjectRoot "EXECUTAR_BACKUP_MANUAL.bat"
@"
@echo off
title Backup Manual - Sistema Exodo
echo ========================================
echo   BACKUP MANUAL - SISTEMA EXODO
echo ========================================
echo.
echo Iniciando backup do PostgreSQL...
powershell -ExecutionPolicy Bypass -File "%~dp0backup_postgresql.ps1" -Modo completo
echo.
if %errorlevel% equ 0 (
    echo Backup concluido com sucesso!
) else (
    echo Backup falhou!
)
echo.
pause
"@ | Set-Content $batPath -Encoding ASCII

Write-OK "Arquivo para backup manual criado: EXECUTAR_BACKUP_MANUAL.bat"

Write-Host "==================================================" -ForegroundColor Green
Write-Host "    CONFIGURACAO CONCLUIDA!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   Backups automaticos agendados com sucesso!" -ForegroundColor White
Write-Host "   Os backups serao salvos em: $BackupDir" -ForegroundColor Gray
Write-Host ""
Write-Host "   Para testar agora:" -ForegroundColor Yellow
Write-Host "   .\EXECUTAR_BACKUP_MANUAL.bat" -ForegroundColor White
Write-Host ""
if ($Silencioso) { try { Stop-Transcript | Out-Null } catch {} }
if (-not $Silencioso) {
    pause
}

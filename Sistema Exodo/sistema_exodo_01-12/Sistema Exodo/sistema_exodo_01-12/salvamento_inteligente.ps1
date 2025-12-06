# ============================================================
# SISTEMA DE SALVAMENTO INTELIGENTE E AUTOMÁTICO
# ============================================================
# Este script faz:
# - Commit automático a cada 20 minutos (se houver alterações)
# - Push automático a cada 30 minutos (se houver commits)
# - Backup antes de cada operação importante
# - Logs detalhados de todas as operações
# ============================================================

param(
    [int]$CommitIntervalMinutes = 20,
    [int]$PushIntervalMinutes = 30
)

# Cores para output
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Detail { param($msg) Write-Host $msg -ForegroundColor Gray }

# Detectar diretório do projeto
if ($PSScriptRoot) {
    $projectPath = $PSScriptRoot
} else {
    $projectPath = (Get-Location).Path
}

# Encontrar repositório Git
$gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    $projectPath = $gitCheck
    Set-Location $projectPath
} else {
    Write-Error "ERRO: Não é um repositório Git válido!"
    exit 1
}

# Criar diretório de logs
$logsDir = Join-Path $projectPath ".salvamento_logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# Função para fazer backup antes de operações importantes
function Backup-AntesOperacao {
    param($operacao)
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = Join-Path $projectPath ".backups"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    $backupFile = Join-Path $backupDir "backup_${operacao}_${timestamp}.txt"
    
    # Salvar status atual
    git status > $backupFile
    git log -1 --oneline >> $backupFile
    
    Write-Detail "  Backup criado: $backupFile"
    return $backupFile
}

# Função para fazer commit
function Fazer-Commit {
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Verificar se há alterações
    Set-Location $projectPath
    $status = git status --porcelain 2>$null
    
    if (-not $status -or $status.Length -eq 0) {
        return $false
    }
    
    # Fazer backup antes do commit
    Backup-AntesOperacao -operacao "pre_commit"
    
    Write-Detail "  [$currentTime] Alterações detectadas, fazendo commit..."
    
    # Adicionar todas as alterações
    git add -A 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Erro ao adicionar arquivos!"
        return $false
    }
    
    # Criar commit
    $commitMessage = "Salvamento automático - $currentTime"
    $commitResult = git commit -m $commitMessage 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $commitHash = git rev-parse --short HEAD
        Write-Success "  Commit criado: $commitHash - $commitMessage"
        
        # Log
        $logFile = Join-Path $logsDir "commits.log"
        "$currentTime | COMMIT | $commitHash | $commitMessage" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        return $true
    } else {
        Write-Error "  Erro ao criar commit: $commitResult"
        return $false
    }
}

# Função para fazer push
function Fazer-Push {
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Verificar se há commits para fazer push
    $ahead = git rev-list --count @{u}..HEAD 2>$null
    
    if (-not $ahead -or $ahead -eq 0) {
        return $false
    }
    
    # Fazer backup antes do push
    Backup-AntesOperacao -operacao "pre_push"
    
    Write-Detail "  [$currentTime] $ahead commit(s) para enviar, fazendo push..."
    
    $pushResult = git push origin main 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  Push realizado com sucesso!"
        
        # Log
        $logFile = Join-Path $logsDir "pushes.log"
        "$currentTime | PUSH | $ahead commit(s) enviado(s)" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        return $true
    } else {
        Write-Error "  Erro ao fazer push: $pushResult"
        
        # Log de erro
        $logFile = Join-Path $logsDir "erros.log"
        "$currentTime | PUSH ERROR | $pushResult" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        return $false
    }
}

# Função principal de loop
function Main-Loop {
    $commitCounter = 0
    $pushCounter = 0
    $iteration = 0
    $lastCommitTime = Get-Date
    $lastPushTime = Get-Date
    
    Write-Info "========================================"
    Write-Info "  SALVAMENTO INTELIGENTE ATIVADO"
    Write-Info "========================================"
    Write-Info ""
    Write-Info "Configuração:"
    Write-Info "  - Commit automático: a cada $CommitIntervalMinutes minutos"
    Write-Info "  - Push automático: a cada $PushIntervalMinutes minutos"
    Write-Info "  - Logs salvos em: $logsDir"
    Write-Info "  - Backups salvos em: .backups"
    Write-Info ""
    Write-Warning "Pressione Ctrl+C para parar"
    Write-Info ""
    
    # Log de início
    $logFile = Join-Path $logsDir "sessao.log"
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "========================================" | Out-File -Append -FilePath $logFile -Encoding UTF8
    "Sessão iniciada: $startTime" | Out-File -Append -FilePath $logFile -Encoding UTF8
    "Commit: $CommitIntervalMinutes min | Push: $PushIntervalMinutes min" | Out-File -Append -FilePath $logFile -Encoding UTF8
    "========================================" | Out-File -Append -FilePath $logFile -Encoding UTF8
    
    while ($true) {
        $iteration++
        $currentTime = Get-Date
        $timeStr = $currentTime.ToString("HH:mm:ss")
        
        Write-Detail "[$timeStr] Iteração $iteration - Verificando..."
        
        # Verificar se é hora de fazer commit (a cada 20 minutos)
        $minutesSinceLastCommit = ($currentTime - $lastCommitTime).TotalMinutes
        if ($minutesSinceLastCommit -ge $CommitIntervalMinutes) {
            Write-Info "[$timeStr] Verificando alterações para commit..."
            $commitFeito = Fazer-Commit
            if ($commitFeito) {
                $commitCounter++
                $lastCommitTime = $currentTime
            }
        }
        
        # Verificar se é hora de fazer push (a cada 30 minutos)
        $minutesSinceLastPush = ($currentTime - $lastPushTime).TotalMinutes
        if ($minutesSinceLastPush -ge $PushIntervalMinutes) {
            Write-Info "[$timeStr] Verificando commits para push..."
            $pushFeito = Fazer-Push
            if ($pushFeito) {
                $pushCounter++
                $lastPushTime = $currentTime
            }
        }
        
        # Resumo a cada 10 iterações
        if ($iteration % 10 -eq 0) {
            Write-Info ""
            Write-Info "=== Resumo ==="
            Write-Info "  Commits realizados: $commitCounter"
            Write-Info "  Pushes realizados: $pushCounter"
            Write-Info "  Próximo commit em: $([math]::Max(0, [math]::Round($CommitIntervalMinutes - $minutesSinceLastCommit))) minutos"
            Write-Info "  Próximo push em: $([math]::Max(0, [math]::Round($PushIntervalMinutes - $minutesSinceLastPush))) minutos"
            Write-Info ""
        }
        
        # Aguardar 1 minuto antes da próxima verificação
        Start-Sleep -Seconds 60
    }
}

# Tratamento de erro global
trap {
    $errorTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Error "Erro crítico: $_"
    
    $logFile = Join-Path $logsDir "erros.log"
    "$errorTime | ERRO CRÍTICO | $_" | Out-File -Append -FilePath $logFile -Encoding UTF8
    
    Write-Warning "O script será reiniciado em 10 segundos..."
    Start-Sleep -Seconds 10
    continue
}

# Iniciar loop principal
try {
    Main-Loop
} catch {
    Write-Error "Erro fatal: $_"
    exit 1
}


# ============================================================
# SISTEMA DE SALVAMENTO EM TEMPO REAL
# ============================================================
# Este script monitora alterações em tempo real e salva
# automaticamente quando detecta mudanças nos arquivos
# ============================================================

param(
    [int]$PushIntervalMinutes = 30,
    [int]$DelayAntesCommit = 5  # Segundos de espera antes de commitar (evita múltiplos commits)
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

# Variáveis de controle
$ultimaAlteracao = Get-Date
$timerCommit = $null
$timerPush = $null
$pushCounter = 0
$commitCounter = 0
$ultimoCommitTime = Get-Date

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
    git status > $backupFile 2>&1
    git log -1 --oneline >> $backupFile 2>&1
    
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
    
    Write-Info "  [$currentTime] Alterações detectadas, fazendo commit..."
    
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
        Write-Success "  ✓ Commit criado: $commitHash"
        
        # Log
        $logFile = Join-Path $logsDir "commits.log"
        "$currentTime | COMMIT | $commitHash | $commitMessage" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        $script:commitCounter++
        $script:ultimoCommitTime = Get-Date
        return $true
    } else {
        Write-Error "  Erro ao criar commit: $commitResult"
        return $false
    }
}

# Função para fazer push
function Fazer-Push {
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Branch de destino: modo-dev
    $targetBranch = "modo-dev"
    
    # Verificar se há commits para fazer push
    $ahead = git rev-list --count @{u}..HEAD 2>$null
    
    if (-not $ahead -or $ahead -eq 0) {
        return $false
    }
    
    # Fazer backup antes do push
    Backup-AntesOperacao -operacao "pre_push"
    
    Write-Info "  [$currentTime] $ahead commit(s) para enviar, fazendo push para $targetBranch..."
    
    # Verificar se o branch existe no remoto
    $branchExists = git ls-remote --heads origin $targetBranch 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $branchExists) {
        Write-Detail "  Branch $targetBranch não existe no remoto, será criado..."
    }
    
    # Fazer push com --set-upstream para criar o branch se não existir
    $pushResult = git push origin $targetBranch --set-upstream 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  ✓ Push realizado com sucesso para $targetBranch!"
        
        # Log
        $logFile = Join-Path $logsDir "pushes.log"
        "$currentTime | PUSH | Branch: $targetBranch | $ahead commit(s) enviado(s)" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        $script:pushCounter++
        return $true
    } else {
        Write-Error "  Erro ao fazer push para $targetBranch"
        Write-Error "  Detalhes: $pushResult"
        
        # Tentar diagnóstico adicional
        Write-Detail "  Verificando conexão com o remoto..."
        $remoteCheck = git remote -v 2>&1
        Write-Detail "  Remote configurado: $remoteCheck"
        
        # Log de erro
        $logFile = Join-Path $logsDir "erros.log"
        "$currentTime | PUSH ERROR | Branch: $targetBranch | $pushResult" | Out-File -Append -FilePath $logFile -Encoding UTF8
        
        return $false
    }
}

# Função para verificar se arquivo deve ser ignorado
function Deve-IgnorarArquivo {
    param($caminho)
    
    $caminhoRelativo = $caminho.Replace($projectPath, "").TrimStart("\")
    
    # Lista de pastas/arquivos a ignorar
    $ignorar = @(
        ".git",
        "build",
        ".dart_tool",
        ".idea",
        ".vscode",
        ".backups",
        ".restore_backups",
        ".salvamento_logs",
        "backups_exodo",
        "node_modules",
        ".flutter-plugins",
        ".flutter-plugins-dependencies",
        ".packages",
        ".pub",
        "*.log",
        "*.tmp",
        "*.temp"
    )
    
    foreach ($item in $ignorar) {
        if ($caminhoRelativo -like "*\$item\*" -or $caminhoRelativo -like "$item\*" -or $caminhoRelativo -like "*$item") {
            return $true
        }
    }
    
    return $false
}

# Função chamada quando arquivo é alterado
function On-FileChanged {
    param($source, $e)
    
    $caminhoCompleto = $e.FullPath
    
    # Ignorar se arquivo não deve ser monitorado
    if (Deve-IgnorarArquivo -caminho $caminhoCompleto) {
        return
    }
    
    $script:ultimaAlteracao = Get-Date
    
    # Cancelar timer anterior se existir
    if ($script:timerCommit) {
        $script:timerCommit.Dispose()
    }
    
    # Criar novo timer para commitar após delay
    $script:timerCommit = [System.Timers.Timer]::new($DelayAntesCommit * 1000)
    $script:timerCommit.AutoReset = $false
    $script:timerCommit.Add_Elapsed({
        Write-Detail "  [$(Get-Date -Format 'HH:mm:ss')] Processando alterações..."
        Fazer-Commit | Out-Null
    })
    $script:timerCommit.Start()
}

# Função principal
function Main-Loop {
    Write-Info "========================================"
    Write-Info "  SALVAMENTO EM TEMPO REAL ATIVADO"
    Write-Info "========================================"
    Write-Info ""
    Write-Info "Configuração:"
    Write-Info "  - Monitoramento: TEMPO REAL"
    Write-Info "  - Delay antes de commit: $DelayAntesCommit segundos"
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
    "Sessão iniciada (TEMPO REAL): $startTime" | Out-File -Append -FilePath $logFile -Encoding UTF8
    "Delay: $DelayAntesCommit seg | Push: $PushIntervalMinutes min" | Out-File -Append -FilePath $logFile -Encoding UTF8
    "========================================" | Out-File -Append -FilePath $logFile -Encoding UTF8
    
    # Criar FileSystemWatcher para monitorar alterações
    $watcher = [System.IO.FileSystemWatcher]::new($projectPath)
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    
    # Filtrar apenas arquivos relevantes (não monitorar .git, build, etc)
    $watcher.Filter = "*.*"
    
    # Eventos a monitorar
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action { On-FileChanged $this $Event } | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action { On-FileChanged $this $Event } | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Deleted" -Action { On-FileChanged $this $Event } | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Renamed" -Action { On-FileChanged $this $Event } | Out-Null
    
    Write-Success "Monitoramento de arquivos iniciado!"
    Write-Info ""
    
    # Timer para push periódico
    $script:timerPush = [System.Timers.Timer]::new($PushIntervalMinutes * 60 * 1000)
    $script:timerPush.AutoReset = $true
    $script:timerPush.Add_Elapsed({
        Write-Info "  [$(Get-Date -Format 'HH:mm:ss')] Verificando commits para push..."
        Fazer-Push | Out-Null
    })
    $script:timerPush.Start()
    
    # Loop principal para manter o script rodando e mostrar status
    $iteration = 0
    while ($true) {
        Start-Sleep -Seconds 30
        
        $iteration++
        if ($iteration % 20 -eq 0) {  # A cada 10 minutos
            $timeStr = (Get-Date).ToString("HH:mm:ss")
            Write-Info ""
            Write-Info "=== Status [$timeStr] ==="
            Write-Info "  Commits realizados: $commitCounter"
            Write-Info "  Pushes realizados: $pushCounter"
            $minutosDesdeUltimoCommit = ((Get-Date) - $ultimoCommitTime).TotalMinutes
            Write-Info "  Último commit: $([math]::Round($minutosDesdeUltimoCommit, 1)) minutos atrás"
            Write-Info "  Monitorando: $projectPath"
            Write-Info ""
        }
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


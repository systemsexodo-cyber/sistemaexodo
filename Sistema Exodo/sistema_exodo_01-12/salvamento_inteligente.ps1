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
    [int]$CommitIntervalMinutes = 5,
    [int]$PushIntervalMinutes = 10
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
    
    Write-Detail "  [$currentTime] Alterações detectadas, preparando commit..."
    
    # Mostrar quais arquivos serão adicionados
    $arquivosModificados = git status --porcelain 2>$null
    if ($arquivosModificados) {
        $arquivosList = ($arquivosModificados -split "`n" | Where-Object { $_ -match '^\s*[MADRC]' } | ForEach-Object { ($_ -split '\s+', 2)[1] })
        Write-Detail "  Arquivos modificados: $($arquivosList.Count)"
        if ($arquivosList.Count -le 5) {
            foreach ($arq in $arquivosList) {
                Write-Detail "    - $arq"
            }
        } else {
            foreach ($arq in $arquivosList[0..4]) {
                Write-Detail "    - $arq"
            }
            Write-Detail "    ... e mais $($arquivosList.Count - 5) arquivo(s)"
        }
    }
    
    # Adicionar todas as alterações
    Write-Detail "  Adicionando todas as alterações ao staging (git add -A)..."
    $addResult = git add -A 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Erro ao adicionar arquivos: $addResult"
        return $false
    }
    
    Write-Detail "  Arquivos adicionados com sucesso!"
    
    # Verificar se há algo para commitar (pode ter sido adicionado mas não há mudanças reais)
    $statusAposAdd = git status --porcelain 2>$null
    if (-not $statusAposAdd -or $statusAposAdd.Length -eq 0) {
        Write-Detail "  Nenhuma alteração para commitar após adicionar"
        return $false
    }
    
    # Criar commit
    Write-Detail "  Criando commit..."
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

# Função para fazer push limpo (sem arquivos grandes)
function Fazer-Push-Limpo {
    param(
        [string]$targetBranch
    )
    
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    Write-Detail "  [$currentTime] Criando branch limpo para push sem arquivos grandes..."
    
    # Salvar branch atual
    $currentBranch = git rev-parse --abbrev-ref HEAD
    
    # Criar branch temporário limpo (orphan)
    $tempBranchName = "temp-push-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    try {
        # Criar branch órfão (sem histórico)
        $checkoutResult = git checkout --orphan $tempBranchName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "  Erro ao criar branch limpo: $checkoutResult"
            return $false
        }
        
        # Limpar staging area
        git reset 2>&1 | Out-Null
        
        # Adicionar apenas arquivos da pasta sistema_exodo_01-12 (respeitando .gitignore)
        Write-Detail "  Adicionando arquivos da pasta sistema_exodo_01-12 (respeitando .gitignore)..."
        $addResult = git add "sistema_exodo_01-12/" 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Também adicionar arquivos na raiz do repositório se houver
            git add "*.ps1" "*.md" ".gitignore" 2>&1 | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Error "  Erro ao adicionar arquivos: $addResult"
            git checkout $currentBranch 2>&1 | Out-Null
            return $false
        }
        
        # Verificar se há algo para commitar
        $status = git status --porcelain 2>&1
        if (-not $status -or $status.Length -eq 0) {
            Write-Detail "  Nenhuma alteração para fazer push"
            git checkout $currentBranch 2>&1 | Out-Null
            git branch -D $tempBranchName 2>&1 | Out-Null
            return $false
        }
        
        # Criar commit com estado atual
        $commitMessage = "Versão limpa do projeto - $currentTime"
        $commitResult = git commit -m $commitMessage 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "  Erro ao criar commit limpo: $commitResult"
            git checkout $currentBranch 2>&1 | Out-Null
            git branch -D $tempBranchName 2>&1 | Out-Null
            return $false
        }
        
        Write-Detail "  Commit limpo criado, fazendo push para $targetBranch..."
        
        # Fazer push forçado para o branch de destino
        $pushResult = git push origin "$tempBranchName`:$targetBranch" --force --no-verify 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  Push limpo realizado com sucesso para $targetBranch!"
            
            # Log
            $logFile = Join-Path $logsDir "pushes.log"
            "$currentTime | PUSH LIMPO | Branch: $targetBranch" | Out-File -Append -FilePath $logFile -Encoding UTF8
            
            # Voltar para branch original
            git checkout $currentBranch 2>&1 | Out-Null
            git branch -D $tempBranchName 2>&1 | Out-Null
            
            return $true
        } else {
            Write-Error "  Erro ao fazer push limpo: $pushResult"
            git checkout $currentBranch 2>&1 | Out-Null
            git branch -D $tempBranchName 2>&1 | Out-Null
            
            # Log de erro
            $logFile = Join-Path $logsDir "erros.log"
            "$currentTime | PUSH LIMPO ERROR | $pushResult" | Out-File -Append -FilePath $logFile -Encoding UTF8
            
            return $false
        }
    } catch {
        Write-Error "  Erro ao fazer push limpo: $_"
        # Garantir que voltamos para o branch original
        git checkout $currentBranch 2>&1 | Out-Null
        git branch -D $tempBranchName 2>&1 | Out-Null
        return $false
    }
}

# Função para fazer push
function Fazer-Push {
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Verificar se há commits para fazer push
    # Primeiro, atualizar referências remotas
    git fetch origin 2>&1 | Out-Null
    
    # Verificar se há commits locais que não estão no remoto
    $localBranch = git rev-parse --abbrev-ref HEAD
    
    # Fazer backup antes do push
    Backup-AntesOperacao -operacao "pre_push"
    
    Write-Detail "  [$currentTime] Fazendo push limpo (sem arquivos grandes) para $localBranch..."
    
    # Usar método de push limpo (sem histórico problemático)
    $pushFeito = Fazer-Push-Limpo -targetBranch $localBranch
    
    if ($pushFeito) {
        return $true
    }
    
    # Se o push limpo falhou, tentar também para main se não for o branch atual
    if ($localBranch -ne "main") {
        Write-Detail "  Tentando também fazer push para main..."
        $pushMainFeito = Fazer-Push-Limpo -targetBranch "main"
        if ($pushMainFeito) {
            Write-Success "  Push para main também realizado!"
        }
    }
    
    return $pushFeito
}

# Função para reverter modificações
function Reverter-Modificacoes {
    param(
        [string]$CommitHash = "HEAD",
        [switch]$Hard = $false
    )
    
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Warning "[$currentTime] Revertendo modificações..."
    
    # Fazer backup antes de reverter
    Backup-AntesOperacao -operacao "pre_revert"
    
    if ($Hard) {
        # Reverter tudo (hard reset)
        git reset --hard $CommitHash 2>&1 | Out-Null
        Write-Success "  Reversão completa realizada (hard reset para $CommitHash)"
    } else {
        # Reverter apenas arquivos não commitados (soft)
        git checkout -- . 2>&1 | Out-Null
        Write-Success "  Alterações não commitadas revertidas"
    }
    
    # Log
    $logFile = Join-Path $logsDir "reversoes.log"
    "$currentTime | REVERT | $CommitHash | Hard: $Hard" | Out-File -Append -FilePath $logFile -Encoding UTF8
    
    return $true
}

# Variável global para controle de salvamento em tempo real
$script:ultimaAlteracao = Get-Date
$script:arquivosAlterados = @{}

# Função para monitorar alterações em tempo real
function Iniciar-MonitoramentoTempoReal {
    Write-Info "Iniciando monitoramento de arquivos em tempo real..."
    
    # Criar FileSystemWatcher para monitorar alterações
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $projectPath
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    
    # Filtrar apenas arquivos relevantes (não incluir .git, build, etc)
    $watcher.Filter = "*.*"
    
    # Evento de alteração
    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        
        # Ignorar arquivos do sistema
        if ($path -match '\.(git|dart_tool|build|\.idea|\.vscode)' -or 
            $path -match '\\\.(git|dart_tool|build|\.idea|\.vscode)') {
            return
        }
        
        # Ignorar arquivos temporários
        if ($path -match '\.(tmp|temp|log|cache)$') {
            return
        }
        
        $script:ultimaAlteracao = Get-Date
        $script:arquivosAlterados[$path] = $changeType
        
        Write-Detail "  Arquivo alterado: $path ($changeType)"
    }
    
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $action | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Deleted" -Action $action | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName "Renamed" -Action $action | Out-Null
    
    return $watcher
}

# Função principal de loop
function Main-Loop {
    $commitCounter = 0
    $pushCounter = 0
    $iteration = 0
    $lastCommitTime = Get-Date
    $lastPushTime = Get-Date
    $lastRealTimeSave = Get-Date
    
    # Iniciar monitoramento em tempo real
    $watcher = Iniciar-MonitoramentoTempoReal
    
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
    Write-Info "Diretório do projeto: $projectPath"
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
        
        # SALVAMENTO EM TEMPO REAL: Se houve alterações recentes (últimos 2 minutos), fazer commit imediatamente
        $secondsSinceLastChange = ($currentTime - $script:ultimaAlteracao).TotalSeconds
        if ($secondsSinceLastChange -lt 120 -and $script:arquivosAlterados.Count -gt 0) {
            $secondsSinceLastRealTimeSave = ($currentTime - $lastRealTimeSave).TotalSeconds
            if ($secondsSinceLastRealTimeSave -ge 60) { # Aguardar pelo menos 1 minuto entre salvamentos em tempo real
                Write-Info "[$timeStr] Alterações detectadas! Salvamento em tempo real..."
                $commitFeito = Fazer-Commit
                if ($commitFeito) {
                    $commitCounter++
                    $lastCommitTime = $currentTime
                    $lastRealTimeSave = $currentTime
                    $script:arquivosAlterados.Clear()
                    Write-Success "  Salvamento em tempo real realizado!"
                }
            }
        }
        
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
        
        # Verificar se é hora de fazer push (a cada X minutos)
        $minutesSinceLastPush = ($currentTime - $lastPushTime).TotalMinutes
        if ($minutesSinceLastPush -ge $PushIntervalMinutes) {
            Write-Info "[$timeStr] Verificando commits para push..."
            $pushFeito = Fazer-Push
            if ($pushFeito) {
                $pushCounter++
                $lastPushTime = $currentTime
            } else {
                # Mesmo que não tenha feito push, atualizar o tempo para não ficar tentando toda iteração
                $lastPushTime = $currentTime
            }
        }
        
        # Resumo a cada 10 iterações
        if ($iteration % 10 -eq 0) {
            Write-Info ""
            Write-Info "=== Resumo ==="
            Write-Info "  Commits realizados: $commitCounter"
            Write-Info "  Pushes realizados: $pushCounter"
            Write-Info "  Arquivos alterados: $($script:arquivosAlterados.Count)"
            Write-Info "  Próximo commit em: $([math]::Max(0, [math]::Round($CommitIntervalMinutes - $minutesSinceLastCommit))) minutos"
            Write-Info "  Próximo push em: $([math]::Max(0, [math]::Round($PushIntervalMinutes - $minutesSinceLastPush))) minutos"
            Write-Info ""
            Write-Info "  Comandos disponíveis:"
            Write-Info "    - Reverter alterações não commitadas: Reverter-Modificacoes"
            Write-Info "    - Reverter para commit específico: Reverter-Modificacoes -CommitHash <hash> -Hard"
            Write-Info ""
        }
        
        # Aguardar 30 segundos antes da próxima verificação (tempo real)
        Start-Sleep -Seconds 30
    }
    
    # Limpar watcher ao sair
    if ($watcher) {
        $watcher.Dispose()
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


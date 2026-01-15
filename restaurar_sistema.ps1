# ============================================================
# SISTEMA DE RESTAURAÇÃO COMPLETO
# ============================================================
# Este script permite restaurar o sistema para qualquer
# versão anterior de forma segura, com backup automático
# ============================================================

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

# Criar diretório de backups de restauração
$restoreBackupDir = Join-Path $projectPath ".restore_backups"
if (-not (Test-Path $restoreBackupDir)) {
    New-Item -ItemType Directory -Path $restoreBackupDir -Force | Out-Null
}

Write-Info "========================================"
Write-Info "  SISTEMA DE RESTAURAÇÃO"
Write-Info "========================================"
Write-Info ""
Write-Info "Diretório do projeto: $projectPath"
Write-Info ""

# Função para criar backup completo antes de restaurar
function Criar-BackupCompleto {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupName = "backup_antes_restauracao_$timestamp"
    $backupPath = Join-Path $restoreBackupDir $backupName
    
    Write-Warning "[1/5] Criando backup completo antes da restauração..."
    
    # Criar diretório de backup
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    # Salvar estado atual do Git
    Write-Detail "  Salvando estado do Git..."
    git status > (Join-Path $backupPath "git_status.txt")
    git log -10 --oneline > (Join-Path $backupPath "git_log.txt")
    git diff > (Join-Path $backupPath "git_diff.txt")
    
    # Salvar hash do commit atual
    $currentHash = git rev-parse HEAD
    $currentHash | Out-File -FilePath (Join-Path $backupPath "commit_atual.txt") -Encoding UTF8
    
    # Criar um commit temporário com o estado atual (se houver alterações)
    $status = git status --porcelain
    if ($status) {
        Write-Detail "  Há alterações não commitadas, salvando..."
        git add -A
        git commit -m "Backup antes de restauração - $timestamp" 2>&1 | Out-Null
    }
    
    Write-Success "  Backup criado em: $backupPath"
    Write-Info ""
    
    return $backupPath
}

# Função para listar versões disponíveis
function Listar-Versoes {
    Write-Info "[2/5] Listando versões disponíveis..."
    Write-Info ""
    
    # Buscar commits recentes
    $commits = git log --oneline --decorate -30
    
    if (-not $commits) {
        Write-Error "  Nenhum commit encontrado!"
        return $null
    }
    
    Write-Detail "Últimos 30 commits:"
    Write-Detail ""
    
    $commitList = @()
    $commits | ForEach-Object {
        if ($_ -match '^([a-f0-9]+)\s+(.+)') {
            $hash = $matches[1]
            $message = $matches[2]
            $commitList += [PSCustomObject]@{
                Hash = $hash
                Message = $message
            }
            Write-Host "  [$($commitList.Count)] " -NoNewline -ForegroundColor Cyan
            Write-Host "$hash " -NoNewline -ForegroundColor Yellow
            Write-Host $message -ForegroundColor White
        }
    }
    
    Write-Info ""
    return $commitList
}

# Função para restaurar versão
function Restaurar-Versao {
    param($commitHash)
    
    Write-Info "[3/5] Verificando commit..."
    
    # Verificar se o commit existe
    $commitExists = git rev-parse --verify "$commitHash" 2>$null
    if (-not $commitExists) {
        Write-Error "  Commit não encontrado: $commitHash"
        return $false
    }
    
    # Obter informações do commit
    $commitInfo = git log -1 --format="%H|%an|%ae|%ad|%s" --date=iso $commitHash
    Write-Detail "  Commit encontrado: $commitInfo"
    
    Write-Info "[4/5] Restaurando versão..."
    
    # Fazer checkout do commit
    $checkoutResult = git checkout $commitHash 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  Versão restaurada com sucesso!"
        return $true
    } else {
        Write-Error "  Erro ao restaurar: $checkoutResult"
        return $false
    }
}

# Função para criar branch de segurança
function Criar-BranchSeguranca {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $branchName = "backup_antes_restauracao_$timestamp"
    
    Write-Info "[5/5] Criando branch de segurança..."
    
    # Criar branch a partir do estado atual
    $branchResult = git branch $branchName 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  Branch de segurança criada: $branchName"
        Write-Detail "  Para voltar: git checkout $branchName"
        return $branchName
    } else {
        Write-Warning "  Não foi possível criar branch: $branchResult"
        return $null
    }
}

# Menu principal
Write-Info "Opções disponíveis:"
Write-Info "  1. Restaurar para um commit específico (digite o hash)"
Write-Info "  2. Ver lista completa de commits (digite 'lista')"
Write-Info "  3. Restaurar para a versão mais recente (digite 'atual')"
Write-Info "  4. Cancelar (digite 'sair')"
Write-Info ""

$userInput = Read-Host "Digite sua escolha"

if ($userInput -eq "sair" -or $userInput -eq "") {
    Write-Warning "Operação cancelada."
    exit 0
}

# Criar backup antes de qualquer operação
$backupPath = Criar-BackupCompleto

# Processar escolha do usuário
if ($userInput -eq "lista") {
    $commitList = Listar-Versoes
    if ($commitList) {
        Write-Info ""
        $numero = Read-Host "Digite o número do commit para restaurar"
        if ($numero -match '^\d+$' -and [int]$numero -le $commitList.Count) {
            $commitHash = $commitList[[int]$numero - 1].Hash
            Write-Info "Restaurando para: $commitHash"
        } else {
            Write-Error "Número inválido!"
            exit 1
        }
    } else {
        exit 1
    }
} elseif ($userInput -eq "atual") {
    $commitHash = "main"
    Write-Info "Restaurando para a versão mais recente (main)..."
} else {
    $commitHash = $userInput.Trim()
    Write-Info "Restaurando para o commit: $commitHash"
}

# Confirmar restauração
Write-Info ""
Write-Warning "========================================"
Write-Warning "  ATENÇÃO: OPERAÇÃO IRREVERSÍVEL"
Write-Warning "========================================"
Write-Warning ""
Write-Warning "Esta operação vai alterar seus arquivos!"
Write-Info "Um backup completo foi criado em: $backupPath"
Write-Info ""
$confirm = Read-Host "Deseja continuar? (s/n)"

if ($confirm -ne "s" -and $confirm -ne "S" -and $confirm -ne "sim") {
    Write-Warning "Operação cancelada."
    exit 0
}

# Criar branch de segurança
$branchName = Criar-BranchSeguranca

# Restaurar versão
$sucesso = Restaurar-Versao -commitHash $commitHash

if ($sucesso) {
    Write-Info ""
    Write-Success "========================================"
    Write-Success "  RESTAURAÇÃO CONCLUÍDA COM SUCESSO!"
    Write-Success "========================================"
    Write-Info ""
    Write-Info "Você está agora na versão: $commitHash"
    Write-Info ""
    Write-Info "Informações importantes:"
    Write-Info "  - Backup completo: $backupPath"
    if ($branchName) {
        Write-Info "  - Branch de segurança: $branchName"
    }
    Write-Info ""
    Write-Warning "Para voltar para a versão mais recente:"
    Write-Detail "  git checkout main"
    Write-Info ""
    Write-Warning "Para voltar para o backup criado:"
    if ($branchName) {
        Write-Detail "  git checkout $branchName"
    }
    Write-Info ""
} else {
    Write-Error "Falha na restauração. Verifique os logs."
    exit 1
}


# ============================================================
# SISTEMA DE BACKUP COMPLETO
# ============================================================
# Cria um backup completo do projeto incluindo:
# - Estado atual do Git
# - Todos os arquivos do projeto
# - Histórico de commits
# - Configurações
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

Write-Info "========================================"
Write-Info "  BACKUP COMPLETO DO PROJETO"
Write-Info "========================================"
Write-Info ""

# Criar diretório de backups
$backupBaseDir = Join-Path $projectPath ".." "backups_exodo"
if (-not (Test-Path $backupBaseDir)) {
    New-Item -ItemType Directory -Path $backupBaseDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $backupBaseDir "backup_$timestamp"

Write-Info "Criando backup em: $backupDir"
Write-Info ""

# Criar estrutura de backup
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupDir "projeto") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupDir "git") -Force | Out-Null

# 1. Salvar informações do Git
Write-Info "[1/4] Salvando informações do Git..."
git status > (Join-Path $backupDir "git" "status.txt")
git log -50 --oneline > (Join-Path $backupDir "git" "log.txt")
git log -1 --format="%H|%an|%ae|%ad|%s" --date=iso > (Join-Path $backupDir "git" "commit_atual.txt")
git branch -a > (Join-Path $backupDir "git" "branches.txt")
git remote -v > (Join-Path $backupDir "git" "remotes.txt")
Write-Success "  Informações do Git salvas"

# 2. Criar bundle do Git (backup completo do repositório)
Write-Info "[2/4] Criando bundle do Git..."
$bundleFile = Join-Path $backupDir "git" "repositorio_completo.bundle"
git bundle create $bundleFile --all 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Success "  Bundle criado: $bundleFile"
} else {
    Write-Warning "  Aviso: Não foi possível criar bundle completo"
}

# 3. Copiar arquivos importantes (exceto node_modules, build, etc)
Write-Info "[3/4] Copiando arquivos do projeto..."
$excludeDirs = @("node_modules", "build", ".dart_tool", ".idea", ".vscode", ".git", "backups_exodo", ".backups", ".restore_backups", ".salvamento_logs")

Get-ChildItem -Path $projectPath -Recurse -File | Where-Object {
    $relativePath = $_.FullName.Replace($projectPath, "").TrimStart("\")
    $shouldExclude = $false
    foreach ($exclude in $excludeDirs) {
        if ($relativePath -like "*\$exclude\*" -or $relativePath -like "$exclude\*") {
            $shouldExclude = $true
            break
        }
    }
    -not $shouldExclude
} | ForEach-Object {
    $relativePath = $_.FullName.Replace($projectPath, "").TrimStart("\")
    $destPath = Join-Path $backupDir "projeto" $relativePath
    $destDir = Split-Path $destPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item $_.FullName -Destination $destPath -Force
}

Write-Success "  Arquivos copiados"

# 4. Criar arquivo de informações do backup
Write-Info "[4/4] Criando arquivo de informações..."
$infoFile = Join-Path $backupDir "info_backup.txt"
@"
========================================
BACKUP COMPLETO DO PROJETO EXODO
========================================
Data/Hora: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Diretório do Projeto: $projectPath
Diretório do Backup: $backupDir

CONTEÚDO DO BACKUP:
- Informações do Git (status, log, branches, remotes)
- Bundle completo do repositório Git
- Todos os arquivos do projeto (exceto temporários)

COMO RESTAURAR:
1. Para restaurar o bundle Git:
   git clone repositorio_completo.bundle projeto_restaurado

2. Para restaurar arquivos:
   Copie os arquivos da pasta 'projeto' para o diretório desejado

3. Para verificar informações:
   - status.txt: Estado do Git no momento do backup
   - log.txt: Histórico de commits
   - commit_atual.txt: Commit atual no momento do backup

========================================
"@ | Out-File -FilePath $infoFile -Encoding UTF8

Write-Success "  Arquivo de informações criado"

# Resumo final
Write-Info ""
Write-Success "========================================"
Write-Success "  BACKUP CONCLUÍDO COM SUCESSO!"
Write-Success "========================================"
Write-Info ""
Write-Info "Localização: $backupDir"
Write-Info ""
Write-Info "Tamanho do backup:"
$backupSize = (Get-ChildItem -Path $backupDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Info "  $([math]::Round($backupSize, 2)) MB"
Write-Info ""
Write-Warning "IMPORTANTE: Mantenha este backup em local seguro!"
Write-Info ""


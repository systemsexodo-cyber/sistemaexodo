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
$parentDir = Split-Path -Parent $projectPath
$backupBaseDir = Join-Path $parentDir "backups_exodo"
if (-not (Test-Path $backupBaseDir)) {
    New-Item -ItemType Directory -Path $backupBaseDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $backupBaseDir "backup_$timestamp"

# Garantir que o caminho está resolvido
$backupDir = (Resolve-Path $backupDir -ErrorAction SilentlyContinue).Path
if (-not $backupDir) {
    $backupDir = Join-Path $backupBaseDir "backup_$timestamp"
}

Write-Info "Criando backup em: $backupDir"
Write-Info ""

# Validar caminho do backup
if (-not $backupDir) {
    Write-Error "ERRO: Não foi possível determinar o diretório de backup!"
    exit 1
}

# Criar estrutura de backup
try {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $backupDir "projeto") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $backupDir "git") -Force | Out-Null
    
    # Verificar se os diretórios foram criados
    if (-not (Test-Path $backupDir)) {
        Write-Error "ERRO: Não foi possível criar o diretório de backup!"
        exit 1
    }
} catch {
    Write-Error "ERRO ao criar estrutura de backup: $_"
    exit 1
}

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
$arquivosCopiados = 0
$arquivosPulados = 0

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
    try {
        $relativePath = $_.FullName.Replace($projectPath, "").TrimStart("\")
        
        # Pular se o caminho relativo estiver vazio ou inválido
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            return
        }
        
        # Validar comprimento do caminho (Windows tem limite de 260 caracteres)
        if ($relativePath.Length -gt 200) {
            $script:arquivosPulados++
            Write-Detail "  [AVISO] Caminho muito longo, pulando: $($relativePath.Substring(0, 50))..."
            return
        }
        
        $projetoDir = Join-Path $backupDir "projeto"
        $destPath = Join-Path $projetoDir $relativePath
        
        # Validar caminho de destino
        if ([string]::IsNullOrWhiteSpace($destPath)) {
            return
        }
        
        $destDir = Split-Path $destPath -Parent -ErrorAction SilentlyContinue
        
        if ($destDir -and -not (Test-Path $destDir -ErrorAction SilentlyContinue)) {
            try {
                New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Detail "  [AVISO] Não foi possível criar diretório: $destDir"
                return
            }
        }
        
        if ($destPath) {
            try {
                Copy-Item $_.FullName -Destination $destPath -Force -ErrorAction Stop
                $script:arquivosCopiados++
            } catch {
                $script:arquivosPulados++
                Write-Detail "  [AVISO] Não foi possível copiar: $relativePath"
            }
        }
    } catch {
        # Ignorar erros individuais e continuar
    }
}

Write-Success "  Arquivos copiados: $arquivosCopiados"
if ($arquivosPulados -gt 0) {
    Write-Warning "  Arquivos pulados: $arquivosPulados (caminhos muito longos ou inválidos)"
}

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


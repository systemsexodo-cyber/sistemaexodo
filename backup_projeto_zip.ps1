# ============================================================
# BACKUP ZIPADO COMPLETO DO PROJETO
# ============================================================
# Cria um arquivo ZIP contendo toda a pasta do projeto
# (exceto diretórios temporários e desnecessários)
# ============================================================

# Cores para output
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Detail { param($msg) Write-Host $msg -ForegroundColor Gray }

# Detectar diretório do projeto (usar o diretório do script, não o repositório Git completo)
if ($PSScriptRoot) {
    $projectPath = $PSScriptRoot
} else {
    $projectPath = (Get-Location).Path
}

# Verificar se é repositório Git (apenas para informações)
$gitCheck = $null
try {
    $gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
} catch { }

Set-Location $projectPath

Write-Info "========================================"
Write-Info "  BACKUP ZIPADO COMPLETO DO PROJETO"
Write-Info "========================================"
Write-Info ""

# Criar diretório de backups
$parentDir = Split-Path -Parent $projectPath
$backupBaseDir = Join-Path $parentDir "backups_exodo"
if (-not (Test-Path $backupBaseDir)) {
    New-Item -ItemType Directory -Path $backupBaseDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$projectName = Split-Path -Leaf $projectPath
$zipFileName = "projeto_completo_${projectName}_$timestamp.zip"
$zipFilePath = Join-Path $backupBaseDir $zipFileName

Write-Info "Projeto: $projectName"
Write-Info "Criando backup ZIP em: $zipFilePath"
Write-Info ""

# Diretórios e arquivos a excluir do backup
$excludeDirs = @(
    "node_modules",
    "build",
    ".dart_tool",
    ".idea",
    ".vscode",
    ".git",
    "backups_exodo",
    ".backups",
    ".restore_backups",
    ".salvamento_logs",
    "__pycache__",
    ".pytest_cache",
    "*.pyc",
    "venv",
    "env",
    ".env"
)

Write-Info "[1/4] Analisando arquivos do projeto..."

# Contar arquivos
$totalArquivos = 0
$arquivosIncluidos = 0
$arquivosPulados = 0
$tamanhoTotal = 0

Get-ChildItem -Path $projectPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $relativePath = $_.FullName.Replace($projectPath, "").TrimStart("\")
    $shouldExclude = $false
    
    foreach ($exclude in $excludeDirs) {
        if ($relativePath -like "*\$exclude\*" -or $relativePath -like "$exclude\*" -or $relativePath -like "*$exclude") {
            $shouldExclude = $true
            break
        }
    }
    
    if (-not $shouldExclude) {
        $totalArquivos++
        $tamanhoTotal += $_.Length
    }
}

Write-Info "  Total de arquivos encontrados: $totalArquivos"
Write-Info "  Tamanho estimado: $([math]::Round($tamanhoTotal / 1MB, 2)) MB"
Write-Info ""

# Criar diretório temporário
Write-Info "[2/4] Preparando arquivos para backup..."
$tempDir = Join-Path $env:TEMP "backup_projeto_$timestamp"
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copiar arquivos
Write-Info "[3/4] Copiando arquivos..."

Get-ChildItem -Path $projectPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $relativePath = $_.FullName.Replace($projectPath, "").TrimStart("\")
    $shouldExclude = $false
    
    # Verificar se deve excluir
    foreach ($exclude in $excludeDirs) {
        if ($relativePath -like "*\$exclude\*" -or $relativePath -like "$exclude\*" -or $relativePath -like "*$exclude") {
            $shouldExclude = $true
            break
        }
    }
    
    if ($shouldExclude) {
        $arquivosPulados++
        return
    }
    
    # Validar comprimento do caminho
    if ($relativePath.Length -gt 200) {
        $arquivosPulados++
        if ($arquivosPulados % 100 -eq 0) {
            Write-Detail "  Processando... (pulados: $arquivosPulados)"
        }
        return
    }
    
    try {
        $destPath = Join-Path $tempDir $relativePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        Copy-Item $_.FullName -Destination $destPath -Force -ErrorAction Stop
        
        $arquivosIncluidos++
        
        if ($arquivosIncluidos % 100 -eq 0) {
            Write-Detail "  Copiados: $arquivosIncluidos arquivos..."
        }
    } catch {
        $arquivosPulados++
        if ($arquivosPulados -lt 10) {
            Write-Detail "  [AVISO] Erro ao copiar: $relativePath"
        }
    }
}

Write-Info "  Arquivos incluídos: $arquivosIncluidos"
if ($arquivosPulados -gt 0) {
    Write-Warning "  Arquivos pulados: $arquivosPulados"
}
Write-Info ""

# Criar arquivo de informações
Write-Info "[4/4] Criando arquivo ZIP..."

# Informações do backup
$backupInfo = @"
========================================
BACKUP COMPLETO DO PROJETO - SISTEMA EXODO
========================================
Data/Hora: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Nome do Projeto: $projectName
Diretório do Projeto: $projectPath

ESTATÍSTICAS DO BACKUP:
- Total de arquivos incluídos: $arquivosIncluidos
- Arquivos excluídos/pulados: $arquivosPulados
- Tamanho estimado: $([math]::Round($tamanhoTotal / 1MB, 2)) MB

DIRETÓRIOS EXCLUÍDOS:
- node_modules, build, .dart_tool
- .idea, .vscode, .git
- backups_exodo, .backups
- __pycache__, venv, env
- E outros diretórios temporários

"@

# Adicionar informações do Git (se disponível)
if ($gitCheck) {
    $backupInfo += "`nINFORMAÇÕES DO GIT:`n"
    
    try {
        $gitStatus = git status 2>&1 | Out-String
        $backupInfo += "STATUS:`n$gitStatus`n"
    } catch { }
    
    try {
        $lastCommit = git log -1 --format="%H|%an|%ae|%ad|%s" --date=iso 2>&1 | Out-String
        $backupInfo += "ÚLTIMO COMMIT:`n$lastCommit`n"
    } catch { }
    
    try {
        $currentBranch = git branch --show-current 2>&1 | Out-String
        $backupInfo += "BRANCH ATUAL:`n$currentBranch`n"
    } catch { }
}

$backupInfo += "`n========================================`n"

# Salvar arquivo de informações
$infoFile = Join-Path $tempDir "INFO_BACKUP.txt"
$backupInfo | Out-File -FilePath $infoFile -Encoding UTF8

# Criar ZIP usando Compress-Archive
if (Test-Path $zipFilePath) {
    Remove-Item $zipFilePath -Force
}

try {
    Write-Detail "  Comprimindo arquivos (isso pode levar alguns minutos)..."
    Compress-Archive -Path "$tempDir\*" -DestinationPath $zipFilePath -Force -ErrorAction Stop
    Write-Success "  ZIP criado com sucesso!"
} catch {
    Write-Error "  ERRO ao criar ZIP: $_"
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Limpar diretório temporário
Write-Detail "  Limpando arquivos temporários..."
Remove-Item $tempDir -Recurse -Force

# Resumo final
Write-Info ""
Write-Success "========================================"
Write-Success "  BACKUP ZIP CRIADO COM SUCESSO!"
Write-Success "========================================"
Write-Info ""
Write-Info "Arquivo: $zipFilePath"
Write-Info ""

# Calcular tamanho do ZIP
if (Test-Path $zipFilePath) {
    $zipSize = (Get-Item $zipFilePath).Length / 1MB
    Write-Info "Tamanho do ZIP: $([math]::Round($zipSize, 2)) MB"
    Write-Info ""
}

Write-Info "Conteúdo do backup:"
Write-Info "  - Todos os arquivos do projeto ($arquivosIncluidos arquivos)"
Write-Info "  - INFO_BACKUP.txt (informações do backup e Git)"
Write-Info ""
Write-Info "Diretórios excluídos:"
Write-Info "  - node_modules, build, .dart_tool"
Write-Info "  - .git, .idea, .vscode"
Write-Info "  - backups_exodo, arquivos temporários"
Write-Info ""
Write-Warning "IMPORTANTE: Mantenha este backup em local seguro!"
Write-Info ""


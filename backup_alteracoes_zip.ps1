# ============================================================
# BACKUP ZIPADO DAS ALTERAÇÕES
# ============================================================
# Cria um arquivo ZIP contendo apenas os arquivos modificados
# e adicionados no repositório Git
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
Write-Info "  BACKUP ZIPADO DAS ALTERAÇÕES"
Write-Info "========================================"
Write-Info ""

# Criar diretório de backups
$parentDir = Split-Path -Parent $projectPath
$backupBaseDir = Join-Path $parentDir "backups_exodo"
if (-not (Test-Path $backupBaseDir)) {
    New-Item -ItemType Directory -Path $backupBaseDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$zipFileName = "alteracoes_$timestamp.zip"
$zipFilePath = Join-Path $backupBaseDir $zipFileName

Write-Info "Criando backup ZIP em: $zipFilePath"
Write-Info ""

# Verificar se há alterações
Write-Info "[1/4] Verificando alterações no Git..."
$status = git status --porcelain

if (-not $status -or $status.Length -eq 0) {
    Write-Warning "Nenhuma alteração encontrada no repositório!"
    Write-Info "Todas as alterações já foram commitadas."
    exit 0
}

# Contar alterações
$arquivosModificados = 0
$arquivosAdicionados = 0
$arquivosRemovidos = 0

$status | ForEach-Object {
    if ($_ -match '^M\s') { $script:arquivosModificados++ }
    elseif ($_ -match '^A\s') { $script:arquivosAdicionados++ }
    elseif ($_ -match '^D\s') { $script:arquivosRemovidos++ }
    elseif ($_ -match '^\?\?') { $script:arquivosAdicionados++ }
}

Write-Info "  Arquivos modificados: $arquivosModificados"
Write-Info "  Arquivos adicionados: $arquivosAdicionados"
Write-Info "  Arquivos removidos: $arquivosRemovidos"
Write-Info ""

# Criar diretório temporário para arquivos
Write-Info "[2/4] Preparando arquivos..."
$tempDir = Join-Path $env:TEMP "backup_temp_$timestamp"
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$arquivosIncluidos = 0
$arquivosPulados = 0
$arquivosList = @()

# Processar arquivos modificados e adicionados
Write-Info "[3/4] Copiando arquivos..."

$status | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    
    # Extrair status e caminho do arquivo
    $statusCode = $line.Substring(0, 2).Trim()
    $filePath = $line.Substring(2).Trim()
    
    # Pular arquivos removidos (não podemos incluí-los)
    if ($statusCode -eq 'D' -or $statusCode -match '^D') {
        return
    }
    
    # Limpar caminho do arquivo (remover aspas se houver)
    $filePath = $filePath.Trim('"')
    
    # Obter caminho completo
    $fullPath = Join-Path $projectPath $filePath
    
    # Verificar se o arquivo existe
    if (-not (Test-Path $fullPath -ErrorAction SilentlyContinue)) {
        $arquivosPulados++
        Write-Detail "  [AVISO] Arquivo não encontrado: $filePath"
        return
    }
    
    # Verificar se é um arquivo (não diretório)
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        return
    }
    
    # Validar comprimento do caminho
    if ($filePath.Length -gt 200) {
        $arquivosPulados++
        Write-Detail "  [AVISO] Caminho muito longo, pulando: $($filePath.Substring(0, 50))..."
        return
    }
    
    try {
        # Criar estrutura de diretórios no temp
        $destPath = Join-Path $tempDir $filePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        # Copiar arquivo
        Copy-Item $fullPath -Destination $destPath -Force -ErrorAction Stop
        
        $arquivosIncluidos++
        $arquivosList += $filePath
        
        if ($arquivosIncluidos % 50 -eq 0) {
            Write-Detail "  Processados: $arquivosIncluidos arquivos..."
        }
    } catch {
        $arquivosPulados++
        Write-Detail "  [ERRO] Não foi possível copiar: $filePath - $_"
    }
}

Write-Info "  Arquivos incluídos: $arquivosIncluidos"
if ($arquivosPulados -gt 0) {
    Write-Warning "  Arquivos pulados: $arquivosPulados"
}
Write-Info ""

# Criar arquivo de informações
Write-Info "[4/4] Criando arquivo ZIP..."

# Informações do Git
$gitInfo = @"
========================================
BACKUP DAS ALTERAÇÕES - SISTEMA EXODO
========================================
Data/Hora: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Diretório do Projeto: $projectPath

ESTATÍSTICAS:
- Arquivos modificados: $arquivosModificados
- Arquivos adicionados: $arquivosAdicionados
- Arquivos removidos: $arquivosRemovidos
- Arquivos incluídos no ZIP: $arquivosIncluidos
- Arquivos pulados: $arquivosPulados

INFORMAÇÕES DO GIT:
"@

# Adicionar status do Git
$gitStatus = git status 2>&1 | Out-String
$gitInfo += "`n`nSTATUS DO GIT:`n$gitStatus`n"

# Adicionar último commit
$lastCommit = git log -1 --format="%H|%an|%ae|%ad|%s" --date=iso 2>&1 | Out-String
$gitInfo += "`nÚLTIMO COMMIT:`n$lastCommit`n"

# Adicionar branch atual
$currentBranch = git branch --show-current 2>&1 | Out-String
$gitInfo += "`nBRANCH ATUAL:`n$currentBranch`n"

# Salvar arquivo de informações
$infoFile = Join-Path $tempDir "INFO_BACKUP.txt"
$gitInfo | Out-File -FilePath $infoFile -Encoding UTF8

# Salvar lista de arquivos
$filesList = $arquivosList -join "`n"
$filesListFile = Join-Path $tempDir "LISTA_ALTERACOES.txt"
$filesList | Out-File -FilePath $filesListFile -Encoding UTF8

# Criar ZIP usando Compress-Archive
if (Test-Path $zipFilePath) {
    Remove-Item $zipFilePath -Force
}

try {
    Compress-Archive -Path "$tempDir\*" -DestinationPath $zipFilePath -Force -ErrorAction Stop
    Write-Success "  ZIP criado com sucesso!"
} catch {
    Write-Error "  ERRO ao criar ZIP: $_"
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Limpar diretório temporário
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
    Write-Info "Tamanho: $([math]::Round($zipSize, 2)) MB"
    Write-Info ""
}

Write-Info "Conteúdo do ZIP:"
Write-Info "  - Arquivos modificados/adicionados ($arquivosIncluidos arquivos)"
Write-Info "  - INFO_BACKUP.txt (informações do Git)"
Write-Info "  - LISTA_ALTERACOES.txt (lista completa)"
Write-Info ""
Write-Warning "IMPORTANTE: Mantenha este backup em local seguro!"
Write-Info ""

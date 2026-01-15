# ============================================================
# CRIAR PONTO DE RESTAURAÇÃO MANUAL
# ============================================================
# Este script cria um ponto de restauração que pode ser
# usado para restaurar o sistema a qualquer momento
# ============================================================

# Cores para output
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Detail { param($msg) Write-Host $msg -ForegroundColor Gray }

# Detectar diretório do projeto (onde o script está)
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} else {
    $scriptDir = (Get-Location).Path
}

# O projeto é onde o script está (sistema_exodo_01-12)
$projectPath = $scriptDir
Set-Location $projectPath

# Verificar se é um repositório Git válido
$gitCheck = git rev-parse --show-toplevel 2>$null
if (-not $gitCheck) {
    Write-Error "ERRO: Não é um repositório Git válido!"
    exit 1
}

Write-Info "========================================"
Write-Info "  CRIAR PONTO DE RESTAURAÇÃO"
Write-Info "========================================"
Write-Info ""

# Criar diretório de pontos de restauração
$pontosDir = Join-Path $projectPath ".pontos_restauracao"
if (-not (Test-Path $pontosDir)) {
    New-Item -ItemType Directory -Path $pontosDir -Force | Out-Null
}

# Solicitar nome/descrição do ponto
Write-Info "Digite um nome ou descrição para este ponto de restauração:"
Write-Detail "  (Ex: 'Antes de implementar feature X', 'Versão estável', etc.)"
Write-Info ""
$nomePonto = Read-Host "Nome do ponto"

if ([string]::IsNullOrWhiteSpace($nomePonto)) {
    $nomePonto = "Ponto de restauração - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}

# Criar tag única
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$tagNome = "RESTORE_$timestamp"
$pontoDir = Join-Path $pontosDir $tagNome

Write-Info ""
Write-Info "[1/4] Criando estrutura do ponto de restauração..."
New-Item -ItemType Directory -Path $pontoDir -Force | Out-Null
Write-Success "  Diretório criado: $pontoDir"

# Salvar informações do Git
Write-Info "[2/4] Salvando estado do Git..."
$commitHash = git rev-parse HEAD
$commitInfo = git log -1 --format="%H|%an|%ae|%ad|%s" --date=iso

# Criar arquivo de informações
$infoFile = Join-Path $pontoDir "info.txt"
@"
========================================
PONTO DE RESTAURAÇÃO
========================================
Nome: $nomePonto
Tag: $tagNome
Data/Hora: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Commit Hash: $commitHash

Informações do Commit:
$commitInfo

COMO RESTAURAR:
Execute: .\restaurar_ponto.ps1
E selecione este ponto pelo nome ou tag.

========================================
"@ | Out-File -FilePath $infoFile -Encoding UTF8

Write-Success "  Informações salvas"

# Criar bundle do Git (backup completo do repositório)
Write-Info "[3/4] Criando backup completo do repositório..."
$bundleFile = Join-Path $pontoDir "repositorio.bundle"
git bundle create $bundleFile --all 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    $bundleSize = (Get-Item $bundleFile).Length / 1MB
    Write-Success "  Bundle criado: $([math]::Round($bundleSize, 2)) MB"
} else {
    Write-Warning "  Aviso: Não foi possível criar bundle completo"
}

# Salvar lista de arquivos importantes
Write-Info "[4/4] Salvando lista de arquivos..."
$arquivosFile = Join-Path $pontoDir "arquivos.txt"
git ls-files > $arquivosFile 2>&1
Write-Success "  Lista de arquivos salva"

# Criar arquivo de índice para busca rápida
$indiceFile = Join-Path $pontosDir "indice.json"
$pontosExistentes = @()

if (Test-Path $indiceFile) {
    try {
        $conteudo = Get-Content $indiceFile -Raw | ConvertFrom-Json
        if ($conteudo -is [Array]) {
            $pontosExistentes = $conteudo
        } else {
            $pontosExistentes = @($conteudo)
        }
    } catch {
        $pontosExistentes = @()
    }
}

$novoPonto = @{
    tag = $tagNome
    nome = $nomePonto
    data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    commitHash = $commitHash
    caminho = $pontoDir
}

$pontosExistentes = $pontosExistentes + @($novoPonto)
$pontosExistentes | ConvertTo-Json -Depth 10 | Out-File -FilePath $indiceFile -Encoding UTF8

Write-Info ""
Write-Success "========================================"
Write-Success "  PONTO DE RESTAURAÇÃO CRIADO!"
Write-Success "========================================"
Write-Info ""
Write-Info "Nome: $nomePonto"
Write-Info "Tag: $tagNome"
Write-Info "Localização: $pontoDir"
Write-Info ""
Write-Warning "Para restaurar este ponto, execute:"
Write-Detail "  .\restaurar_ponto.ps1"
Write-Info ""


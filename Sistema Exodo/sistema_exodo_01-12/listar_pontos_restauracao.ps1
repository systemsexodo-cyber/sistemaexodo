# ============================================================
# LISTAR PONTOS DE RESTAURAÇÃO
# ============================================================
# Lista todos os pontos de restauração disponíveis
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
Write-Info "  PONTOS DE RESTAURAÇÃO DISPONÍVEIS"
Write-Info "========================================"
Write-Info ""

# Diretório de pontos de restauração
$pontosDir = Join-Path $projectPath ".pontos_restauracao"
$indiceFile = Join-Path $pontosDir "indice.json"

if (-not (Test-Path $pontosDir) -or -not (Test-Path $indiceFile)) {
    Write-Warning "Nenhum ponto de restauração encontrado!"
    Write-Info ""
    Write-Info "Para criar um ponto de restauração, execute:"
    Write-Detail "  .\criar_ponto_restauracao.ps1"
    Write-Info ""
    exit 0
}

# Carregar índice de pontos
$pontos = @()
try {
    $conteudo = Get-Content $indiceFile -Raw | ConvertFrom-Json
    $pontos = $conteudo
} catch {
    Write-Error "Erro ao carregar índice de pontos de restauração!"
    exit 1
}

if ($pontos.Count -eq 0) {
    Write-Warning "Nenhum ponto de restauração encontrado!"
    exit 0
}

# Ordenar por data (mais recente primeiro)
$pontosOrdenados = $pontos | Sort-Object -Property data -Descending

Write-Info "Total de pontos: $($pontosOrdenados.Count)"
Write-Info ""

for ($i = 0; $i -lt $pontosOrdenados.Count; $i++) {
    $ponto = $pontosOrdenados[$i]
    $numero = $i + 1
    
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  [$numero] $($ponto.nome)" -ForegroundColor White
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Detail "  Data: $($ponto.data)"
    Write-Detail "  Tag: $($ponto.tag)"
    Write-Detail "  Commit: $($ponto.commitHash)"
    
    # Verificar se o diretório existe
    if (Test-Path $ponto.caminho) {
        $bundleFile = Join-Path $ponto.caminho "repositorio.bundle"
        if (Test-Path $bundleFile) {
            $tamanho = (Get-Item $bundleFile).Length / 1MB
            Write-Detail "  Tamanho: $([math]::Round($tamanho, 2)) MB"
        }
        Write-Success "  Status: Disponível"
    } else {
        Write-Error "  Status: Diretório não encontrado!"
    }
    
    Write-Info ""
}

Write-Info "Para restaurar um ponto, execute:"
Write-Detail "  .\restaurar_ponto.ps1"
Write-Info ""


# ============================================================
# RESTAURAR PONTO DE RESTAURAÇÃO
# ============================================================
# Este script permite restaurar o sistema para um ponto
# de restauração criado anteriormente
# ============================================================

param(
    [int]$NumeroPonto = 0,
    [switch]$ConfirmarAutomatico = $false
)

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
Write-Info "  RESTAURAR PONTO DE RESTAURAÇÃO"
Write-Info "========================================"
Write-Info ""

# Diretório de pontos de restauração
$pontosDir = Join-Path $projectPath ".pontos_restauracao"
$indiceFile = Join-Path $pontosDir "indice.json"

if (-not (Test-Path $pontosDir) -or -not (Test-Path $indiceFile)) {
    Write-Error "Nenhum ponto de restauração encontrado!"
    Write-Info ""
    Write-Info "Para criar um ponto de restauração, execute:"
    Write-Detail "  .\criar_ponto_restauracao.ps1"
    Write-Info ""
    exit 1
}

# Carregar índice de pontos
$pontos = @()
try {
    $conteudo = Get-Content $indiceFile -Raw | ConvertFrom-Json
    # Se for um array, usar diretamente; se for um objeto único, converter para array
    if ($conteudo -is [array]) {
        $pontos = $conteudo
    } else {
        $pontos = @($conteudo)
    }
} catch {
    Write-Error "Erro ao carregar índice de pontos de restauração!"
    exit 1
}

if ($pontos.Count -eq 0) {
    Write-Error "Nenhum ponto de restauração encontrado!"
    exit 1
}

# Listar pontos disponíveis
Write-Info "Pontos de restauração disponíveis:"
Write-Info ""
for ($i = 0; $i -lt $pontos.Count; $i++) {
    $ponto = $pontos[$i]
    $numero = $i + 1
    Write-Host "  [$numero] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($ponto.nome) " -NoNewline -ForegroundColor White
    Write-Host "($($ponto.data))" -ForegroundColor Gray
    Write-Detail "      Tag: $($ponto.tag) | Commit: $($ponto.commitHash.Substring(0, 7))"
    Write-Info ""
}

# Aceitar número como parâmetro ou solicitar
$escolha = $null
if ($NumeroPonto -gt 0) {
    $escolha = $NumeroPonto.ToString()
    Write-Info "Usando ponto número: $NumeroPonto"
} else {
    # Solicitar escolha
    Write-Info "Digite o número do ponto para restaurar (ou 'sair' para cancelar):"
    $escolha = Read-Host "Escolha"
}

if ($escolha -eq "sair" -or [string]::IsNullOrWhiteSpace($escolha)) {
    Write-Warning "Operação cancelada."
    exit 0
}

$numero = 0
if (-not [int]::TryParse($escolha, [ref]$numero) -or $numero -lt 1 -or $numero -gt $pontos.Count) {
    Write-Error "Número inválido!"
    exit 1
}

$pontoSelecionado = $pontos[$numero - 1]

Write-Info ""
Write-Info "Ponto selecionado:"
Write-Info "  Nome: $($pontoSelecionado.nome)"
Write-Info "  Data: $($pontoSelecionado.data)"
Write-Info "  Tag: $($pontoSelecionado.tag)"
Write-Info "  Commit: $($pontoSelecionado.commitHash)"
Write-Info ""

# Confirmar restauração
Write-Warning "========================================"
Write-Warning "  ATENÇÃO: OPERAÇÃO IRREVERSÍVEL"
Write-Warning "========================================"
Write-Warning ""
Write-Warning "Esta operação vai restaurar o sistema para este ponto!"
Write-Warning "Todas as alterações após este ponto serão perdidas!"
Write-Info ""

$confirmar = $null
if ($ConfirmarAutomatico) {
    $confirmar = "s"
    Write-Info "Confirmação automática ativada."
} else {
    $confirmar = Read-Host "Deseja continuar? (s/n)"
}

if ($confirmar -ne "s" -and $confirmar -ne "S" -and $confirmar -ne "sim") {
    Write-Warning "Operação cancelada."
    exit 0
}

# Criar backup do estado atual antes de restaurar
Write-Info ""
Write-Info "[1/3] Criando backup do estado atual..."
$backupAtualDir = Join-Path $projectPath ".backups"
if (-not (Test-Path $backupAtualDir)) {
    New-Item -ItemType Directory -Path $backupAtualDir -Force | Out-Null
}

$backupTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupAtualFile = Join-Path $backupAtualDir "backup_antes_restauracao_$backupTimestamp.txt"

git status > $backupAtualFile 2>&1
git log -1 --oneline >> $backupAtualFile 2>&1
$commitAtual = git rev-parse HEAD
"Commit atual: $commitAtual" | Out-File -Append -FilePath $backupAtualFile -Encoding UTF8

Write-Success "  Backup criado: $backupAtualFile"

# Restaurar do bundle
Write-Info "[2/3] Restaurando repositório do ponto de restauração..."
$bundleFile = Join-Path $pontoSelecionado.caminho "repositorio.bundle"

if (-not (Test-Path $bundleFile)) {
    Write-Error "Bundle não encontrado! Tentando restaurar pelo commit..."
    
    # Tentar restaurar pelo commit hash
    $checkoutResult = git checkout $pontoSelecionado.commitHash 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Erro ao restaurar: $checkoutResult"
        exit 1
    }
} else {
    # Criar diretório temporário para restaurar
    $tempDir = Join-Path $env:TEMP "restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        # Clonar do bundle
        $cloneResult = git clone $bundleFile $tempDir 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            # Copiar arquivos (exceto .git)
            Get-ChildItem -Path $tempDir -Recurse -File | Where-Object {
                $_.FullName -notlike "*\.git\*"
            } | ForEach-Object {
                $relativePath = $_.FullName.Replace($tempDir, "").TrimStart("\")
                $destPath = Join-Path $projectPath $relativePath
                $destDir = Split-Path $destPath -Parent
                
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                
                Copy-Item $_.FullName -Destination $destPath -Force
            }
            
            # Restaurar estado do Git
            Set-Location $projectPath
            git reset --hard $pontoSelecionado.commitHash 2>&1 | Out-Null
        } else {
            Write-Error "Erro ao clonar bundle: $cloneResult"
            exit 1
        }
    } finally {
        # Limpar diretório temporário
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Info "[3/3] Verificando restauração..."
$commitRestaurado = git rev-parse HEAD

if ($commitRestaurado -eq $pontoSelecionado.commitHash) {
    Write-Info ""
    Write-Success "========================================"
    Write-Success "  RESTAURAÇÃO CONCLUÍDA COM SUCESSO!"
    Write-Success "========================================"
    Write-Info ""
    Write-Info "Sistema restaurado para:"
    Write-Info "  Nome: $($pontoSelecionado.nome)"
    Write-Info "  Data: $($pontoSelecionado.data)"
    Write-Info "  Commit: $commitRestaurado"
    Write-Info ""
    Write-Warning "Backup do estado anterior:"
    Write-Detail "  $backupAtualFile"
    Write-Info ""
} else {
    Write-Error "Aviso: O commit restaurado pode ser diferente do esperado!"
    Write-Info "  Esperado: $($pontoSelecionado.commitHash)"
    Write-Info "  Obtido: $commitRestaurado"
    Write-Info ""
}


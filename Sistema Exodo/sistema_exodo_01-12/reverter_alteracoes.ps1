# ============================================================
# REVERTER ALTERAÇÕES LOCAIS
# ============================================================
# Este script permite reverter alterações de várias formas:
# 1. Descartar alterações não commitadas (soft)
# 2. Reverter para um commit específico (hard)
# 3. Ver histórico de commits para escolher
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
Write-Info "  REVERTER ALTERAÇÕES LOCAIS"
Write-Info "========================================"
Write-Info ""
Write-Info "Diretório do projeto: $projectPath"
Write-Info ""

# Menu de opções
Write-Info "Opções disponíveis:"
Write-Info "  1. Descartar alterações não commitadas (soft)"
Write-Info "  2. Reverter para um commit específico (hard)"
Write-Info "  3. Ver histórico de commits"
Write-Info "  4. Cancelar"
Write-Info ""
$opcao = Read-Host "Escolha uma opção (1-4)"

if ($opcao -eq '3') {
    Write-Info ""
    Write-Info "Últimos 10 commits:"
    Write-Info ""
    git log --oneline -10 --decorate
    Write-Info ""
    $opcao = Read-Host "Agora escolha uma opção (1-2) ou pressione Enter para cancelar"
    if ([string]::IsNullOrWhiteSpace($opcao)) {
        Write-Info "Operação cancelada."
        exit 0
    }
}

if ($opcao -eq '2') {
    Write-Info ""
    Write-Info "Últimos 10 commits:"
    Write-Info ""
    git log --oneline -10 --decorate
    Write-Info ""
    $commitHash = Read-Host "Digite o hash do commit (ou pressione Enter para HEAD)"
    if ([string]::IsNullOrWhiteSpace($commitHash)) {
        $commitHash = "HEAD"
    }
    
    Write-Warning ""
    Write-Warning "ATENÇÃO: Esta ação irá reverter TODAS as alterações para o commit $commitHash!"
    Write-Warning "Todas as alterações após este commit serão perdidas!"
    Write-Info ""
    $confirmacao = Read-Host "Deseja continuar? (S/N)"
    
    if ($confirmacao -ne 'S' -and $confirmacao -ne 's') {
        Write-Info "Operação cancelada."
        exit 0
    }
    
    Write-Info ""
    Write-Info "Revertendo para commit $commitHash..."
    git reset --hard $commitHash 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "✓ Reversão concluída com sucesso!"
        Write-Info "O repositório agora está no estado do commit $commitHash"
    } else {
        Write-Error "✗ Erro ao reverter para o commit $commitHash"
        exit 1
    }
    
    exit 0
}

if ($opcao -eq '4' -or $opcao -ne '1') {
    Write-Info "Operação cancelada."
    exit 0
}

# Verificar se há alterações
$status = git status --porcelain
if (-not $status) {
    Write-Success "Nenhuma alteração local encontrada!"
    Write-Info "Todos os arquivos estão no estado do último commit."
    exit 0
}

# Mostrar resumo das alterações
Write-Warning "Alterações que serão descartadas:"
Write-Detail ""
$status | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^(\S+)\s+(.+)$') {
        $statusCode = $matches[1]
        $file = $matches[2]
        $statusText = switch ($statusCode) {
            'M' { 'Modificado' }
            'A' { 'Adicionado' }
            'D' { 'Deletado' }
            'R' { 'Renomeado' }
            'C' { 'Copiado' }
            'U' { 'Atualizado' }
            '??' { 'Não rastreado' }
            default { $statusCode }
        }
        Write-Detail "  [$statusText] $file"
    }
}
Write-Info ""

# Confirmar ação
Write-Warning "ATENÇÃO: Esta ação irá descartar TODAS as alterações locais!"
Write-Warning "As alterações não podem ser recuperadas após esta operação."
Write-Info ""
$confirmacao = Read-Host "Deseja continuar? (S/N)"

if ($confirmacao -ne 'S' -and $confirmacao -ne 's') {
    Write-Info "Operação cancelada pelo usuário."
    exit 0
}

Write-Info ""
Write-Info "[1/3] Descartando alterações em arquivos rastreados..."
try {
    # Descartar alterações em arquivos modificados
    git checkout . 2>&1 | Out-Null
    Write-Success "  ✓ Alterações descartadas"
} catch {
    Write-Error "  ✗ Erro ao descartar alterações: $_"
    exit 1
}

Write-Info ""
Write-Info "[2/3] Removendo arquivos adicionados ao staging..."
try {
    # Remover arquivos do staging (mas manter no disco)
    git reset HEAD . 2>&1 | Out-Null
    Write-Success "  ✓ Staging limpo"
} catch {
    Write-Warning "  ⚠ Aviso ao limpar staging: $_"
}

Write-Info ""
Write-Info "[3/3] Verificando resultado..."
$statusFinal = git status --porcelain
if (-not $statusFinal) {
    Write-Success "✓ Todas as alterações foram revertidas com sucesso!"
    Write-Info ""
    Write-Info "Os arquivos agora estão no estado do último commit."
} else {
    Write-Warning "Ainda há algumas alterações:"
    Write-Detail $statusFinal
    Write-Info ""
    Write-Info "Deseja remover também arquivos não rastreados? (S/N)"
    $removerNaoRastreados = Read-Host
    
    if ($removerNaoRastreados -eq 'S' -or $removerNaoRastreados -eq 's') {
        Write-Info "Removendo arquivos não rastreados..."
        git clean -fd 2>&1 | Out-Null
        Write-Success "✓ Arquivos não rastreados removidos"
    }
}

Write-Info ""
Write-Success "Operação concluída!"
Write-Info ""



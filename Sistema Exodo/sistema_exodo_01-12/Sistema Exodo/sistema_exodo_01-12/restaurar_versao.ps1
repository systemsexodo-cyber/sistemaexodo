# Script para Restaurar uma Versão Anterior
# Permite voltar facilmente para qualquer versão salva anteriormente

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESTAURAR VERSAO ANTERIOR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

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
    Write-Host "ERRO: Nao e um repositorio Git valido!" -ForegroundColor Red
    exit 1
}

Write-Host "Diretorio do projeto: $projectPath" -ForegroundColor Gray
Write-Host ""

# Salvar estado atual antes de restaurar
Write-Host "[1/4] Salvando estado atual antes de restaurar..." -ForegroundColor Yellow
$saveScript = Join-Path $projectPath "sistema_exodo_novo\salvar_alteracoes.ps1"
if (Test-Path $saveScript) {
    & $saveScript | Out-Null
    Write-Host "  Estado atual salvo com sucesso!" -ForegroundColor Green
} else {
    Write-Host "  Aviso: Script de salvamento nao encontrado" -ForegroundColor Yellow
}
Write-Host ""

# Listar commits recentes
Write-Host "[2/4] Listando versoes disponiveis..." -ForegroundColor Yellow
Write-Host ""
$commits = git log --oneline --decorate -20

if (-not $commits) {
    Write-Host "  Nenhum commit encontrado!" -ForegroundColor Red
    exit 1
}

Write-Host $commits -ForegroundColor Gray
Write-Host ""

# Solicitar hash do commit
Write-Host "[3/4] Selecione a versao para restaurar:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Opcoes:" -ForegroundColor Cyan
Write-Host "  1. Digite o HASH completo do commit (ex: 20db8d2)" -ForegroundColor White
Write-Host "  2. Digite 'ultimo' para voltar para a versao mais recente" -ForegroundColor White
Write-Host "  3. Digite 'sair' para cancelar" -ForegroundColor White
Write-Host ""

$userInput = Read-Host "Digite sua escolha"

if ($userInput -eq "sair" -or $userInput -eq "") {
    Write-Host "Operacao cancelada." -ForegroundColor Yellow
    exit 0
}

if ($userInput -eq "ultimo") {
    $commitHash = "main"
    Write-Host "  Restaurando para a versao mais recente (main)..." -ForegroundColor Cyan
} else {
    $commitHash = $userInput.Trim()
    Write-Host "  Restaurando para o commit: $commitHash" -ForegroundColor Cyan
}

# Verificar se o commit existe
$commitExists = git rev-parse --verify "$commitHash" 2>$null
if (-not $commitExists -and $commitHash -ne "main") {
    Write-Host ""
    Write-Host "ERRO: Commit nao encontrado: $commitHash" -ForegroundColor Red
    Write-Host "Verifique o hash e tente novamente." -ForegroundColor Yellow
    exit 1
}

# Confirmar restauração
Write-Host ""
Write-Host "ATENCAO: Esta operacao vai alterar seus arquivos!" -ForegroundColor Yellow
Write-Host "Um backup foi criado antes desta operacao." -ForegroundColor Cyan
$confirm = Read-Host "Deseja continuar? (s/n)"

if ($confirm -ne "s" -and $confirm -ne "S" -and $confirm -ne "sim") {
    Write-Host "Operacao cancelada." -ForegroundColor Yellow
    exit 0
}

# Restaurar versão
Write-Host ""
Write-Host "[4/4] Restaurando versao..." -ForegroundColor Yellow

if ($commitHash -eq "main") {
    git checkout main 2>&1 | Out-Null
} else {
    git checkout $commitHash 2>&1 | Out-Null
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  VERSAO RESTAURADA COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Voce esta agora na versao: $commitHash" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Para voltar para a versao mais recente:" -ForegroundColor Yellow
    Write-Host "  git checkout main" -ForegroundColor White
    Write-Host ""
    Write-Host "Ou execute este script novamente." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO AO RESTAURAR" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Verifique o hash do commit e tente novamente." -ForegroundColor Yellow
    exit 1
}




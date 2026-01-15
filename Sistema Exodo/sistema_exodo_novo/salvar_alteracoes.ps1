# Script para salvar automaticamente todas as alterações
# Este script faz commit de todas as mudanças para você poder voltar quando precisar

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SALVANDO ALTERAÇÕES AUTOMATICAMENTE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do projeto (onde o script está localizado)
if ($PSScriptRoot) {
    $projectPath = $PSScriptRoot
} else {
    $projectPath = (Get-Location).Path
}

# Garantir que estamos no diretório correto
Set-Location $projectPath

# Verificar se git funciona aqui
$gitCheck = git rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    $projectPath = $gitCheck
    Set-Location $projectPath
} else {
    Write-Host "ERRO: Este diretório não é um repositório Git válido!" -ForegroundColor Red
    Write-Host "Execute este script dentro da pasta sistema_exodo_novo." -ForegroundColor Yellow
    exit 1
}

Write-Host "Diretório do projeto: $projectPath" -ForegroundColor Gray
Write-Host ""

# Verificar se há alterações
Write-Host "[1/3] Verificando alterações..." -ForegroundColor Yellow
$status = git status --porcelain

if (-not $status -or $status.Length -eq 0) {
    Write-Host "  Nenhuma alteracao encontrada. Tudo esta salvo!" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Mostrar resumo das alterações
Write-Host "  Alterações encontradas:" -ForegroundColor Gray
git status --short | ForEach-Object {
    Write-Host "    $_" -ForegroundColor Gray
}
Write-Host ""

# Adicionar todas as alterações
Write-Host "[2/3] Adicionando todas as alterações..." -ForegroundColor Yellow
git add -A

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Erro ao adicionar arquivos!" -ForegroundColor Red
    exit 1
}

    Write-Host "  Arquivos adicionados com sucesso!" -ForegroundColor Green
Write-Host ""

# Criar commit com data e hora
Write-Host "[3/3] Criando commit..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commitMessage = "Salvamento automático - $timestamp"

$commitResult = git commit -m $commitMessage 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ALTERAÇÕES SALVAS COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Mensagem do commit: $commitMessage" -ForegroundColor Cyan
    Write-Host ""
    
    # Mostrar hash do commit
    $commitHash = git rev-parse --short HEAD
    Write-Host "Hash do commit: $commitHash" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Você pode voltar a este ponto usando:" -ForegroundColor Yellow
    Write-Host "  git checkout $commitHash" -ForegroundColor White
    Write-Host ""
    Write-Host "Ou ver todos os commits salvos com:" -ForegroundColor Yellow
    Write-Host "  git log --oneline" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO AO SALVAR" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $commitResult -ForegroundColor Red
    Write-Host ""
    Write-Host "Verifique se há algum problema com o repositório Git." -ForegroundColor Yellow
    exit 1
}

Write-Host "Processo finalizado." -ForegroundColor Cyan


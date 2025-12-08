# Script para fazer push seguro removendo arquivos grandes antes

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PUSH SEGURO - REMOVENDO ARQUIVOS GRANDES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Ir para diretório do repositório
$repoPath = "C:\Users\USER\Downloads"
Set-Location $repoPath

# Verificar branch atual
$currentBranch = git branch --show-current
Write-Host "Branch atual: $currentBranch" -ForegroundColor Yellow
Write-Host ""

# Verificar se há arquivos ZIP grandes no staging
Write-Host "Verificando arquivos grandes..." -ForegroundColor Cyan
$largeFiles = git ls-files | Where-Object {
    $file = $_
    if (Test-Path $file) {
        $size = (Get-Item $file -ErrorAction SilentlyContinue).Length
        ($file -like "*.zip") -and ($size -gt 50MB)
    } else {
        $false
    }
}

if ($largeFiles) {
    Write-Host "Arquivos ZIP grandes encontrados:" -ForegroundColor Yellow
    $largeFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    
    # Remover do índice
    Write-Host "Removendo arquivos grandes do indice..." -ForegroundColor Cyan
    $largeFiles | ForEach-Object {
        git rm --cached $_ 2>&1 | Out-Null
    }
    Write-Host "Arquivos removidos do indice!" -ForegroundColor Green
    Write-Host ""
}

# Verificar se há commits para fazer push
$commitsAhead = git rev-list --count origin/$currentBranch..HEAD 2>&1
if ($commitsAhead -eq 0) {
    Write-Host "Nenhum commit para enviar. Tudo atualizado!" -ForegroundColor Green
    exit 0
}

Write-Host "Commits a enviar: $commitsAhead" -ForegroundColor Cyan
Write-Host ""

# Fazer push
Write-Host "Fazendo push para origin/$currentBranch..." -ForegroundColor Cyan
$pushResult = git push origin $currentBranch 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  PUSH REALIZADO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO NO PUSH" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $pushResult -ForegroundColor Yellow
    
    # Verificar se é erro de arquivo grande
    if ($pushResult -match "exceeds.*file size limit") {
        Write-Host ""
        Write-Host "SOLUCAO:" -ForegroundColor Cyan
        Write-Host "O arquivo grande ainda esta no historico remoto." -ForegroundColor Yellow
        Write-Host "Execute: git filter-branch para remover do historico" -ForegroundColor White
    }
}

Write-Host ""





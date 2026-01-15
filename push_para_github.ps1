# Script para fazer push do projeto para o GitHub
# Este script garante que o push sempre funcione, mesmo com histórico grande

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PUSH AUTOMATICO PARA GITHUB" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Definir diretório do projeto fixo
$projectPath = "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12"

# Verificar se o diretório existe
if (-not (Test-Path $projectPath)) {
    Write-Host "ERRO: Diretório não encontrado: $projectPath" -ForegroundColor Red
    exit 1
}

# Garantir que estamos no diretório correto
Set-Location $projectPath

# Verificar se git funciona aqui
$gitCheck = git rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    $projectPath = $gitCheck
} else {
    Write-Host "ERRO: Este diretório não é um repositório Git válido!" -ForegroundColor Red
    Write-Host "Diretório: $projectPath" -ForegroundColor Yellow
    exit 1
}

Write-Host "Diretório do projeto: $projectPath" -ForegroundColor Gray

$tempPath = Join-Path (Split-Path $projectPath) "sistema_exodo_push_temp"
$remoteUrl = "git@github.com:systemsexodo-cyber/sistemaexodo.git"

Write-Host "[1/5] Preparando ambiente..." -ForegroundColor Yellow

# Limpar diretório temporário se existir
if (Test-Path $tempPath) {
    Write-Host "  Removendo diretório temporário anterior..." -ForegroundColor Gray
    Remove-Item -Recurse -Force $tempPath -ErrorAction SilentlyContinue
}

# Criar diretório temporário
New-Item -ItemType Directory -Path $tempPath | Out-Null

Write-Host "[2/5] Copiando arquivos do projeto..." -ForegroundColor Yellow
# Excluir arquivos e diretórios que não devem ir para o GitHub
$excludeItems = @(
    ".git",
    "flutter_windows_*",
    "*.exe",
    "*.zip",
    "backup-*.sql",
    "*.xlsx",
    "*.mp4",
    "build",
    ".dart_tool",
    ".flutter-plugins",
    ".flutter-plugins-dependencies"
)
Copy-Item -Path "$projectPath\*" -Destination "$tempPath\" -Recurse -Exclude $excludeItems -Force -ErrorAction SilentlyContinue

Write-Host "[3/5] Inicializando repositório Git limpo..." -ForegroundColor Yellow
Set-Location $tempPath
git init | Out-Null
git add . | Out-Null

# Obter mensagem do último commit
$lastCommitMessage = git -C $projectPath log -1 --pretty=%B
if ([string]::IsNullOrWhiteSpace($lastCommitMessage)) {
    $lastCommitMessage = "Atualização do projeto - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}

git commit -m $lastCommitMessage | Out-Null

Write-Host "[4/5] Configurando remote e branch..." -ForegroundColor Yellow
git remote remove origin 2>$null
git remote add origin $remoteUrl
git branch -M main

Write-Host "[5/5] Fazendo push para o GitHub..." -ForegroundColor Yellow
Write-Host ""

$pushResult = git push -u origin main --force 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  PUSH CONCLUIDO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Repositório: $remoteUrl" -ForegroundColor Cyan
    Write-Host "Branch: main" -ForegroundColor Cyan
    Write-Host ""
    
    # Sincronizar repositório original
    Write-Host "Sincronizando repositório original..." -ForegroundColor Yellow
    Set-Location $projectPath
    git fetch origin
    git reset --hard origin/main
    
    Write-Host ""
    Write-Host "Tudo pronto! Seu código está no GitHub." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO NO PUSH" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $pushResult -ForegroundColor Red
    Write-Host ""
    Write-Host "Verifique sua conexão e tente novamente." -ForegroundColor Yellow
}

# Limpar diretório temporário
Write-Host ""
Write-Host "Limpando arquivos temporários..." -ForegroundColor Gray
Set-Location $projectPath
Remove-Item -Recurse -Force $tempPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Processo finalizado." -ForegroundColor Cyan


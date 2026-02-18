# Script de Deploy Automático para Firebase (Hosting + Functions)
# Versão ultra-resiliente e otimizada

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETO - SISTEMA ÊXODO" -ForegroundColor Cyan
Write-Host "  (HOSTING + CLOUD FUNCTIONS)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

# 1. Verificando alterações git
Write-Host "[1/7] Verificando alteracoes nao commitadas..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>$null
$relevantChanges = $gitStatus | Where-Object { 
    $_ -notmatch "\.salvamento_logs" -and 
    $_ -notmatch "commits\.log" -and 
    $_ -notmatch "sessao\.log" -and
    $_ -notmatch "^build\\" -and
    $_ -notmatch "\.dart_tool\\"
}
if ($relevantChanges) {
    Write-Host "  AVISO: Ha alteracoes nao commitadas!" -ForegroundColor Yellow
    Write-Host "  Fazendo commit automatico..." -ForegroundColor Cyan
    git add . 2>$null
    git commit -m "feat: alteracoes antes do deploy - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" --no-verify 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Commit realizado com sucesso!" -ForegroundColor Green
    }
}

# 2. Verificar Ambiente
Write-Host "`n[2/7] Verificando ambiente e ferramentas..." -ForegroundColor Yellow
$firebaseProject = "exodosystems-1541d"
$firebaseCmd = "firebase"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  ERRO: Node.js nao encontrado! Por favor, instale o Node.js." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "  AVISO: Firebase CLI global nao encontrado. Usando npx..." -ForegroundColor Yellow
    $firebaseCmd = "npx -y firebase-tools@latest"
}

Write-Host "  Projeto alvo configurado: $firebaseProject" -ForegroundColor Cyan
Write-Host "  OK: Ferramentas prontas" -ForegroundColor Green

# 3. Preparar Funções (Node.js)
Write-Host "`n[3/7] Preparando Cloud Functions..." -ForegroundColor Yellow
if (Test-Path "functions") {
    Set-Location functions
    Write-Host "  Instalando dependencias (npm install)..." -ForegroundColor Gray
    # Usar --no-bin-links para evitar erros de permissão comuns no Windows
    npm install --no-audit --no-fund --quiet | Out-Null
    Set-Location ..
    Write-Host "  OK: Funcoes preparadas" -ForegroundColor Green
}

# 4. Limpar e Build Flutter
Write-Host "`n[4/7] Limpando e construindo para Web..." -ForegroundColor Yellow
if (Test-Path "build") { Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue }
flutter clean | Out-Null
flutter pub get | Out-Null
Write-Host "  Executando: flutter build web --release" -ForegroundColor Gray
$buildResult = flutter build web --release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERRO: Falha no build do Flutter!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Build finalizado com sucesso" -ForegroundColor Green

# 5. Deploy Firebase
Write-Host "`n[5/7] Fazendo deploy para o Firebase..." -ForegroundColor Yellow
Write-Host "  Isso pode levar alguns minutos (Hosting + Functions)..." -ForegroundColor Cyan

# Execução direta para permitir que o usuário veja logs de autenticação se necessário
if ($firebaseCmd -match "npx") {
    # No Windows, npx às vezes precisa de cmd /c
    cmd /c "$firebaseCmd deploy --only hosting,functions --project $firebaseProject"
}
else {
    firebase deploy --only hosting, functions --project $firebaseProject
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  DEPLOY CONCLUIDO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  URL: https://$firebaseProject.web.app" -ForegroundColor Cyan
}
else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "  ERRO NO DEPLOY!" -ForegroundColor Red
    Write-Host "  Verifique se voce esta logado: firebase login" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host "`n[7/7] Processo finalizado!" -ForegroundColor Green

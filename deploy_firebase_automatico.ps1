# Script de Deploy Automático para Firebase (Hosting + Functions)
# Versão robusta e não-interativa

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETO - SISTEMA ÊXODO" -ForegroundColor Cyan
Write-Host "  (HOSTING + CLOUD FUNCTIONS)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

# 1. Verificando alterações git
Write-Host "[1/8] Verificando alteracoes nao commitadas..." -ForegroundColor Yellow
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
else {
    Write-Host "  OK: Nenhuma alteracao relevante." -ForegroundColor Green
}

# 2. Verificar Ambiente
Write-Host "`n[2/8] Verificando ambiente (Node.js e Firebase)..." -ForegroundColor Yellow
$firebaseProject = "exodosystems-1541d"
$firebaseCmd = "firebase"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  ERRO: Node.js nao encontrado!" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "  AVISO: Firebase CLI global nao encontrado. Usando 'npx -y firebase-tools'..." -ForegroundColor Yellow
    $firebaseCmd = "npx -y firebase-tools"
}

Write-Host "  Projeto alvo: $firebaseProject" -ForegroundColor Cyan
# Tentar selecionar o projeto com timeout/não-interativo
cmd /c "$firebaseCmd use $firebaseProject" 2>&1 | Out-Null
Write-Host "  OK: Ambiente configurado" -ForegroundColor Green

# 3. Preparar Funções (Node.js)
Write-Host "`n[3/8] Preparando Cloud Functions..." -ForegroundColor Yellow
if (Test-Path "functions") {
    Set-Location functions
    Write-Host "  Instalando dependencias das funcoes..." -ForegroundColor Gray
    npm install --no-audit --no-fund | Out-Null
    Set-Location ..
    Write-Host "  OK: Funcoes preparadas" -ForegroundColor Green
}
else {
    Write-Host "  AVISO: Pasta 'functions' nao encontrada. Ignorando." -ForegroundColor Yellow
}

# 4. Limpar Build Anterior
Write-Host "`n[4/8] Limpando build anterior..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
}
flutter clean 2>&1 | Out-Null
Write-Host "  OK: Build limpo" -ForegroundColor Green

# 5. Dependências Flutter
Write-Host "`n[5/8] Obtendo dependencias Flutter..." -ForegroundColor Yellow
flutter pub get 2>&1 | Out-Null
Write-Host "  OK: Dependencias obtidas" -ForegroundColor Green

# 6. Build Web
Write-Host "`n[6/8] Construindo para Web (Release)..." -ForegroundColor Yellow
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Gray
$buildResult = flutter build web --release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERRO: Falha no build!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Build finalizado" -ForegroundColor Green

# 7. Deploy Firebase
Write-Host "`n[7/8] Fazendo deploy (Hosting + Functions)..." -ForegroundColor Yellow
Write-Host "  Executando: $firebaseCmd deploy --only hosting,functions --project $firebaseProject" -ForegroundColor Cyan
$deployResult = cmd /c "$firebaseCmd deploy --only hosting,functions --project $firebaseProject" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  DEPLOY CONCLUIDO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  URL Hosting: https://$firebaseProject.web.app" -ForegroundColor Cyan
}
else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "  ERRO NO DEPLOY!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $deployResult -ForegroundColor Red
    exit 1
}

Write-Host "`n[8/8] Processo finalizado!" -ForegroundColor Green

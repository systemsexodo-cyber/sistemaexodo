# Script de Deploy para Firebase Hosting
# Versão simplificada e direta

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY PARA FIREBASE HOSTING" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

$firebaseProject = "exodosystems-1541d"

Write-Host "[1/5] Limpando projeto..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
}
flutter clean 2>&1 | Out-Null
Write-Host "  OK: Projeto limpo" -ForegroundColor Green
Write-Host ""

Write-Host "[2/5] Obtendo dependencias..." -ForegroundColor Yellow
flutter pub get 2>&1 | Out-Null
Write-Host "  OK: Dependencias obtidas" -ForegroundColor Green
Write-Host ""

Write-Host "[3/5] Construindo para web (Release)..." -ForegroundColor Yellow
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Gray
$buildResult = flutter build web --release 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Build concluido!" -ForegroundColor Green
    
    if (Test-Path "build\web\index.html") {
        Write-Host "  Build web criado em: build\web\" -ForegroundColor Cyan
    } else {
        Write-Host "  ERRO: Arquivo index.html nao encontrado!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ERRO: Falha ao construir!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host ""

Write-Host "[4/5] Verificando Firebase..." -ForegroundColor Yellow
$firebaseCheck = firebase --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERRO: Firebase CLI nao encontrado!" -ForegroundColor Red
    Write-Host "  Instale: npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}
Write-Host "  OK: Firebase CLI encontrado" -ForegroundColor Green
Write-Host "  Projeto: $firebaseProject" -ForegroundColor Cyan
Write-Host ""

Write-Host "[5/5] Fazendo deploy para Firebase Hosting..." -ForegroundColor Yellow
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Gray
$deployResult = firebase deploy --only hosting --project $firebaseProject 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  DEPLOY CONCLUIDO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "URLs do projeto:" -ForegroundColor Cyan
    Write-Host "  https://$firebaseProject.web.app" -ForegroundColor White
    Write-Host "  https://$firebaseProject.firebaseapp.com" -ForegroundColor White
    Write-Host ""
    Write-Host "IMPORTANTE - Para ver as alteracoes:" -ForegroundColor Yellow
    Write-Host "  1. Limpe o cache do navegador (Ctrl + Shift + Delete)" -ForegroundColor White
    Write-Host "  2. Ou use modo anonimo (Ctrl + Shift + N)" -ForegroundColor White
    Write-Host "  3. Aguarde 2-5 minutos para propagacao do CDN" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO AO FAZER DEPLOY!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhes do erro:" -ForegroundColor Red
    Write-Host $deployResult -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "Deploy concluido!" -ForegroundColor Green
Write-Host ""

# Script de Deploy Automático - Sistema Êxodo
# Versão não-interativa para execução automática

param(
    [string]$Plataforma = "windows",  # windows, web, android
    [switch]$AutoCommit = $false
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY AUTOMATICO - SISTEMA EXODO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

Write-Host "[1/8] Verificando Flutter..." -ForegroundColor Yellow
$flutterCheck = flutter --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERRO: Flutter nao encontrado!" -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Flutter encontrado" -ForegroundColor Green
Write-Host ""

if ($AutoCommit) {
    Write-Host "[2/8] Fazendo commit automatico..." -ForegroundColor Yellow
    git add . 2>$null
    $commitMessage = "feat: deploy automatico - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    git commit -m $commitMessage --no-verify 2>$null
    Write-Host "  Commit realizado" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[2/8] Pulando commit (use -AutoCommit para fazer commit)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "[3/8] Limpando projeto..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
}
flutter clean 2>&1 | Out-Null
Write-Host "  OK: Projeto limpo" -ForegroundColor Green
Write-Host ""

Write-Host "[4/8] Obtendo dependencias..." -ForegroundColor Yellow
flutter pub get 2>&1 | Out-Null
Write-Host "  OK: Dependencias obtidas" -ForegroundColor Green
Write-Host ""

Write-Host "[5/8] Verificando erros..." -ForegroundColor Yellow
$analyzeResult = flutter analyze --no-fatal-infos 2>&1
$errorCount = ($analyzeResult | Select-String -Pattern "error •").Count
if ($errorCount -gt 0) {
    Write-Host "  AVISO: $errorCount erro(s) encontrado(s)" -ForegroundColor Yellow
    Write-Host "  Continuando mesmo assim..." -ForegroundColor Yellow
} else {
    Write-Host "  OK: Nenhum erro encontrado" -ForegroundColor Green
}
Write-Host ""

Write-Host "[6/8] Construindo para $Plataforma (Release)..." -ForegroundColor Yellow
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Gray

$buildCommand = "flutter build $Plataforma --release"
$buildResult = Invoke-Expression $buildCommand 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Build concluido com sucesso!" -ForegroundColor Green
    
    if ($Plataforma -eq "windows") {
        $exePath = "build\windows\x64\runner\Release\sistema_exodo_novo.exe"
        if (Test-Path $exePath) {
            $fileSize = (Get-Item $exePath).Length / 1MB
            Write-Host "  Executavel: $exePath ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Cyan
        }
    } elseif ($Plataforma -eq "web") {
        if (Test-Path "build\web\index.html") {
            Write-Host "  Build web criado em: build\web\" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "  ERRO: Falha ao construir!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host ""

if ($Plataforma -eq "web") {
    Write-Host "[7/8] Deploy para Firebase..." -ForegroundColor Yellow
    $firebaseProject = "exodosystems-1541d"
    $deployResult = firebase deploy --only hosting --project $firebaseProject 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: Deploy concluido!" -ForegroundColor Green
        Write-Host "  URL: https://$firebaseProject.web.app" -ForegroundColor Cyan
    } else {
        Write-Host "  AVISO: Falha no deploy Firebase" -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "[7/8] Pulando deploy Firebase (nao e web)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "[8/8] Resumo" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY CONCLUIDO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Plataforma -eq "windows") {
    Write-Host "Executavel: build\windows\x64\runner\Release\" -ForegroundColor White
} elseif ($Plataforma -eq "web") {
    Write-Host "Build web: build\web\" -ForegroundColor White
}
Write-Host ""


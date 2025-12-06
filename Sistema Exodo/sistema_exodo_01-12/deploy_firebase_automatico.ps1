# Script de Deploy Automático para Firebase Hosting
# Baseado no deploy_completo.ps1 - versão não-interativa

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETO PARA FIREBASE HOSTING" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

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
    } else {
        Write-Host "  AVISO: Falha ao fazer commit. Continuando mesmo assim..." -ForegroundColor Yellow
    }
} else {
    Write-Host "  OK: Nenhuma alteracao relevante nao commitada." -ForegroundColor Green
}
Write-Host ""

Write-Host "[2/7] Verificando projeto Firebase..." -ForegroundColor Yellow
$firebaseProject = "exodosystems-1541d"
Write-Host "  Projeto alvo: $firebaseProject" -ForegroundColor Cyan
$currentProject = cmd /c "firebase use" 2>$null | Select-String -Pattern "using"
if ($currentProject -notmatch $firebaseProject) {
    Write-Host "  Mudando para o projeto $firebaseProject..." -ForegroundColor Yellow
    cmd /c "firebase use $firebaseProject" 2>&1 | Out-Null
}
Write-Host "  OK: Projeto Firebase configurado" -ForegroundColor Green
Write-Host ""

Write-Host "[3/7] REMOVENDO COMPLETAMENTE o diretorio build..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  OK: Diretorio build removido completamente!" -ForegroundColor Green
} else {
    Write-Host "  OK: Diretorio build nao existe (ja esta limpo)." -ForegroundColor Green
}
Write-Host ""

Write-Host "[4/7] Limpando cache do Flutter..." -ForegroundColor Yellow
$cleanResult = flutter clean 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Cache do Flutter limpo!" -ForegroundColor Green
} else {
    Write-Host "  AVISO: Erro ao limpar cache. Continuando mesmo assim..." -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[5/7] Obtendo dependencias do Flutter..." -ForegroundColor Yellow
$pubGetResult = flutter pub get 2>&1
$pubGetOutput = $pubGetResult | Out-String
if ($pubGetOutput -match "Got dependencies!" -or $LASTEXITCODE -eq 0) {
    Write-Host "  OK: Dependencias obtidas com sucesso!" -ForegroundColor Green
} else {
    Write-Host "  AVISO: Alguns avisos foram encontrados, mas continuando..." -ForegroundColor Yellow
    if ($pubGetOutput -match "Got dependencies!") {
        Write-Host "  OK: Dependencias foram obtidas mesmo com avisos!" -ForegroundColor Green
    } else {
        Write-Host "  ERRO: Falha critica ao obter dependencias!" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

Write-Host "[6/7] Construindo projeto para web (modo release)..." -ForegroundColor Yellow
Write-Host "  Executando: flutter build web --release" -ForegroundColor Cyan
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Yellow
Write-Host "  IMPORTANTE: Este build sera COMPLETAMENTE NOVO!" -ForegroundColor Cyan
$buildResult = flutter build web --release 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Build concluido com sucesso!" -ForegroundColor Green
    
    if (Test-Path "build\web\index.html") {
        $buildTime = (Get-Item "build\web\index.html").LastWriteTime
        Write-Host "  Build criado em: $buildTime" -ForegroundColor Cyan
    } else {
        Write-Host "  ERRO: Arquivo build\web\index.html nao foi criado!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ERRO: Falha ao construir o projeto!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host ""

Write-Host "[7/7] Fazendo deploy para Firebase Hosting..." -ForegroundColor Yellow
Write-Host "  Executando: firebase deploy --only hosting --project $firebaseProject" -ForegroundColor Cyan
$deployResult = cmd /c "firebase deploy --only hosting --project $firebaseProject" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  DEPLOY REALIZADO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Projeto: $firebaseProject" -ForegroundColor Cyan
    Write-Host "URL: https://$firebaseProject.web.app" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANTE - PARA VER AS ALTERACOES:" -ForegroundColor Yellow
    Write-Host "  1. Limpe o cache do navegador (Ctrl + Shift + Delete)" -ForegroundColor White
    Write-Host "  2. Ou use modo anonimo (Ctrl + Shift + N)" -ForegroundColor White
    Write-Host "  3. Ou faca hard refresh (Ctrl + Shift + R)" -ForegroundColor White
    Write-Host "  4. Aguarde 2-5 minutos para propagacao do CDN" -ForegroundColor White
    Write-Host ""
    Write-Host "O QUE FOI FEITO:" -ForegroundColor Cyan
    Write-Host "  [OK] Build antigo foi REMOVIDO completamente" -ForegroundColor Green
    Write-Host "  [OK] Novo build foi criado do zero" -ForegroundColor Green
    Write-Host "  [OK] Deploy foi feito com arquivos atualizados" -ForegroundColor Green
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

Write-Host "[OK] Processo concluido!" -ForegroundColor Green
Write-Host ""


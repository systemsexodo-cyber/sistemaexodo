# Script de Deploy FORÇADO - Garante que TODAS as alterações sejam aplicadas
# Este script limpa completamente o build e força uma atualização no Firebase

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY FORCADO - FORCAR ATUALIZACAO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do projeto
$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

Write-Host "[1/7] Verificando alterações não commitadas..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>$null
if ($gitStatus) {
    Write-Host "  AVISO: Há alterações não commitadas!" -ForegroundColor Yellow
    Write-Host "  Continuando com deploy mesmo assim (alterações locais serão incluídas no build)..." -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "  OK: Nenhuma alteração não commitada." -ForegroundColor Green
    Write-Host ""
}

Write-Host "[2/7] Verificando projeto Firebase..." -ForegroundColor Yellow
$firebaseProject = "exodosystems-1541d"
Write-Host "  Projeto alvo: $firebaseProject" -ForegroundColor Cyan

# Verificar se o projeto está configurado
$currentProject = cmd /c "firebase use" 2>$null | Select-String -Pattern "using"
if ($currentProject -notmatch $firebaseProject) {
    Write-Host "  Mudando para o projeto $firebaseProject..." -ForegroundColor Yellow
    $switchResult = cmd /c "firebase use $firebaseProject" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: Projeto Firebase configurado!" -ForegroundColor Green
    } else {
        Write-Host "  AVISO: Não foi possível mudar o projeto. Continuando..." -ForegroundColor Yellow
    }
} else {
    Write-Host "  OK: Projeto Firebase já configurado corretamente." -ForegroundColor Green
}
Write-Host ""

Write-Host "[3/7] REMOVENDO COMPLETAMENTE o diretório build..." -ForegroundColor Yellow
Write-Host "  Isso garante que nenhum arquivo antigo será usado!" -ForegroundColor Cyan
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  OK: Diretório build removido completamente!" -ForegroundColor Green
} else {
    Write-Host "  OK: Diretório build não existe (já está limpo)." -ForegroundColor Green
}
Write-Host ""

Write-Host "[4/7] Limpando cache do Flutter..." -ForegroundColor Yellow
Write-Host "  Executando: flutter clean" -ForegroundColor Cyan
$cleanResult = flutter clean 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Cache do Flutter limpo!" -ForegroundColor Green
} else {
    Write-Host "  AVISO: Erro ao limpar cache. Continuando mesmo assim..." -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[5/7] Obtendo dependências do Flutter..." -ForegroundColor Yellow
Write-Host "  Executando: flutter pub get" -ForegroundColor Cyan
$pubGetResult = flutter pub get 2>&1
$pubGetOutput = $pubGetResult | Out-String
if ($pubGetOutput -match "Got dependencies!" -or $LASTEXITCODE -eq 0) {
    Write-Host "  OK: Dependências obtidas com sucesso!" -ForegroundColor Green
    if ($pubGetOutput -match "Developer Mode") {
        Write-Host "  AVISO: Developer Mode pode ser necessário, mas continuando..." -ForegroundColor Yellow
    }
} else {
    Write-Host "  AVISO: Alguns avisos foram encontrados, mas continuando..." -ForegroundColor Yellow
    if ($pubGetOutput -match "Got dependencies!") {
        Write-Host "  OK: Dependências foram obtidas mesmo com avisos!" -ForegroundColor Green
    } else {
        Write-Host "  ERRO: Falha crítica ao obter dependências!" -ForegroundColor Red
        Write-Host $pubGetOutput -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

Write-Host "[6/7] Construindo projeto para web (modo release)..." -ForegroundColor Yellow
Write-Host "  Executando: flutter build web --release" -ForegroundColor Cyan
Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Yellow
Write-Host "  IMPORTANTE: Este build será COMPLETAMENTE NOVO!" -ForegroundColor Cyan
$buildResult = flutter build web --release 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK: Build concluído com sucesso!" -ForegroundColor Green
    
    # Verificar se o build foi criado
    if (Test-Path "build\web\index.html") {
        $buildTime = (Get-Item "build\web\index.html").LastWriteTime
        Write-Host "  Build criado em: $buildTime" -ForegroundColor Cyan
    } else {
        Write-Host "  ERRO: Arquivo build\web\index.html não foi criado!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ERRO: Falha ao construir o projeto!" -ForegroundColor Red
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}
Write-Host ""

Write-Host "[7/7] Fazendo deploy para Firebase Hosting (FORÇANDO ATUALIZAÇÃO)..." -ForegroundColor Yellow
Write-Host "  Executando: firebase deploy --only hosting --project $firebaseProject" -ForegroundColor Cyan
Write-Host "  Este deploy irá SUBSTITUIR completamente a versão anterior!" -ForegroundColor Yellow
Write-Host ""

# Fazer deploy com mensagem clara
$deployResult = cmd /c "firebase deploy --only hosting --project $firebaseProject" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  DEPLOY FORCADO REALIZADO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Projeto: $firebaseProject" -ForegroundColor Cyan
    Write-Host "URL: https://$firebaseProject.web.app" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANTE - PARA VER AS ALTERAÇÕES:" -ForegroundColor Yellow
    Write-Host "  1. Limpe o cache do navegador (Ctrl + Shift + Delete)" -ForegroundColor White
    Write-Host "  2. Ou use modo anônimo (Ctrl + Shift + N)" -ForegroundColor White
    Write-Host "  3. Ou faça hard refresh (Ctrl + Shift + R)" -ForegroundColor White
    Write-Host "  4. Aguarde 2-5 minutos para propagação do CDN" -ForegroundColor White
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


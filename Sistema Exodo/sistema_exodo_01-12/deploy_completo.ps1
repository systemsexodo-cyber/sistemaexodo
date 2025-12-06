# Script de Deploy Completo - Sistema Êxodo
# Suporta: Windows, Web (Firebase), Android
# Autor: Sistema Êxodo
# Data: $(Get-Date -Format 'yyyy-MM-dd')

param(
    [string]$Plataforma = "all",  # all, windows, web, android
    [switch]$SkipTests = $false,
    [switch]$SkipClean = $false
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETO - SISTEMA ÊXODO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do projeto
$projectPath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $projectPath

Write-Host "Diretório do projeto: $projectPath" -ForegroundColor Gray
Write-Host ""

# Verificar se Flutter está instalado
Write-Host "[1/10] Verificando Flutter..." -ForegroundColor Yellow
$flutterVersion = flutter --version 2>&1 | Select-String -Pattern "Flutter"
if (-not $flutterVersion) {
    Write-Host "  ERRO: Flutter não encontrado!" -ForegroundColor Red
    Write-Host "  Instale o Flutter: https://flutter.dev/docs/get-started/install" -ForegroundColor Yellow
    exit 1
}
Write-Host "  OK: Flutter encontrado" -ForegroundColor Green
Write-Host ""

# Verificar alterações não commitadas
Write-Host "[2/10] Verificando alterações não commitadas..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>$null
$relevantChanges = $gitStatus | Where-Object { 
    $_ -notmatch "\.salvamento_logs" -and 
    $_ -notmatch "commits\.log" -and 
    $_ -notmatch "sessao\.log" -and
    $_ -notmatch "^build\\" -and
    $_ -notmatch "\.dart_tool\\"
}
if ($relevantChanges) {
    Write-Host "  AVISO: Há alterações não commitadas!" -ForegroundColor Yellow
    Write-Host "  Deseja fazer commit automático? (S/N)" -ForegroundColor Cyan
    $response = Read-Host
    if ($response -eq "S" -or $response -eq "s") {
        Write-Host "  Fazendo commit automático..." -ForegroundColor Cyan
        git add . 2>$null
        $commitMessage = "feat: preparacao para deploy - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        git commit -m $commitMessage --no-verify 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Commit realizado com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "  AVISO: Falha ao fazer commit. Continuando..." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  OK: Nenhuma alteração relevante não commitada." -ForegroundColor Green
}
Write-Host ""

# Verificar erros de análise
Write-Host "[3/10] Verificando erros de código..." -ForegroundColor Yellow
$analyzeResult = flutter analyze --no-fatal-infos 2>&1
$errorCount = ($analyzeResult | Select-String -Pattern "error •").Count
if ($errorCount -gt 0) {
    Write-Host "  AVISO: Foram encontrados $errorCount erro(s)!" -ForegroundColor Yellow
    Write-Host "  Deseja continuar mesmo assim? (S/N)" -ForegroundColor Cyan
    $response = Read-Host
    if ($response -ne "S" -and $response -ne "s") {
        Write-Host "  Deploy cancelado pelo usuário." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  OK: Nenhum erro encontrado!" -ForegroundColor Green
}
Write-Host ""

# Limpar projeto
if (-not $SkipClean) {
    Write-Host "[4/10] Limpando projeto..." -ForegroundColor Yellow
    if (Test-Path "build") {
        Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
        Write-Host "  Diretório build removido" -ForegroundColor Gray
    }
    $cleanResult = flutter clean 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: Projeto limpo!" -ForegroundColor Green
    } else {
        Write-Host "  AVISO: Alguns avisos ao limpar. Continuando..." -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "[4/10] Limpeza pulada (--SkipClean)" -ForegroundColor Gray
    Write-Host ""
}

# Obter dependências
Write-Host "[5/10] Obtendo dependências..." -ForegroundColor Yellow
$pubGetResult = flutter pub get 2>&1
$pubGetOutput = $pubGetResult | Out-String
if ($pubGetOutput -match "Got dependencies!" -or $LASTEXITCODE -eq 0) {
    Write-Host "  OK: Dependências obtidas!" -ForegroundColor Green
} else {
    Write-Host "  ERRO: Falha ao obter dependências!" -ForegroundColor Red
    Write-Host $pubGetOutput -ForegroundColor Red
    exit 1
}
Write-Host ""

# Executar testes (opcional)
if (-not $SkipTests) {
    Write-Host "[6/10] Executando testes..." -ForegroundColor Yellow
    $testResult = flutter test 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: Todos os testes passaram!" -ForegroundColor Green
    } else {
        Write-Host "  AVISO: Alguns testes falharam. Continuando mesmo assim..." -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "[6/10] Testes pulados (--SkipTests)" -ForegroundColor Gray
    Write-Host ""
}

# Determinar plataformas para build
$platformsToBuild = @()
if ($Plataforma -eq "all") {
    $platformsToBuild = @("windows", "web")
} elseif ($Plataforma -eq "windows") {
    $platformsToBuild = @("windows")
} elseif ($Plataforma -eq "web") {
    $platformsToBuild = @("web")
} elseif ($Plataforma -eq "android") {
    $platformsToBuild = @("android")
} else {
    Write-Host "  ERRO: Plataforma inválida: $Plataforma" -ForegroundColor Red
    Write-Host "  Use: all, windows, web, android" -ForegroundColor Yellow
    exit 1
}

# Build para cada plataforma
$buildStep = 7
foreach ($platform in $platformsToBuild) {
    Write-Host "[$buildStep/10] Construindo para $platform (Release)..." -ForegroundColor Yellow
    
    $buildCommand = "flutter build $platform --release"
    Write-Host "  Executando: $buildCommand" -ForegroundColor Cyan
    Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Gray
    
    $buildResult = Invoke-Expression $buildCommand 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: Build para $platform concluído!" -ForegroundColor Green
        
        # Verificar arquivos de build
        if ($platform -eq "windows") {
            $exePath = "build\windows\x64\runner\Release\sistema_exodo_novo.exe"
            if (Test-Path $exePath) {
                $fileSize = (Get-Item $exePath).Length / 1MB
                Write-Host "  Executável criado: $exePath ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Cyan
            }
        } elseif ($platform -eq "web") {
            if (Test-Path "build\web\index.html") {
                Write-Host "  Build web criado em: build\web\" -ForegroundColor Cyan
            }
        } elseif ($platform -eq "android") {
            $apkPath = "build\app\outputs\flutter-apk\app-release.apk"
            if (Test-Path $apkPath) {
                $fileSize = (Get-Item $apkPath).Length / 1MB
                Write-Host "  APK criado: $apkPath ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "  ERRO: Falha ao construir para $platform!" -ForegroundColor Red
        Write-Host $buildResult -ForegroundColor Red
        Write-Host "  Continuando com outras plataformas..." -ForegroundColor Yellow
    }
    Write-Host ""
    $buildStep++
}

# Deploy para Firebase (se web foi construído)
if ($platformsToBuild -contains "web") {
    Write-Host "[$buildStep/10] Preparando deploy para Firebase..." -ForegroundColor Yellow
    
    $firebaseProject = "exodosystems-1541d"
    Write-Host "  Projeto Firebase: $firebaseProject" -ForegroundColor Cyan
    
    # Verificar se Firebase está configurado
    $firebaseCheck = firebase --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  AVISO: Firebase CLI não encontrado. Pulando deploy web." -ForegroundColor Yellow
        Write-Host "  Instale: npm install -g firebase-tools" -ForegroundColor Gray
    } else {
        Write-Host "  Deseja fazer deploy para Firebase Hosting? (S/N)" -ForegroundColor Cyan
        $response = Read-Host
        if ($response -eq "S" -or $response -eq "s") {
            Write-Host "  Fazendo deploy para Firebase..." -ForegroundColor Cyan
            $deployResult = firebase deploy --only hosting --project $firebaseProject 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  OK: Deploy para Firebase concluído!" -ForegroundColor Green
                Write-Host "  URL: https://$firebaseProject.web.app" -ForegroundColor Cyan
            } else {
                Write-Host "  ERRO: Falha no deploy para Firebase!" -ForegroundColor Red
                Write-Host $deployResult -ForegroundColor Red
            }
        } else {
            Write-Host "  Deploy para Firebase cancelado." -ForegroundColor Gray
        }
    }
    Write-Host ""
    $buildStep++
}

# Resumo final
Write-Host "[$buildStep/10] Resumo do Deploy" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$buildSuccess = @()
$buildFailed = @()

foreach ($platform in $platformsToBuild) {
    if ($platform -eq "windows") {
        if (Test-Path "build\windows\x64\runner\Release\sistema_exodo_novo.exe") {
            $buildSuccess += "Windows"
        } else {
            $buildFailed += "Windows"
        }
    } elseif ($platform -eq "web") {
        if (Test-Path "build\web\index.html") {
            $buildSuccess += "Web"
        } else {
            $buildFailed += "Web"
        }
    } elseif ($platform -eq "android") {
        if (Test-Path "build\app\outputs\flutter-apk\app-release.apk") {
            $buildSuccess += "Android"
        } else {
            $buildFailed += "Android"
        }
    }
}

if ($buildSuccess.Count -gt 0) {
    Write-Host "  [OK] Builds concluidos com sucesso:" -ForegroundColor Green
    foreach ($platform in $buildSuccess) {
        Write-Host "    - $platform" -ForegroundColor Green
    }
    Write-Host ""
}

if ($buildFailed.Count -gt 0) {
    Write-Host "  [ERRO] Builds que falharam:" -ForegroundColor Red
    foreach ($platform in $buildFailed) {
        Write-Host "    - $platform" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY CONCLUÍDO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Localizações dos builds
Write-Host "Localizações dos builds:" -ForegroundColor Cyan
if (Test-Path "build\windows\x64\runner\Release") {
    Write-Host "  Windows: build\windows\x64\runner\Release\" -ForegroundColor White
}
if (Test-Path "build\web") {
    Write-Host "  Web: build\web\" -ForegroundColor White
}
if (Test-Path "build\app\outputs\flutter-apk") {
    Write-Host "  Android: build\app\outputs\flutter-apk\" -ForegroundColor White
}
Write-Host ""

Write-Host "Para executar novamente:" -ForegroundColor Gray
Write-Host "  .\deploy_completo.ps1 -Plataforma windows" -ForegroundColor Gray
Write-Host "  .\deploy_completo.ps1 -Plataforma web" -ForegroundColor Gray
Write-Host "  .\deploy_completo.ps1 -Plataforma all" -ForegroundColor Gray
Write-Host ""

# Deploy Rapido - Sistema Exodo
# Executa apenas os comandos essenciais para build

param(
    [string]$Plataforma = "windows"
)

Write-Host "Deploy Rapido - Plataforma: $Plataforma" -ForegroundColor Cyan
Write-Host ""

Set-Location $PSScriptRoot

Write-Host "1. Limpando..." -ForegroundColor Yellow
flutter clean 2>&1 | Out-Null

Write-Host "2. Obtendo dependencias..." -ForegroundColor Yellow
flutter pub get 2>&1 | Out-Null

Write-Host "3. Construindo ($Plataforma)..." -ForegroundColor Yellow
flutter build $Plataforma --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Deploy concluido!" -ForegroundColor Green
    if ($Plataforma -eq "windows") {
        Write-Host "Executavel: build\windows\x64\runner\Release\sistema_exodo_novo.exe" -ForegroundColor Cyan
    } elseif ($Plataforma -eq "web") {
        Write-Host "Build web: build\web\" -ForegroundColor Cyan
    }
} else {
    Write-Host ""
    Write-Host "ERRO no build!" -ForegroundColor Red
    exit 1
}


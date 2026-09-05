# Script para executar Flutter Web sem problemas de navegador
# Resolve o problema de "Failed to launch browser"

param(
    [string]$Device = "web-server"
)

Write-Host "🚀 Executando Flutter Web..." -ForegroundColor Cyan
Write-Host ""

# Navegar para o diretório do projeto
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

# Verificar se está no diretório correto
if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "❌ Erro: pubspec.yaml não encontrado!" -ForegroundColor Red
    Write-Host "   Certifique-se de executar este script na raiz do projeto Flutter." -ForegroundColor Yellow
    exit 1
}

Write-Host "📁 Diretório: $projectRoot" -ForegroundColor Gray
Write-Host ""

# Opções de dispositivo disponíveis
$devices = @{
    "web-server" = "Servidor web (não abre navegador automaticamente)"
    "chrome"     = "Google Chrome"
    "edge"       = "Microsoft Edge"
}

if ($devices.ContainsKey($Device)) {
    Write-Host "🌐 Dispositivo selecionado: $Device" -ForegroundColor Yellow
    Write-Host "   $($devices[$Device])" -ForegroundColor Gray
}
else {
    Write-Host "⚠️  Dispositivo '$Device' não reconhecido. Usando 'web-server'." -ForegroundColor Yellow
    $Device = "web-server"
}

Write-Host ""
Write-Host "🧹 Limpando processos e temporários..." -ForegroundColor Cyan
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Stop-Process -Name flutter -Force -ErrorAction SilentlyContinue
Stop-Process -Name dart -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $env:TEMP -Filter "flutter_tools.*" -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "▶️  Iniciando Flutter..." -ForegroundColor Green

Write-Host ""

# Executar Flutter
if ($Device -eq "web-server") {
    Write-Host "💡 Dica: Após iniciar, abra manualmente:" -ForegroundColor Cyan
    Write-Host "   http://localhost:8080" -ForegroundColor Gray
    Write-Host ""
    flutter run -d $Device --web-port 8080
}
else {
    flutter run -d $Device --web-port 8080
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Erro ao executar Flutter!" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Soluções alternativas:" -ForegroundColor Yellow
    Write-Host "   1. Tente com Edge: .\flutter_run_web.ps1 -Device edge" -ForegroundColor Gray
    Write-Host "   2. Tente com Chrome: .\flutter_run_web.ps1 -Device chrome" -ForegroundColor Gray
    Write-Host "   3. Use web-server e abra manualmente: .\flutter_run_web.ps1 -Device web-server" -ForegroundColor Gray
    exit 1
}







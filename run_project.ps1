# ============================================================================
# Script Rápido de Execução - Sistema Êxodo
# ============================================================================
# Use este script para executar rapidamente o projeto Flutter
# ============================================================================

param(
    [string]$Device = "edge"
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Sistema Êxodo - Execução Rápida" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se está no diretório correto
if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "[ERRO] Arquivo pubspec.yaml não encontrado!" -ForegroundColor Red
    Write-Host "[INFO] Execute este script no diretório raiz do projeto" -ForegroundColor Yellow
    pause
    exit 1
}

# Matar processos travados
Write-Host "[INFO] Encerrando processos Flutter anteriores..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.Name -like '*flutter*' -or $_.Name -like '*dart*' } | Stop-Process -Force -ErrorAction SilentlyContinue

# Remover lock file
$flutterPath = Split-Path (Split-Path (Get-Command flutter).Source -Parent) -ErrorAction SilentlyContinue
if ($flutterPath) {
    Remove-Item "$flutterPath\bin\cache\flutter.bat.lock" -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 1

# Mostrar dispositivos disponíveis
Write-Host "`n[INFO] Dispositivos disponíveis:" -ForegroundColor Yellow
flutter devices

# Executar projeto
Write-Host "`n[INFO] Executando projeto no dispositivo: $Device" -ForegroundColor Yellow
Write-Host ""

flutter run -d $Device

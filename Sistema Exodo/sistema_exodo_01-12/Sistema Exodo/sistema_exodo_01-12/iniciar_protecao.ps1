# ============================================================
# INICIAR SISTEMA DE PROTEÇÃO E SALVAMENTO AUTOMÁTICO
# ============================================================
# Este script inicia o sistema de salvamento inteligente
# em uma janela minimizada
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INICIANDO SISTEMA DE PROTEÇÃO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do script
if ($PSScriptRoot) {
    $scriptPath = Join-Path $PSScriptRoot "salvamento_inteligente.ps1"
} else {
    $scriptPath = Join-Path (Get-Location).Path "salvamento_inteligente.ps1"
}

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERRO: Script não encontrado: $scriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "Iniciando salvamento inteligente..." -ForegroundColor Yellow
Write-Host "  - Commit automático: a cada 20 minutos" -ForegroundColor Gray
Write-Host "  - Push automático: a cada 30 minutos" -ForegroundColor Gray
Write-Host "  - Backups automáticos antes de cada operação" -ForegroundColor Gray
Write-Host ""

# Iniciar em janela minimizada
$scriptFullPath = Resolve-Path $scriptPath
Start-Process powershell.exe -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptFullPath`"" -WindowStyle Minimized

Write-Host "========================================" -ForegroundColor Green
Write-Host "  SISTEMA INICIADO COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "O script está rodando em background (janela minimizada)." -ForegroundColor Yellow
Write-Host ""
Write-Host "Para parar:" -ForegroundColor Cyan
Write-Host "  - Feche a janela PowerShell minimizada na barra de tarefas" -ForegroundColor White
Write-Host "  - Ou pressione Ctrl+C na janela do script" -ForegroundColor White
Write-Host ""
Write-Host "Para verificar logs:" -ForegroundColor Cyan
Write-Host "  Get-Content .salvamento_logs\sessao.log" -ForegroundColor White
Write-Host ""


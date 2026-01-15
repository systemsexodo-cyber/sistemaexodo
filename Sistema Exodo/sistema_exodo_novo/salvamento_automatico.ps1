# Script de Salvamento Automatico Periodico
# Execute este script em background para salvar automaticamente a cada X minutos

param(
    [int]$IntervalMinutes = 30
)

Write-Host "Salvamento automatico iniciado (intervalo: $IntervalMinutes minutos)" -ForegroundColor Cyan
Write-Host "Pressione Ctrl+C para parar" -ForegroundColor Yellow
Write-Host ""

$scriptPath = Join-Path (Split-Path $PSScriptRoot) "sistema_exodo_novo\salvar_alteracoes.ps1"

while ($true) {
    Start-Sleep -Seconds ($IntervalMinutes * 60)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Salvando automaticamente..." -ForegroundColor Gray
    & $scriptPath | Out-Null
}

# Script de Salvamento Automatico Periodico
# Execute este script em background para salvar automaticamente a cada X minutos

param(
    [int]$IntervalMinutes = 30
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SALVAMENTO AUTOMATICO ATIVADO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Intervalo: $IntervalMinutes minutos" -ForegroundColor Yellow
Write-Host "Pressione Ctrl+C para parar" -ForegroundColor Yellow
Write-Host ""

# Detectar diretório do projeto
if ($PSScriptRoot) {
    $projectPath = $PSScriptRoot
} else {
    $projectPath = (Get-Location).Path
}

# Encontrar repositório Git
$gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    $projectPath = $gitCheck
} else {
    Write-Host "ERRO: Nao e um repositorio Git valido!" -ForegroundColor Red
    exit 1
}

$scriptPath = Join-Path $projectPath "sistema_exodo_novo\salvar_alteracoes.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERRO: Script de salvamento nao encontrado: $scriptPath" -ForegroundColor Red
    exit 1
}

$iteration = 0

while ($true) {
    $iteration++
    $currentTime = Get-Date -Format "HH:mm:ss"
    
    Write-Host "[$currentTime] Iteracao $iteration - Verificando alteracoes..." -ForegroundColor Gray
    
    # Verificar se há alterações antes de salvar
    Set-Location $projectPath
    $status = git status --porcelain 2>$null
    
    if ($status -and $status.Length -gt 0) {
        Write-Host "[$currentTime] Alteracoes detectadas! Salvando..." -ForegroundColor Yellow
        & $scriptPath | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[$currentTime] Alteracoes salvas com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "[$currentTime] Erro ao salvar alteracoes" -ForegroundColor Red
        }
    } else {
        Write-Host "[$currentTime] Nenhuma alteracao detectada" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    
    # Aguardar próximo intervalo
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}




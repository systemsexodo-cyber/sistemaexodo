# Script para Habilitar Developer Mode no Windows
# Necessário para suporte a symlinks no Flutter

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  HABILITANDO DEVELOPER MODE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se está executando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ATENCAO: Este script precisa ser executado como Administrador!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opcoes:" -ForegroundColor Cyan
    Write-Host "  1. Clique com botao direito no PowerShell e selecione 'Executar como Administrador'" -ForegroundColor White
    Write-Host "  2. Ou abra as configuracoes manualmente:" -ForegroundColor White
    Write-Host ""
    Write-Host "Abrindo configuracoes do Windows..." -ForegroundColor Yellow
    Start-Process "ms-settings:developers"
    Write-Host ""
    Write-Host "Nas configuracoes:" -ForegroundColor Cyan
    Write-Host "  1. Vá em 'Para desenvolvedores'" -ForegroundColor White
    Write-Host "  2. Ative 'Modo de desenvolvedor'" -ForegroundColor White
    Write-Host "  3. Feche esta janela e tente novamente" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Executando como Administrador - OK" -ForegroundColor Green
Write-Host ""

# Tentar habilitar Developer Mode via registro
Write-Host "[1/2] Habilitando Developer Mode via registro..." -ForegroundColor Yellow

try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    
    # Criar chave se não existir
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Habilitar Developer Mode
    Set-ItemProperty -Path $regPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $regPath -Name "AllowAllTrustedApps" -Value 1 -Type DWord -Force
    
    Write-Host "  Developer Mode habilitado via registro!" -ForegroundColor Green
    
} catch {
    Write-Host "  Aviso: Nao foi possivel habilitar via registro automaticamente" -ForegroundColor Yellow
    Write-Host "  Abrindo configuracoes do Windows..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[2/2] Abrindo configuracoes do Windows para confirmacao..." -ForegroundColor Yellow
Start-Process "ms-settings:developers"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PROCESSO CONCLUIDO" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Por favor, confirme nas configuracoes:" -ForegroundColor Cyan
Write-Host "  1. Vá em 'Para desenvolvedores'" -ForegroundColor White
Write-Host "  2. Verifique se 'Modo de desenvolvedor' está ATIVADO" -ForegroundColor White
Write-Host "  3. Se não estiver, ative manualmente" -ForegroundColor White
Write-Host ""
Write-Host "Depois de ativar, reinicie o terminal e tente novamente!" -ForegroundColor Yellow
Write-Host ""



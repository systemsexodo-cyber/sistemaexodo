# Script de Inicializacao - Carrega protecoes automaticamente
# Adicione este script ao seu perfil PowerShell para ativar automaticamente

$projectPath = "C:/Users/USER/Downloads"
$saveScript = "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\salvar_alteracoes.ps1"

# Funcao para salvar rapidamente
function Salvar-Alteracoes {
    Set-Location $projectPath
    & $saveScript
}

# Alias
Set-Alias -Name salvar -Value Salvar-Alteracoes -Scope Global

Write-Host "Protecoes automaticas carregadas!" -ForegroundColor Green
Write-Host "Use 'salvar' para salvar suas alteracoes rapidamente." -ForegroundColor Cyan

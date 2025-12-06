# Script de Configuração de Proteção Automática
# Configura salvamento automático e proteções contra erros

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURANDO PROTECAO AUTOMATICA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do projeto
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$projectPath = Split-Path $scriptDir -Parent

# Encontrar repositório Git
$gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    $gitDir = git -C $projectPath rev-parse --git-dir 2>$null
    $projectPath = $gitCheck
} else {
    Write-Host "ERRO: Nao e um repositorio Git valido!" -ForegroundColor Red
    exit 1
}

$hooksDir = Join-Path $gitDir "hooks"
$saveScript = Join-Path $scriptDir "salvar_alteracoes.ps1"

Write-Host "Diretorio do projeto: $projectPath" -ForegroundColor Gray
Write-Host "Diretorio de hooks: $hooksDir" -ForegroundColor Gray
Write-Host "Script de salvamento: $saveScript" -ForegroundColor Gray
Write-Host ""

# Criar diretório de hooks se não existir
if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    Write-Host "[1/6] Diretorio de hooks criado" -ForegroundColor Green
} else {
    Write-Host "[1/6] Diretorio de hooks encontrado" -ForegroundColor Green
}

# Hook pre-commit (PowerShell)
Write-Host "[2/6] Configurando hook pre-commit..." -ForegroundColor Yellow
$preCommitContent = @"
# Hook pre-commit: Salva automaticamente antes de cada commit
`$projectPath = "$projectPath"
`$scriptPath = "$saveScript"
Set-Location `$projectPath
& `$scriptPath | Out-Null
"@

$preCommitPath = Join-Path $hooksDir "pre-commit.ps1"
$preCommitContent | Out-File -FilePath $preCommitPath -Encoding UTF8

# Criar wrapper .bat para o hook (Git no Windows precisa disso)
$preCommitBat = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0pre-commit.ps1"
"@
$preCommitBatPath = Join-Path $hooksDir "pre-commit"
$preCommitBat | Out-File -FilePath $preCommitBatPath -Encoding ASCII
Write-Host "  Hook pre-commit configurado" -ForegroundColor Green

# Hook pre-push (PowerShell)
Write-Host "[3/6] Configurando hook pre-push..." -ForegroundColor Yellow
$prePushContent = @"
# Hook pre-push: Cria backup antes de push
`$projectPath = "$projectPath"
`$scriptPath = "$saveScript"
Set-Location `$projectPath
& `$scriptPath | Out-Null

# Criar backup adicional
`$backupDir = Join-Path `$projectPath "backups_automaticos"
if (-not (Test-Path `$backupDir)) {
    New-Item -ItemType Directory -Path `$backupDir -Force | Out-Null
}
`$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$backupFile = Join-Path `$backupDir "backup_pre_push_`$timestamp.zip"
`$sourcePath = Join-Path `$projectPath "sistema_exodo_novo"
if (Test-Path `$sourcePath) {
    Compress-Archive -Path `$sourcePath -DestinationPath `$backupFile -Force -ErrorAction SilentlyContinue
}
"@

$prePushPath = Join-Path $hooksDir "pre-push.ps1"
$prePushContent | Out-File -FilePath $prePushPath -Encoding UTF8

$prePushBat = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0pre-push.ps1"
"@
$prePushBatPath = Join-Path $hooksDir "pre-push"
$prePushBat | Out-File -FilePath $prePushBatPath -Encoding ASCII
Write-Host "  Hook pre-push configurado" -ForegroundColor Green

# Configurar Git para proteger branches importantes
Write-Host "[4/6] Configurando protecao de branches..." -ForegroundColor Yellow
git config --local receive.denyDeleteBranch true 2>$null
git config --local receive.denyForcePush true 2>$null
Write-Host "  Protecao de branches configurada" -ForegroundColor Green

# Criar alias Git para salvamento rápido
Write-Host "[5/6] Criando alias Git para salvamento rapido..." -ForegroundColor Yellow
git config --local alias.salvar "!powershell.exe -ExecutionPolicy Bypass -File `"$saveScript`"" 2>$null
Write-Host "  Alias 'git salvar' criado" -ForegroundColor Green

# Criar script de inicialização automática
Write-Host "[6/6] Criando script de inicializacao..." -ForegroundColor Yellow
$initScript = @"
# Script de Inicializacao - Carrega protecoes automaticamente
# Adicione este script ao seu perfil PowerShell para ativar automaticamente

`$projectPath = "$projectPath"
`$saveScript = "$saveScript"

# Funcao para salvar rapidamente
function Salvar-Alteracoes {
    Set-Location `$projectPath
    & `$saveScript
}

# Alias
Set-Alias -Name salvar -Value Salvar-Alteracoes -Scope Global

Write-Host "Protecoes automaticas carregadas!" -ForegroundColor Green
Write-Host "Use 'salvar' para salvar suas alteracoes rapidamente." -ForegroundColor Cyan
"@

$initPath = Join-Path $scriptDir "inicializar_protecoes.ps1"
$initScript | Out-File -FilePath $initPath -Encoding UTF8
Write-Host "  Script de inicializacao criado" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PROTECAO CONFIGURADA COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Protecoes ativas:" -ForegroundColor Cyan
Write-Host "  - Salvamento automatico antes de cada commit" -ForegroundColor White
Write-Host "  - Backup automatico antes de push" -ForegroundColor White
Write-Host "  - Protecao contra delete de branches" -ForegroundColor White
Write-Host "  - Protecao contra force push" -ForegroundColor White
Write-Host ""
Write-Host "Comandos disponiveis:" -ForegroundColor Cyan
Write-Host "  git salvar          - Salvar alteracoes manualmente" -ForegroundColor White
Write-Host "  .\salvar_alteracoes.ps1 - Salvar alteracoes (script completo)" -ForegroundColor White
Write-Host "  .\restaurar_versao.ps1  - Restaurar uma versao anterior" -ForegroundColor White
Write-Host "  .\salvamento_automatico.ps1 - Ativar salvamento periodico" -ForegroundColor White
Write-Host ""
Write-Host "Voce esta protegido contra erros!" -ForegroundColor Green
Write-Host ""


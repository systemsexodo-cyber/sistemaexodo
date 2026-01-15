# Script de Proteção Automática e Salvamento
# Este script configura proteções automáticas para salvar suas alterações e proteger contra erros

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURANDO PROTECAO AUTOMATICA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
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
    $gitDir = git -C $projectPath rev-parse --git-dir 2>$null
    $projectPath = $gitCheck
} else {
    Write-Host "ERRO: Nao e um repositorio Git valido!" -ForegroundColor Red
    exit 1
}

$hooksDir = Join-Path $gitDir "hooks"
$scriptPath = Join-Path $projectPath "sistema_exodo_novo\salvar_alteracoes.ps1"

Write-Host "Diretorio do projeto: $projectPath" -ForegroundColor Gray
Write-Host "Diretorio de hooks: $hooksDir" -ForegroundColor Gray
Write-Host ""

# Criar diretório de hooks se não existir
if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    Write-Host "[1/5] Diretorio de hooks criado" -ForegroundColor Green
} else {
    Write-Host "[1/5] Diretorio de hooks encontrado" -ForegroundColor Green
}

# Hook pre-commit: Salva automaticamente antes de cada commit
Write-Host "[2/5] Configurando hook pre-commit..." -ForegroundColor Yellow
$preCommitHook = @"
#!/bin/sh
# Hook pre-commit: Salva automaticamente antes de cada commit
# Este hook garante que todas as alterações sejam salvas antes de commitar

cd "$projectPath"
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" 2>&1 | Out-Null

# Permitir que o commit continue
exit 0
"@

$preCommitPath = Join-Path $hooksDir "pre-commit"
$preCommitHook | Out-File -FilePath $preCommitPath -Encoding ASCII -NoNewline
Write-Host "  Hook pre-commit configurado" -ForegroundColor Green

# Hook pre-push: Cria backup antes de push
Write-Host "[3/5] Configurando hook pre-push..." -ForegroundColor Yellow
$prePushHook = @"
#!/bin/sh
# Hook pre-push: Cria backup antes de enviar para o GitHub
# Protege contra perda de dados ao fazer push

cd "$projectPath"
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" 2>&1 | Out-Null

# Criar backup adicional
`$backupDir = Join-Path "$projectPath" "backups_automaticos"
if (-not (Test-Path `$backupDir)) {
    New-Item -ItemType Directory -Path `$backupDir -Force | Out-Null
}
`$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$backupFile = Join-Path `$backupDir "backup_pre_push_`$timestamp.zip"
Compress-Archive -Path "$projectPath\sistema_exodo_novo\*" -DestinationPath `$backupFile -Force

exit 0
"@

$prePushPath = Join-Path $hooksDir "pre-push"
$prePushHook | Out-File -FilePath $prePushPath -Encoding ASCII -NoNewline
Write-Host "  Hook pre-push configurado" -ForegroundColor Green

# Hook pre-reset: Protege contra reset acidental
Write-Host "[4/5] Configurando protecao contra reset..." -ForegroundColor Yellow
$preResetHook = @"
#!/bin/sh
# Hook pre-reset: Cria backup antes de reset
# Protege contra perda de dados ao fazer reset

cd "$projectPath"
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" 2>&1 | Out-Null

Write-Host ""
Write-Host "ATENCAO: Voce esta prestes a fazer um reset!" -ForegroundColor Yellow
Write-Host "Um backup automatico foi criado antes desta operacao." -ForegroundColor Cyan
Write-Host ""

exit 0
"@

$preResetPath = Join-Path $hooksDir "pre-reset"
$preResetHook | Out-File -FilePath $preResetPath -Encoding ASCII -NoNewline
Write-Host "  Protecao contra reset configurada" -ForegroundColor Green

# Script de salvamento automático periódico
Write-Host "[5/5] Criando script de salvamento periodico..." -ForegroundColor Yellow
$autoSaveScript = @"
# Script de Salvamento Automatico Periodico
# Execute este script em background para salvar automaticamente a cada X minutos

param(
    [int]`$IntervalMinutes = 30
)

Write-Host "Salvamento automatico iniciado (intervalo: `$IntervalMinutes minutos)" -ForegroundColor Cyan
Write-Host "Pressione Ctrl+C para parar" -ForegroundColor Yellow
Write-Host ""

`$scriptPath = Join-Path (Split-Path `$PSScriptRoot) "sistema_exodo_novo\salvar_alteracoes.ps1"

while (`$true) {
    Start-Sleep -Seconds (`$IntervalMinutes * 60)
    Write-Host "[`$(Get-Date -Format 'HH:mm:ss')] Salvando automaticamente..." -ForegroundColor Gray
    & `$scriptPath | Out-Null
}
"@

$autoSavePath = Join-Path (Split-Path $PSScriptRoot -Parent) "sistema_exodo_novo\salvamento_automatico.ps1"
if (-not (Test-Path (Split-Path $autoSavePath -Parent))) {
    $autoSavePath = Join-Path $projectPath "sistema_exodo_novo\salvamento_automatico.ps1"
}
$autoSaveScript | Out-File -FilePath $autoSavePath -Encoding UTF8
Write-Host "  Script de salvamento periodico criado" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PROTECAO CONFIGURADA COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Protecoes ativas:" -ForegroundColor Cyan
Write-Host "  - Salvamento automatico antes de cada commit" -ForegroundColor White
Write-Host "  - Backup automatico antes de push" -ForegroundColor White
Write-Host "  - Protecao contra reset acidental" -ForegroundColor White
Write-Host "  - Script de salvamento periodico disponivel" -ForegroundColor White
Write-Host ""
Write-Host "Para ativar salvamento periodico (a cada 30 minutos):" -ForegroundColor Yellow
Write-Host "  .\sistema_exodo_novo\salvamento_automatico.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Voce esta protegido!" -ForegroundColor Green


# ============================================================
# BACKUP AUTOMÁTICO DO PROJETO PARA GOOGLE DRIVE
# ============================================================
# Este script realiza o ZIP do projeto e faz o upload para o 
# Google Drive usando uma conta de serviço (Service Account).
# ============================================================

$projectPath = $PSScriptRoot
if (-not $projectPath) { $projectPath = Get-Location }
Set-Location $projectPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  BACKUP AUTOMÁTICO -> GOOGLE DRIVE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Verificar se existe a credencial do Google Drive (OAuth Client ID)
$jsonPath = Join-Path $projectPath "gdrive_client_id.json"
if (-not (Test-Path $jsonPath)) {
    Write-Host "!!! AVISO: Arquivo 'gdrive_client_id.json' não encontrado." -ForegroundColor Yellow
    Write-Host "Para usar seu espaço pessoal do Drive, você precisa:" -ForegroundColor Gray
    Write-Host "1. Criar um 'ID do cliente OAuth' do tipo 'App de desktop' no Google Cloud Console."
    Write-Host "2. Baixar o JSON, renomear para 'gdrive_client_id.json' e salvar no projeto."
    Write-Host ""
    Write-Host "Deseja continuar apenas com o ZIP local? (S/N)"
    $ans = Read-Host
    if ($ans -ne 's' -and $ans -ne 'S') { exit }
}

# 2. Gerar o ZIP do projeto usando o script existente
Write-Host "`n>>> [1/2] Gerando ZIP do projeto..." -ForegroundColor Cyan
$zipScript = Join-Path $projectPath "backup_projeto_zip.ps1"
& $zipScript

# O script backup_projeto_zip.ps1 gera o arquivo em ../backups_exodo/
$parentDir = Split-Path -Parent $projectPath
$backupBaseDir = Join-Path $parentDir "backups_exodo"

# Pegar o arquivo mais recente criado
$latestZip = Get-ChildItem -Path $backupBaseDir -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $latestZip) {
    Write-Host "!!! ERRO: Não foi possível localizar o arquivo ZIP gerado." -ForegroundColor Red
    exit 1
}

Write-Host ">>> Arquivo localizado: $($latestZip.Name)" -ForegroundColor Green

# 3. Upload para o Google Drive via Dart CLI
if (Test-Path $jsonPath) {
    Write-Host "`n>>> [2/2] Enviando para o Google Drive..." -ForegroundColor Cyan
    
    # Executar script Dart
    # Usamos o flutter pub run para garantir que as dependências do pubspec estão disponíveis
    dart lib/scripts/gdrive_backup.dart "$($latestZip.FullName)" "$jsonPath"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  BACKUP CONCLUÍDO COM SUCESSO NO DRIVE!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    }
    else {
        Write-Host "`n!!! FALHA no upload para o Google Drive." -ForegroundColor Red
    }
}
else {
    Write-Host "`n>>> Backup ZIP concluído localmente, mas upload ignorado por falta de credenciais." -ForegroundColor Yellow
}

Write-Host "`nBackup finalizado em: $((Get-Date).ToString('HH:mm:ss'))"

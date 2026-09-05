# ============================================================
# RESTAURAR BACKUP - SISTEMA EXODO
# Restaura um backup .dump (pg_restore) no banco local.
#
# USO (PowerShell):
#   powershell -ExecutionPolicy Bypass -File RESTAURAR_BACKUP.ps1
#       -> restaura o backup mais recente de .\backups_postgresql\
#   powershell -ExecutionPolicy Bypass -File RESTAURAR_BACKUP.ps1 D:\meu\backup.dump
#       -> restaura um arquivo especifico
#
# IMPORTANTE: FECHE o sistema (sistema_exodo_novo.exe) ANTES de restaurar.
# O banco sera recriado do backup - dados locais atuais serao substituidos.
# ============================================================

param(
    [string]$Arquivo = ""
)

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Localizar PostgreSQL (mesma logica do backup) ---
$PgRestore = $null
$Psql = $null
$Candidatos = @(
    (Join-Path $ProjectRoot "postgresql\pgsql\bin"),
    (Join-Path $ProjectRoot "postgresql\bin"),
    "C:\SistemaExodo\postgresql\bin",
    (Join-Path $ProjectRoot "..\postgresql\bin")
)
foreach ($c in $Candidatos) {
    $pr = Join-Path $c "pg_restore.exe"
    $ps = Join-Path $c "psql.exe"
    if ((Test-Path $pr) -and (Test-Path $ps)) { $PgRestore = $pr; $Psql = $ps; break }
}
if (-not $PgRestore) {
    Write-Host "ERRO: pg_restore.exe nao encontrado." -ForegroundColor Red
    exit 1
}

# --- Credenciais (do .env) ---
$DbHost = "localhost"; $DbPort = 5432; $DbName = "exodo_db"; $DbUser = "exodo_user"; $DbPass = "ex@#$"
$envFile = Join-Path $ProjectRoot ".env"
if (Test-Path $envFile) {
    foreach ($linha in (Get-Content $envFile -ErrorAction SilentlyContinue)) {
        if     ($linha -match '^\s*DB_HOST\s*=\s*(.+)\s*$')     { $DbHost = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_PORT\s*=\s*(.+)\s*$')     { $DbPort = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_NAME\s*=\s*(.+)\s*$')     { $DbName = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_USER\s*=\s*(.+)\s*$')     { $DbUser = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_PASSWORD\s*=\s*(.+)\s*$') { $DbPass = $Matches[1].Trim() }
    }
}

# --- Encontrar arquivo .dump ---
if ($Arquivo -eq "") {
    $dir = Join-Path $ProjectRoot "backups_postgresql"
    $Arquivo = Get-ChildItem -Path $dir -Filter "exodo_backup_*.dump" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Arquivo) {
        Write-Host "Nenhum backup .dump encontrado em: $dir" -ForegroundColor Red
        Write-Host "Passe o caminho do arquivo: RESTAURAR_BACKUP.ps1 C:\caminho\backup.dump" -ForegroundColor Yellow
        exit 1
    }
}
if (-not (Test-Path $Arquivo)) {
    Write-Host "Arquivo nao encontrado: $Arquivo" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESTAURAR BACKUP - SISTEMA EXODO" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Arquivo: $Arquivo" -ForegroundColor White
Write-Host "Banco:   $DbName em $DbHost`:$DbPort" -ForegroundColor White
Write-Host ""
Write-Host "AVISO: isso vai SUBSTITUIR os dados atuais do banco local!" -ForegroundColor Yellow
Write-Host "Confirma? Digite SIM para continuar:" -ForegroundColor Yellow
$confirma = Read-Host
if ($confirma -ne "SIM") {
    Write-Host "Cancelado." -ForegroundColor Red
    exit 1
}

$env:PGPASSWORD = $DbPass

# 1. Verificar se PostgreSQL esta rodando
Write-Host "Verificando PostgreSQL..." -ForegroundColor Cyan
& $Psql -h $DbHost -p $DbPort -U $DbUser -d postgres -c "SELECT 1" -t -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: PostgreSQL nao esta acessivel. Inicie por: scripts\iniciar_postgres.bat" -ForegroundColor Red
    exit 1
}

# 2. Recriar banco vazio (drop + create)
Write-Host "Recriando banco $DbName..." -ForegroundColor Cyan
& $Psql -h $DbHost -p $DbPort -U $DbUser -d postgres -c "DROP DATABASE IF EXISTS `"$DbName`" WITH (FORCE);" 2>&1
& $Psql -h $DbHost -p $DbPort -U $DbUser -d postgres -c "CREATE DATABASE `"$DbName`";" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: nao foi possivel recriar o banco. Veja a mensagem acima." -ForegroundColor Red
    exit 1
}

# 3. Restaurar
Write-Host "Restaurando backup... (pode levar alguns minutos)" -ForegroundColor Cyan
& $PgRestore -h $DbHost -p $DbPort -U $DbUser -d $DbName --clean --if-exists --no-owner "$Arquivo" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  RESTAURACAO CONCLUIDA COM SUCESSO!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Abra o sistema e verifique os dados." -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "ERRO na restauracao. Veja as mensagens acima." -ForegroundColor Red
    Write-Host "Dica: se aparecer 'relation already exists', reexecute - o --clean resolve na 2a vez." -ForegroundColor Yellow
    exit 1
}
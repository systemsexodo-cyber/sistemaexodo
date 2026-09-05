# ============================================================================
# REPARAR BANCO - SISTEMA EXODO
# ============================================================================
# Cria o banco exodo_db e as tabelas se NAO existirem.
# Use este script quando o PostgreSQL estiver rodando mas o banco
# nao foi criado (ex: instalacao antiga cancelada no meio).
# Pode rodar quantas vezes quiser (e idempotente).
# ============================================================================
# IMPORTANTE: somente caracteres ASCII aqui (PS 5.1 le como ANSI).
# ============================================================================

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Split-Path $ScriptDir -Parent
$pgBin = Join-Path $AppDir "postgresql\bin"
$psql = Join-Path $pgBin "psql.exe"

$DbHost = "localhost"
$DbPort = "5432"
$DbUser = "exodo_user"
$DbPassword = "ex@#$"
$DbName = "exodo_db"

Write-Host "============================================"
Write-Host "  REPARO DO BANCO - Sistema Exodo"
Write-Host "============================================"
Write-Host "AppDir: $AppDir"

if (-not (Test-Path $psql)) {
    Write-Host "ERRO: psql nao encontrado em: $pgBin"
    Write-Host "      O PostgreSQL nao esta instalado corretamente."
    exit 1
}

# Ler do .env se existir (respeita valores customizados)
$envFile = Join-Path $AppDir ".env"
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
    if ($envContent) {
        $m = [regex]::Match($envContent, '(?m)^DB_HOST\s*=\s*(.+)$')
        if ($m.Success) { $DbHost = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($envContent, '(?m)^DB_PORT\s*=\s*(.+)$')
        if ($m.Success) { $DbPort = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($envContent, '(?m)^DB_USER\s*=\s*(.+)$')
        if ($m.Success) { $DbUser = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($envContent, '(?m)^DB_PASSWORD\s*=\s*(.+)$')
        if ($m.Success) { $DbPassword = $m.Groups[1].Value.Trim() }
        $m = [regex]::Match($envContent, '(?m)^DB_NAME\s*=\s*(.+)$')
        if ($m.Success) { $DbName = $m.Groups[1].Value.Trim() }
        Write-Host "Configuracao lida do .env"
    }
}

$env:PGPASSWORD = $DbPassword

Write-Host "Host: $DbHost  Porta: $DbPort  Banco: $DbName  Usuario: $DbUser"

# 1. Verificar se o PostgreSQL esta respondendo
Write-Host ""
Write-Host "1/4 Verificando se o PostgreSQL esta rodando..."
$conectou = $false
for ($i = 1; $i -le 10; $i++) {
    & $psql -U $DbUser -d postgres -h $DbHost -p $DbPort -t -c "SELECT 1" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $conectou = $true; break }
    Write-Host "   Aguardando PostgreSQL iniciar... ($i/10)"
    Start-Sleep -Seconds 3
}
if (-not $conectou) {
    Write-Host "ERRO: PostgreSQL nao esta respondendo na porta $DbPort."
    Write-Host "      Tente iniciar por: scripts\iniciar_postgres.bat"
    exit 1
}
Write-Host "   PostgreSQL OK!"

# 2. Criar o banco se nao existir
Write-Host ""
Write-Host "2/4 Verificando se o banco '$DbName' existe..."
$dbExists = (& $psql -U $DbUser -d postgres -h $DbHost -p $DbPort -t -A -c "SELECT 1 FROM pg_database WHERE datname='$DbName'" 2>&1) -join ""
if ($dbExists.Trim() -eq "1") {
    Write-Host "   Banco '$DbName' ja existe."
} else {
    Write-Host "   Banco '$DbName' NAO existe. Criando..."
    & $psql -U $DbUser -d postgres -h $DbHost -p $DbPort -c "CREATE DATABASE $DbName OWNER $DbUser;" 2>&1
    $createExit = $LASTEXITCODE
    if ($createExit -eq 0) {
        Write-Host "   Banco '$DbName' criado com sucesso!"
    } else {
        Write-Host "ERRO: nao foi possivel criar o banco '$DbName'."
        exit 1
    }
}

# 3. Executar init_db.sql (cria as tabelas se nao existirem - idempotente)
Write-Host ""
Write-Host "3/4 Executando init_db.sql (cria tabelas se faltarem)..."
$sqlFile = Join-Path $ScriptDir "init_db.sql"
if (-not (Test-Path $sqlFile)) {
    Write-Host "ERRO: init_db.sql nao encontrado em: $sqlFile"
    exit 1
}
& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -f $sqlFile 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   init_db.sql executado com sucesso!"
} else {
    Write-Host "ERRO ao executar init_db.sql (exit $LASTEXITCODE)"
    exit 1
}

# 3b. Migrar schema (uuid->text) para sincronizar com a nuvem (idempotente)
Write-Host ""
Write-Host "Executando migracao de schema (uuid->text)..."
$migrarScript = Join-Path $ScriptDir "migrar_schema.ps1"
if (Test-Path $migrarScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $migrarScript -DbHost $DbHost -DbPort $DbPort -DbUser $DbUser -DbPassword $DbPassword -DbName $DbName 2>&1
} else {
    Write-Host "AVISO: migrar_schema.ps1 nao encontrado"
}

# 4. Confirmar as tabelas
Write-Host ""
Write-Host "4/4 Verificando tabelas criadas..."
$tableCount = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>&1) -join " ").Trim()
Write-Host "   Tabelas encontradas no banco '$DbName': $tableCount"

Write-Host ""
Write-Host "============================================"
Write-Host "  REPARO CONCLUIDO!"
Write-Host "============================================"
Write-Host "  Banco:  $DbName"
Write-Host "  Tabelas: $tableCount"
Write-Host "  Pode abrir o Sistema Exodo normalmente."
Write-Host "============================================"

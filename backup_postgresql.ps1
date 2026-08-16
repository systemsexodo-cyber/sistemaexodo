<#
.SYNOPSIS
    Script de Backup Automatico do PostgreSQL Local - Sistema Exodo
.DESCRIPTION
    Realiza backup completo do banco PostgreSQL usando pg_dump.
    Mantem backups diarios por 30 dias e backups semanais por 6 meses.
.PARAMETER Modo
    "completo" - Backup de todas as tabelas (padrao)
    "rapido"   - Backup apenas dos dados (sem indices, sem owners)
.PARAMETER DiretorioBackup
    Diretorio onde os backups serao salvos (opcional)
.EXAMPLE
    .\backup_postgresql.ps1 -Modo "rapido"
    .\backup_postgresql.ps1 -DiretorioBackup "D:\Backups\Exodo"
.NOTES
    Autor: Sistema Exodo
    Versao: 1.1.0
#>

param(
    [ValidateSet("completo", "rapido")]
    [string]$Modo = "completo",
    [string]$DiretorioBackup = ""
)

# ============================================================
# CONFIGURACOES
# ============================================================
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Localizar PostgreSQL automaticamente ---
$PgDump = $null
$Psql = $null
$CandidatosPgBin = @(
    (Join-Path $ProjectRoot "postgresql\pgsql\bin"),
    (Join-Path $ProjectRoot "postgresql\bin"),
    "C:\SistemaExodo\postgresql\bin",
    (Join-Path $ProjectRoot "..\postgresql\bin")
)
foreach ($cand in $CandidatosPgBin) {
    $pgDumpTmp = Join-Path $cand "pg_dump.exe"
    $psqlTmp   = Join-Path $cand "psql.exe"
    if ((Test-Path $pgDumpTmp) -and (Test-Path $psqlTmp)) {
        $PgDump = $pgDumpTmp
        $Psql   = $psqlTmp
        break
    }
}
if (-not $PgDump) {
    $PgDump = (Get-Command pg_dump.exe -ErrorAction SilentlyContinue).Source
    $Psql   = (Get-Command psql.exe -ErrorAction SilentlyContinue).Source
}

# --- Configuracoes do Banco (lidas do .env) ---
$DbHost = "localhost"
$DbPort = 5432
$DbName = "exodo_db"
$DbUser = "exodo_user"
$DbPass = "ex@#$"
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

# Configuracoes de Retencao
$DiasManterDiario = 30
$DiasManterSemanal = 180

# ============================================================
# FUNCOES
# ============================================================
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    $logFile = Join-Path $diretorioBackup "backup_log.txt"
    Add-Content -Path $logFile -Value $logMessage
}

function Test-Requirements {
    if (-not (Test-Path $PgDump)) {
        Write-Host "ERRO: pg_dump.exe nao encontrado em: $PgDump" -ForegroundColor Red
        return $false
    }
    try {
        $env:PGPASSWORD = $DbPass
        $test = & $Psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -c "SELECT 1" -t -q 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERRO: PostgreSQL nao esta acessivel em $DbHost`:$DbPort" -ForegroundColor Red
            Write-Host "   Detalhe: $test" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "ERRO: Nao foi possivel conectar ao PostgreSQL: $_" -ForegroundColor Red
        return $false
    }
    return $true
}

function Get-DiretorioBackup {
    if ($DiretorioBackup -ne "") {
        $dir = $DiretorioBackup
    } else {
        $dir = Join-Path $ProjectRoot "backups_postgresql"
    }
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function New-Backup {
    param([string]$Diretorio)

    $data = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $diaSemana = (Get-Date).DayOfWeek

    if ($diaSemana -eq "Sunday") {
        $nomeArquivo = "exodo_backup_SEMANAL_$(Get-Date -Format 'yyyy-MM-dd').dump"
    } else {
        $nomeArquivo = "exodo_backup_$data.dump"
    }

    $arquivoDump = Join-Path $Diretorio $nomeArquivo
    $arquivoLog = Join-Path $Diretorio "backup_info.json"

    Write-Log "Iniciando backup ($Modo)..."
    Write-Log "   Banco: $DbName em $DbHost`:$DbPort"
    Write-Log "   Arquivo: $nomeArquivo"

    $env:PGPASSWORD = $DbPass

    if ($Modo -eq "completo") {
        $argumentos = @(
            "-h", $DbHost,
            "-p", $DbPort,
            "-U", $DbUser,
            "-d", $DbName,
            "--format=custom",
            "--verbose",
            "--no-owner",
            "--compress=9",
            "--file", $arquivoDump
        )
    } else {
        $argumentos = @(
            "-h", $DbHost,
            "-p", $DbPort,
            "-U", $DbUser,
            "-d", $DbName,
            "--data-only",
            "--format=custom",
            "--verbose",
            "--no-owner",
            "--compress=9",
            "--file", $arquivoDump
        )
    }

    Write-Log "   Executando pg_dump..."

    try {
        $resultado = & $PgDump $argumentos 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Log "ERRO: pg_dump falhou (codigo: $exitCode)"
            foreach ($line in $resultado) { Write-Log "   $line" }
            return $false
        }

        if (Test-Path $arquivoDump) {
            $tamanho = (Get-Item $arquivoDump).Length / 1MB
            Write-Log "Backup concluido! Tamanho: $([math]::Round($tamanho, 2)) MB"
        } else {
            Write-Log "ERRO: arquivo de backup nao encontrado."
            return $false
        }

        $infoBackup = @{
            "data" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "banco" = $DbName
            "host" = $DbHost
            "modo" = $Modo
            "arquivo" = $nomeArquivo
            "tamanho_mb" = [math]::Round(((Get-Item $arquivoDump).Length / 1MB), 2)
            "sucesso" = $true
        }
        $infoJson = Get-Content $arquivoLog -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $infoJson) { $infoJson = @() }
        elseif ($infoJson -isnot [System.Array]) { $infoJson = @($infoJson) }
        if (-not $infoJson) { $infoJson = @() }
        $infoJson += $infoBackup
        $infoJson | ConvertTo-Json | Set-Content $arquivoLog

        return $true

    } catch {
        Write-Log "ERRO CRITICO: $_"
        return $false
    }
}
function Remove-ObsoleteBackups {
    param([string]$Diretorio)

    Write-Log "Limpando backups antigos..."
    $agora = Get-Date

    Get-ChildItem -Path $Diretorio -Filter "exodo_backup_*.dump" -File | Where-Object {
        $_.Name -notmatch "SEMANAL" -and $agora.Subtract($_.LastWriteTime).Days -gt $DiasManterDiario
    } | ForEach-Object {
        Write-Log "   Removendo backup diario antigo: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

    Get-ChildItem -Path $Diretorio -Filter "exodo_backup_SEMANAL_*.dump" -File | Where-Object {
        $agora.Subtract($_.LastWriteTime).Days -gt $DiasManterSemanal
    } | ForEach-Object {
        Write-Log "   Removendo backup semanal antigo: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

    Write-Log "Limpeza concluida."
}

function Test-BackupIntegrity {
    param([string]$Diretorio)
    $ultimoBackup = Get-ChildItem -Path $Diretorio -Filter "exodo_backup_*.dump" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $ultimoBackup) {
        Write-Log "Nenhum backup .dump encontrado para verificar integridade."
        return
    }
    Write-Log "Verificando integridade do ultimo backup: $($ultimoBackup.Name)"
    $env:PGPASSWORD = $DbPass
    $pgRestore = Join-Path (Split-Path $PgDump -Parent) "pg_restore.exe"
    if (-not (Test-Path $pgRestore)) { $pgRestore = (Get-Command pg_restore.exe -ErrorAction SilentlyContinue).Source }
    if (-not $pgRestore) { Write-Log "pg_restore nao encontrado - pulando verificacao."; return }
    $lista = & $pgRestore -l $ultimoBackup.FullName 2>&1
    if ($LASTEXITCODE -eq 0 -and ($lista | Select-String "TABLE DATA").Count -gt 0) {
        Write-Log ("Integridade verificada com sucesso: " + $ultimoBackup.Name)
    } else {
        Write-Log "Problema detectado na integridade do backup."
    }
}

# ============================================================
# EXECUCAO PRINCIPAL
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  BACKUP - SISTEMA EXODO (PostgreSQL Local)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verificar requisitos
if (-not (Test-Requirements)) {
    exit 1
}

# Obter diretorio de backup
$diretorioBackup = Get-DiretorioBackup
Write-Log "Diretorio de backup: $diretorioBackup"

# Executar backup
$sucesso = New-Backup -Diretorio $diretorioBackup

if ($sucesso) {
    # Limpar backups antigos
    Remove-ObsoleteBackups -Diretorio $diretorioBackup

    # Verificar integridade
    Test-BackupIntegrity -Diretorio $diretorioBackup

    Write-Log "Backup concluido com sucesso!"

    $totalBackups = (Get-ChildItem -Path $diretorioBackup -Filter "exodo_backup_*" -File).Count
    $tamanhoTotal = [math]::Round(((Get-ChildItem -Path $diretorioBackup -Filter "exodo_backup_*" -File | Measure-Object Length -Sum).Sum / 1MB), 2)
    Write-Log "Total de backups: $totalBackups | Espaco total: $tamanhoTotal MB"

    exit 0
} else {
    Write-Log "Backup FALHOU!"
    exit 1
}

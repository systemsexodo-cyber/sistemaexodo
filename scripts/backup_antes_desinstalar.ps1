# ============================================================
# BACKUP ANTES DE DESINSTALAR - SISTEMA EXODO
# ------------------------------------------------------------
# O desinstalador apaga {app}\pgdata (o cluster PostgreSQL), {app}\data e os
# logs, e tambem o .env (senha do banco / chaves da nuvem). Sem uma copia, os
# dados da loja vao embora junto com a desinstalacao.
#
# Este script roda ANTES dessa remocao (InitializeUninstall no instalador),
# gera um dump no formato custom (restauravel com pg_restore ou com o
# RESTAURAR_BACKUP.ps1) numa pasta FORA da pasta do sistema e confirma que o
# arquivo existe e nao esta vazio.
#
# USO MANUAL:
#   powershell -ExecutionPolicy Bypass -File scripts\backup_antes_desinstalar.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\backup_antes_desinstalar.ps1 `
#       -AppDir "C:\SistemaExodo" -Destino "D:\Backups Exodo"
#
# CODIGOS DE SAIDA:
#   0 = backup gerado (ou nao havia banco para copiar)
#   1 = falha (nada foi copiado / arquivo vazio) -> o instalador avisa
# ============================================================

param(
    [string]$AppDir = "",
    [string]$Destino = ""
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $linha = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $linha
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $linha -Encoding UTF8 } catch { }
    }
}

function Sair-ComErro {
    param([string]$Mensagem, [int]$Codigo = 1)
    Write-Log "ERRO: $Mensagem"
    exit $Codigo
}

# --- Pasta do sistema ------------------------------------------------------
if (-not $AppDir) { $AppDir = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path $AppDir)) { Sair-ComErro "pasta do sistema nao encontrada: $AppDir" 1 }

# --- Pasta de destino (NUNCA dentro de {app}: ela sera apagada) -------------
if (-not $Destino) {
    $docs = [Environment]::GetFolderPath("CommonDocuments")
    if ([string]::IsNullOrWhiteSpace($docs)) { $docs = "C:\" }
    $Destino = Join-Path $docs "Sistema Exodo Backups"
}

try {
    if (-not (Test-Path $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
} catch {
    Sair-ComErro "nao foi possivel criar a pasta de backup '$Destino': $($_.Exception.Message)" 1
}

$appFull = [System.IO.Path]::GetFullPath($AppDir).TrimEnd('\')
$destFull = [System.IO.Path]::GetFullPath($Destino).TrimEnd('\')
if ($destFull.StartsWith($appFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Sair-ComErro "destino '$destFull' esta dentro da pasta do sistema '$appFull', que sera apagada. Use uma pasta fora dela." 1
}

$script:LogFile = Join-Path $Destino "backup_desinstalacao.log"
Write-Log "=== Backup antes de desinstalar ==="
Write-Log "Pasta do sistema: $appFull"
Write-Log "Destino: $destFull"

# --- Binarios do PostgreSQL ------------------------------------------------
$pgBin = Join-Path $AppDir "postgresql\bin"
$PgDump = Join-Path $pgBin "pg_dump.exe"
$Psql = Join-Path $pgBin "psql.exe"
$PgCtl = Join-Path $pgBin "pg_ctl.exe"

if (-not (Test-Path $PgDump)) {
    $cmdDump = Get-Command pg_dump.exe -ErrorAction SilentlyContinue
    $cmdPsql = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmdDump) { $PgDump = $cmdDump.Source }
    if ($cmdPsql) { $Psql = $cmdPsql.Source }
}
if (-not (Test-Path $PgDump)) {
    Sair-ComErro "pg_dump.exe nao encontrado em '$pgBin' (nem no PATH). Nada foi copiado." 1
}

# --- Credenciais (do .env, que o app usa) ----------------------------------
$DbHost = "localhost"
$DbPort = "5432"
$DbName = "exodo_db"
$DbUser = "exodo_user"
$DbPass = ""
$envFile = Join-Path $AppDir ".env"
if (Test-Path $envFile) {
    foreach ($linha in (Get-Content $envFile -ErrorAction SilentlyContinue)) {
        if     ($linha -match '^\s*DB_HOST\s*=\s*(.+)\s*$')     { $DbHost = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_PORT\s*=\s*(.+)\s*$')     { $DbPort = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_NAME\s*=\s*(.+)\s*$')     { $DbName = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_USER\s*=\s*(.+)\s*$')     { $DbUser = $Matches[1].Trim() }
        elseif ($linha -match '^\s*DB_PASSWORD\s*=\s*(.+)\s*$') { $DbPass = $Matches[1].Trim() }
    }
} else {
    Write-Log "AVISO: .env nao encontrado em $appFull - usando os valores padrao do banco."
}

# --- Garantir que o servidor esta respondendo ------------------------------
function Testar-Conexao {
    if (-not (Test-Path $Psql)) { return $false }
    $env:PGPASSWORD = $DbPass
    & $Psql -h $DbHost -p $DbPort -U $DbUser -d postgres -t -A -c "SELECT 1" 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

if (-not (Testar-Conexao)) {
    Write-Log "PostgreSQL nao respondeu; tentando iniciar o servico PostgreSQL_Exodo..."
    & sc.exe start "PostgreSQL_Exodo" 2>&1 | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 2
        if (Testar-Conexao) { break }
    }
}

if (-not (Testar-Conexao) -and (Test-Path $PgCtl)) {
    $dataDir = Join-Path $AppDir "pgdata"
    if (Test-Path (Join-Path $dataDir "postgresql.conf")) {
        Write-Log "Servico nao subiu; tentando pg_ctl direto em '$dataDir'..."
        $logDir = Join-Path $AppDir "logs"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        & $PgCtl -D $dataDir -l (Join-Path $logDir "pg_desinstalar.log") start -w -t 30 2>&1 | Out-Null
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Seconds 2
            if (Testar-Conexao) { break }
        }
    }
}

if (-not (Testar-Conexao)) {
    Sair-ComErro "nao foi possivel conectar ao PostgreSQL em ${DbHost}:${DbPort}. Nada foi copiado." 1
}

# --- O banco existe nesta instalacao? --------------------------------------
$env:PGPASSWORD = $DbPass
$existe = ((& $Psql -h $DbHost -p $DbPort -U $DbUser -d postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname='$DbName'" 2>&1) -join " ").Trim()
if ($existe -ne "1") {
    Write-Log "Banco '$DbName' nao existe nesta instalacao - nao ha dados para copiar."
    exit 0
}

# --- pg_dump ---------------------------------------------------------------
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$arquivo = Join-Path $Destino ("exodo_backup_antes_desinstalar_{0}.dump" -f $stamp)
Write-Log "Gerando backup do banco '$DbName' em: $arquivo"

$saida = & $PgDump -h $DbHost -p $DbPort -U $DbUser -d $DbName --format=custom --no-owner --compress=9 --file $arquivo 2>&1
$codigo = $LASTEXITCODE

if ($codigo -ne 0) {
    Sair-ComErro ("pg_dump falhou (codigo {0}): {1}" -f $codigo, (($saida | Out-String).Trim())) 1
}
if (-not (Test-Path $arquivo)) {
    Sair-ComErro "pg_dump terminou sem erro mas o arquivo nao foi criado: $arquivo" 1
}
$tamanho = (Get-Item $arquivo).Length
if ($tamanho -le 0) {
    Sair-ComErro "o backup gerado esta vazio: $arquivo" 1
}

Write-Log ("Backup concluido: {0} ({1:N2} MB)" -f $arquivo, ($tamanho / 1MB))
Write-Log "Para restaurar depois de reinstalar: RESTAURAR_BACKUP.ps1 `"$arquivo`""
exit 0

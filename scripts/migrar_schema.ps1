# ============================================================================
# MIGRAR SCHEMA - SISTEMA EXODO
# ============================================================================
# Corrige o schema do banco local para ficar IGUAL ao de referencia (dev/cloud):
#   1. Remove tabelas fantasma (itens_pedido, pagamentos, app_update_config)
#      que NAO existem na nuvem (causavam spam de HTTP 404 a cada ciclo).
#   2. Remove todas as constraints de chave estrangeira (o banco de
#      referencia NAO tem FKs - causa de falhas de download em ordem errada).
#   3. Converte colunas uuid -> text (a nuvem usa ids TEXT como
#      '1776036401244'/'1'/'produto-diversos-9999').
#   4. Executa o init_db.sql (adiciona tabelas/triggers/indices faltantes).
# Pode rodar quantas vezes quiser (e IDEMPOTENTE - nao faz nada se ja migrado).
# IMPORTANTE: somente caracteres ASCII aqui (PS 5.1 le como ANSI).
# ============================================================================

param(
    [string]$DbHost = "localhost",
    [string]$DbPort = "5432",
    [string]$DbUser = "exodo_user",
    [string]$DbPassword = "ex@#$",
    [string]$DbName = "exodo_db"
)

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Split-Path $ScriptDir -Parent
$pgBin = Join-Path $AppDir "postgresql\bin"
$psql = Join-Path $pgBin "psql.exe"

Write-Host "============================================"
Write-Host "  MIGRACAO DE SCHEMA - Sistema Exodo"
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
Write-Host "1/5 Verificando se o PostgreSQL esta rodando..."
$conectou = $false
for ($i = 1; $i -le 10; $i++) {
    & $psql -U $DbUser -d postgres -h $DbHost -p $DbPort -t -c "SELECT 1" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $conectou = $true; break }
    Write-Host "   Aguardando PostgreSQL iniciar... ($i/10)"
    Start-Sleep -Seconds 3
}
if (-not $conectou) {
    Write-Host "ERRO: PostgreSQL nao esta respondendo na porta $DbPort."
    exit 1
}
Write-Host "   PostgreSQL OK!"

# 2. Remover tabelas fantasma (nao existem na nuvem -> causam 404 no sync)
Write-Host ""
Write-Host "2/5 Removendo tabelas fantasma (se existirem)..."
foreach ($t in @('itens_pedido', 'pagamentos', 'app_update_config')) {
    $existe = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='$t'" 2>&1) -join "").Trim()
    if ($existe -eq "1") {
        & $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "DROP TABLE IF EXISTS public.$t" 2>&1
        Write-Host "   Tabela '$t' removida (nao existia na nuvem)."
    } else {
        Write-Host "   Tabela '$t' nao existia - OK."
    }
}

# 3. Remover todas as constraints de chave estrangeira (banco de referencia nao tem FKs)
Write-Host ""
Write-Host "3/5 Removendo constraints de chave estrangeira..."
$fkRows = @(& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT conrelid::regclass::text || '|' || conname FROM pg_constraint WHERE contype='f' AND connamespace='public'::regnamespace" 2>&1)
$fkCount = 0
foreach ($fk in $fkRows) {
    $fk = $fk.Trim()
    if (-not $fk) { continue }
    $parts = $fk.Split('|')
    if ($parts.Count -ge 2) {
        $tbl = $parts[0]
        $con = $parts[1]
        & $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "ALTER TABLE $tbl DROP CONSTRAINT IF EXISTS $con" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $fkCount++ }
    }
}
Write-Host "   FKs removidas: $fkCount"

# 4. Converter colunas uuid -> text (exceto sync_logs.id que permanece uuid no banco de referencia)
Write-Host ""
Write-Host "4/5 Convertendo colunas uuid para text..."
$uuidRows = @(& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT table_name || '|' || column_name FROM information_schema.columns WHERE data_type='uuid' AND table_schema='public' AND NOT (table_name='sync_logs' AND column_name='id')" 2>&1)
$convCount = 0
foreach ($row in $uuidRows) {
    $row = $row.Trim()
    if (-not $row) { continue }
    $parts = $row.Split('|')
    if ($parts.Count -ge 2) {
        $tbl = $parts[0]
        $col = $parts[1]
        & $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "ALTER TABLE public.`"$tbl`" ALTER COLUMN `"$col`" DROP DEFAULT" 2>&1 | Out-Null
        & $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "ALTER TABLE public.`"$tbl`" ALTER COLUMN `"$col`" TYPE text USING `"$col`"::text" 2>&1
        if ($LASTEXITCODE -eq 0) { $convCount++; Write-Host "   $tbl.$col -> text" }
    }
}
Write-Host "   Colunas convertidas: $convCount"

# 5b. RESETAR o controle de sincronizacao (_sync_controle) E a fila outbox
# (_exodo_sync_log).
# - _sync_controle: o sincronizador ANTIGO (quebrado) avancou os timestamps por
#   tabela mesmo com os downloads falhando (uuid). Sem este reset, o primeiro
#   sync apos a migracao consultaria updated_at >= timestamp salvo e PULARIA
#   todo o historico antigo. A tabela e recriada vazia pelo sincronizador no
#   proximo ciclo, forcando o re-download completo.
# - _exodo_sync_log: se a maquina quebrada tiver essa fila com id uuid, a
#   conversao acima a deixaria como text, e o CREATE TABLE IF NOT EXISTS do
#   init_db.sql seria ignorado (tabela ja existe) - deixando schema divergente
#   e quebrando o DELETE ... WHERE id = ANY(inteiros) do sincronizador.
#   Dropa-la garante que o init_db.sql recria com id integer + sequence
#   (schema de referencia). DROP IF EXISTS e idempotente.
Write-Host ""
Write-Host "5b/5 Resetando controle de sincronizacao e fila outbox (forca re-download)..."
# Aviso: se houver alteracoes locais que nunca subiram para a nuvem, elas serao
# descartadas (o re-download completo sobrescreve tudo com o estado da nuvem).
$pendentes = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT count(*) FROM public._exodo_sync_log" 2>&1) -join " ").Trim()
if ($pendentes -match '^[0-9]+$' -and [int]$pendentes -gt 0) {
    Write-Host "   ATENCAO: $pendentes evento(s) de sincronizacao pendente(s) serao descartados."
    Write-Host "   Se existiam alteracoes locais que nao subiram (precos, vendas, cadastros),"
    Write-Host "   confira-as antes de continuar - o banco sera sobrescrito pela nuvem."
}
& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "DROP TABLE IF EXISTS public._sync_controle" 2>&1 | Out-Null
& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -c "DROP TABLE IF EXISTS public._exodo_sync_log" 2>&1 | Out-Null
Write-Host "   _sync_controle e _exodo_sync_log limpos - o primeiro sync vai baixar todo o historico."

# 5. Executar init_db.sql (adiciona tabelas/triggers/indices/views faltantes - idempotente)
Write-Host ""
Write-Host "5/5 Executando init_db.sql (objetos faltantes)..."
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

# Resumo final
$tableCount = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>&1) -join " ").Trim()
$uuidRest = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT count(*) FROM information_schema.columns WHERE data_type='uuid' AND table_schema='public'" 2>&1) -join " ").Trim()
$triggers = ((& $psql -U $DbUser -d $DbName -h $DbHost -p $DbPort -t -A -c "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace)" 2>&1) -join " ").Trim()

Write-Host ""
Write-Host "============================================"
Write-Host "  MIGRACAO CONCLUIDA!"
Write-Host "============================================"
Write-Host "  Tabelas: $tableCount"
Write-Host "  Colunas uuid restantes: $uuidRest (esperado: 1 - sync_logs)"
Write-Host "  Triggers outbox: $triggers"
Write-Host "  O sincronizador agora vai baixar os dados da nuvem."
Write-Host "============================================"

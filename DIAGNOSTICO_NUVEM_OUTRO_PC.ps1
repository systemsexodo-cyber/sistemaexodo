# ============================================================================
#  DIAGNOSTICO_NUVEM_OUTRO_PC.ps1
#
#  Rode NO PC QUE ESTA COM PROBLEMA (botao direito > Executar com o PowerShell,
#  ou cole num .bat:  powershell -ExecutionPolicy Bypass -File DIAGNOSTICO_NUVEM_OUTRO_PC.ps1)
#
#  Ele apenas LE e TESTA - nao altera nada.
# ============================================================================

$ErrorActionPreference = "SilentlyContinue"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DIAGNOSTICO DE CONEXAO COM A NUVEM - PC: $env:COMPUTERNAME"
Write-Host " Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "========================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. .env --
$envFiles = @(
    "C:\SistemaExodo\.env",
    "$env:USERPROFILE\.antigravity\sistema_exodo_15-04-2026\.env",
    ".\.env"
) | Where-Object { Test-Path $_ }

if (-not $envFiles) {
    Write-Host "[ERRO] Nenhum .env encontrado (C:\SistemaExodo\.env, etc)." -ForegroundColor Red
}

foreach ($f in $envFiles) {
    Write-Host "`n--- $f ---" -ForegroundColor Yellow
    Select-String -Path $f -Pattern "^(NUVEM_PROVEDOR|SUPABASE_URL|SUPABASE_FUNCTIONS_URL|NEON_DATA_API_URL|PAR_HOST|LAN_SYNC)=" |
        ForEach-Object {
            $p = $_.Line -split '=', 2
            "$($p[0]) = $($p[1])"
        }
    # chave: mostra so os 20 primeiros caracteres
    Select-String -Path $f -Pattern "^(SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY|NEON_DATA_API_KEY)=" |
        ForEach-Object {
            $p = $_.Line -split '=', 2
            $v = $p[1]
            $vis = if ($v.Length -gt 24) { $v.Substring(0, 24) + "... (" + $v.Length + " chars)" } else { $v }
            "$($p[0]) = $vis"
        }
}

# --------------------------------------------------- 2. dominios mortos? ----
Write-Host "`n=== 2. RESOLUCAO DNS (NXDOMAIN = dominio morto) ===" -ForegroundColor Cyan
$hosts = @(
    "febffvlpvxtiihvnfuts.supabase.co",
    "exodosystems.tail9b4943.ts.net",
    "servidorsupabase.tail9b4943.ts.net",
    "desktop-86ut1r1.tail9b4943.ts.net"
)
foreach ($h in $hosts) {
    try {
        $ip = (Resolve-DnsName $h -Type A -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
        Write-Host ("  [OK]    {0} -> {1}" -f $h, $ip) -ForegroundColor Green
    } catch {
        Write-Host ("  [MORTO] {0} -> NXDOMAIN" -f $h) -ForegroundColor Red
    }
}

# ------------------------------------------------- 3. testa a nuvem real ----
Write-Host "`n=== 3. TESTE DIRETO NA NUVEM (funnel publico) ===" -ForegroundColor Cyan
$envCfg = Get-Content "C:\SistemaExodo\.env" -ErrorAction SilentlyContinue
if (-not $envCfg) { $envCfg = Get-Content ".\.env" -ErrorAction SilentlyContinue }
$key = ""
$url = "https://exodosystems.tail9b4943.ts.net"
if ($envCfg) {
    $k = ($envCfg | Where-Object { $_ -match "^SUPABASE_ANON_KEY=" }) -replace "^SUPABASE_ANON_KEY=", ""
    $u = ($envCfg | Where-Object { $_ -match "^SUPABASE_URL=" }) -replace "^SUPABASE_URL=", ""
    if ($k) { $key = $k }
    if ($u -and $u -match "^https?://(exodosystems|febffvlpvxtiihvnfuts|servidorsupabase|desktop)") { $url = $u }
}
Write-Host "  URL base testada: $url"

try {
    $r = Invoke-WebRequest -Uri "$url/rest/v1/empresas?select=id&limit=1" `
        -Headers @{ apikey = $key; Authorization = "Bearer $key" } `
        -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK]  GET /rest/v1/empresas -> HTTP $($r.StatusCode)  (credencial VALIDA)" -ForegroundColor Green
} catch {
    $code = ""
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    if ($code -eq "401" -or $code -eq "403") {
        Write-Host "  [FALHA] HTTP $code - a CHAVE do .env esta ERRADA/expirada (dominio acessivel)" -ForegroundColor Red
        Write-Host "          -> e o mesmo problema encontrado no servidor: chave antiga do projeto" -ForegroundColor Red
        Write-Host "             Supabase morto. Compare com o .env do servidor." -ForegroundColor Red
    } else {
        Write-Host "  [FALHA] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ------------------------------------------- 4. sincronizador / processos ---
Write-Host "`n=== 4. PROCESSOS DO SISTEMA ===" -ForegroundColor Cyan
Get-Process SincronizadorNuvem, ExodoNfceBridge, sistema_exodo_novo -ErrorAction SilentlyContinue |
    ForEach-Object { "  $($_.ProcessName)  PID $($_.Id)  desde $($_.StartTime)" }

$log = "C:\SistemaExodo\sincronizador.log"
if (Test-Path $log) {
    Write-Host "`n=== 5. ULTIMOS ERROS NO LOG ($log) ===" -ForegroundColor Cyan
    Get-Content $log -Tail 3000 |
        Select-String -Pattern "ERRO|falha|401|403|Unauthorized|refused|DNS|nao existe|timed out" |
        Select-Object -Last 8 | ForEach-Object { "  " + $_.Line.Substring(0, [Math]::Min(190, $_.Line.Length)) }
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " FIM - cole a saida no chat para analise."
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para fechar"

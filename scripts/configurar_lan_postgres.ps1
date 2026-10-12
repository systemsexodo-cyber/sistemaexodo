# ============================================================================
# CONFIGURAR O POSTGRESQL PARA A REDE LOCAL - SISTEMA EXODO
# ============================================================================
# Prepara ESTE computador para o outro PC da loja conectar direto no banco
# local (sincronizacao_sem_nuvem / modo LAN):
#   1. listen_addresses = '*' no postgresql.conf (o PostgreSQL passa a ouvir a
#      rede local, nao so o 127.0.0.1);
#   2. libera no pg_hba.conf a REDE LOCAL deste PC (senha obrigatoria) - ou um
#      IP/rede especifica, se voce pedir;
#   3. abre a porta no Firewall do Windows (perfil Privado);
#   4. grava PAR_HOST/PAR_PORT no .env deste PC;
#   5. reinicia o PostgreSQL.
#
# Rode UMA VEZ EM CADA PC, como Administrador. Por padrao NAO precisa informar IP
# nenhum: ele libera a REDE LOCAL inteira (a sub-rede /24 deste PC). Assim uma
# loja com varios caixas nao precisa cruzar IP a IP.
#
#   Liberar a rede toda:   (sem argumento)
#   Liberar so um PC:      -PeerHost 192.168.0.12
#   Liberar uma rede:      -Subnet 192.168.0.0/24
#
# Depois disso, o SincronizadorNuvem de cada PC passa a atualizar os bancos
# tambem pela rede local. Nada aqui toca a nuvem.
#
# IMPORTANTE: somente caracteres ASCII neste arquivo (o PowerShell 5.1 le como
# ANSI e acentos viram lixo).
# ============================================================================

param(
    # IP do OUTRO PC. Opcional: sem ele, este PC libera a REDE LOCAL inteira
    # (a sub-rede /24 deste computador). Esse e o jeito pratico quando a loja
    # tem varios caixas: roda UMA vez em cada PC e todos se enxergam, sem
    # ninguem precisar informar o IP de ninguem.
    [string]$PeerHost = "",
    # Libera exatamente esta rede (ex.: 192.168.0.0/24 ou 10.0.0.0/16). Opcional.
    [string]$Subnet = "",
    [string]$DbPort = "5432",
    [string]$DataDir = "",
    [switch]$NaoReiniciar
)

$ErrorActionPreference = "Stop"

function Falhar($mensagem) {
    Write-Host ""
    Write-Host "ERRO: $mensagem" -ForegroundColor Red
    exit 1
}

function Get-SubredesLocais {
    # Redes /24 deste PC (ex.: 192.168.0.0/24). E daqui que sai a liberacao de
    # todo mundo de uma vez, sem informar o IP de cada maquina.
    $redes = @()
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
        foreach ($i in $ips) {
            $p = $i.IPAddress.Split('.')
            if ($p.Count -eq 4) { $redes += "$($p[0]).$($p[1]).$($p[2]).0/24" }
        }
    } catch { }
    return @($redes | Select-Object -Unique)
}

# --- contexto ---------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir    = Split-Path $ScriptDir -Parent
$envFile   = Join-Path $AppDir ".env"

# --- onde o PostgreSQL REALMENTE esta ---------------------------------------
# Nao da para supor que a instalacao fica dentro da pasta do app. O servico do
# Windows informa o proprio pg_ctl.exe e o -D (pasta de dados). Sem isso o
# script procurava em <AppDir>\data e morria com "postgresql.conf nao
# encontrado" em toda maquina em que o banco foi instalado em outro lugar.
$ServicoPostgres  = $null
$pgCtlDoServico   = $null
$DataDirDoServico = $null
try {
    $ServicoPostgres = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match 'pg_ctl' } | Select-Object -First 1
    if ($ServicoPostgres) {
        $mExe = [regex]::Match($ServicoPostgres.PathName, '^\s*"([^"]+\.exe)"')
        if (-not $mExe.Success) {
            $mExe = [regex]::Match($ServicoPostgres.PathName, '^\s*(\S+\.exe)')
        }
        if ($mExe.Success) { $pgCtlDoServico = $mExe.Groups[1].Value }
        $mDir = [regex]::Match($ServicoPostgres.PathName, '-D\s+"([^"]+)"')
        if (-not $mDir.Success) {
            $mDir = [regex]::Match($ServicoPostgres.PathName, '-D\s+(\S+)')
        }
        if ($mDir.Success) { $DataDirDoServico = $mDir.Groups[1].Value }
    }
} catch { }

# pg_ctl: o do servico manda; senao, o caminho relativo ao app.
if ($pgCtlDoServico -and (Test-Path $pgCtlDoServico)) {
    $pgCtl = $pgCtlDoServico
} else {
    $pgCtl = Join-Path $AppDir "postgresql\bin\pg_ctl.exe"
}
$pgBin = Split-Path $pgCtl -Parent

# Pasta de dados: respeita -DataDir; senao usa a do servico; senao procura.
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $candidatos = @()
    if ($DataDirDoServico) { $candidatos += $DataDirDoServico }
    $candidatos += (Join-Path $AppDir "pgdata")
    $candidatos += (Join-Path $AppDir "data")
    foreach ($cand in $candidatos) {
        if ($cand -and (Test-Path (Join-Path $cand "postgresql.conf"))) {
            $DataDir = $cand
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($DataDir) -and $DataDirDoServico) {
        $DataDir = $DataDirDoServico
    }
}

Write-Host "============================================"
Write-Host "  REDE LOCAL - Configurar PostgreSQL"
Write-Host "============================================"
Write-Host "AppDir  : $AppDir"
Write-Host "DataDir : $DataDir"
Write-Host "Servico : $(if ($ServicoPostgres) { $ServicoPostgres.Name } else { '(nao encontrado)' })"
Write-Host "Par     : $PeerHost"

# --- permissao de administrador --------------------------------------------
$ehAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin) {
    Falhar "este script precisa ser executado como Administrador (botao direito > Executar como administrador)."
}

# --- localizar os arquivos de configuracao ---------------------------------
$confFile = Join-Path $DataDir "postgresql.conf"
$hbaFile  = Join-Path $DataDir "pg_hba.conf"
if (-not (Test-Path $confFile)) { Falhar "postgresql.conf nao encontrado em: $confFile" }
if (-not (Test-Path $hbaFile))  { Falhar "pg_hba.conf nao encontrado em: $hbaFile" }

# Ler do .env se existir (respeita porta customizada)
if (Test-Path $envFile) {
    $conteudo = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
    if ($conteudo) {
        $m = [regex]::Match($conteudo, '(?m)^DB_PORT\s*=\s*(.+)$')
        if ($m.Success) { $DbPort = $m.Groups[1].Value.Trim() }
    }
}

# --- 1. listen_addresses ---------------------------------------------------
Write-Host ""
Write-Host "[1/5] Ajustando listen_addresses no postgresql.conf..."
$conf = Get-Content $confFile -Raw
$confOriginal = $conf
# Aceita qualquer espacamento e comentario opcional na linha.
if ($conf -match "(?m)^\s*#?\s*listen_addresses\s*=") {
    $conf = [regex]::Replace($conf, "(?m)^\s*#?\s*listen_addresses\s*=.*$",
                             "listen_addresses = '*'")
} else {
    $conf = $conf.TrimEnd() + "`r`nlisten_addresses = '*'`r`n"
}
if ($conf -ne $confOriginal) {
    Copy-Item $confFile "$confFile.bak_lan" -Force
    Set-Content -Path $confFile -Value $conf -NoNewline
    Write-Host "      postgresql.conf atualizado (backup: postgresql.conf.bak_lan)"
} else {
    Write-Host "      ja estava correto."
}

# --- 2. pg_hba.conf --------------------------------------------------------
# Quem pode entrar: um IP (-PeerHost), uma rede (-Subnet) ou, por padrao, a
# rede local inteira. Vale sempre a senha do banco (scram-sha-256).
$alvos = @()
if (-not [string]::IsNullOrWhiteSpace($Subnet)) {
    $alvos += $Subnet.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($PeerHost)) {
    if ($PeerHost -match '/') { $alvos += $PeerHost.Trim() }
    else {
        # O pg_hba.conf so aceita ENDERECO (IP ou rede), nunca nome de
        # computador: uma linha "NOME/32" e invalida e derruba o PostgreSQL
        # no proximo restart. Se vier um nome, resolve para o IP de hoje.
        $ehIp = $false
        try { $ehIp = [System.Net.IPAddress]::TryParse($PeerHost.Trim(), [ref]$null) } catch { }
        if (-not $ehIp) {
            try {
                $ipResolvido = [System.Net.Dns]::GetHostAddresses($PeerHost.Trim()) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -First 1
            } catch { }
            if ($ipResolvido) {
                Write-Host "      Nome '$($PeerHost.Trim())' resolvido para $ipResolvido (o pg_hba.conf usa IP)."
                $alvos += "$ipResolvido/32"
            } else {
                Falhar "nao consegui resolver '$($PeerHost.Trim())' para um IP. Informe o IP, ou rode SEM argumento para liberar a rede local inteira (recomendado)."
            }
        } else {
            $alvos += "$($PeerHost.Trim())/32"
        }
    }
} else {
    $alvos += Get-SubredesLocais
    if ($alvos.Count -eq 0) {
        Falhar "nao achei a rede local deste PC. Informe -PeerHost <ip do outro> ou -Subnet <rede>."
    }
}
$modo = if ($alvos.Count -eq 1 -and $alvos[0] -like '*/32') { 'IP unico' } else { 'rede local' }

Write-Host ""
Write-Host "[2/5] Liberando ($modo) no pg_hba.conf: $($alvos -join ', ')"
$hba = Get-Content $hbaFile -Raw
$novas = @()
foreach ($alvo in $alvos) {
    if ($hba -notmatch [regex]::Escape($alvo)) { $novas += $alvo }
}
if ($novas.Count -eq 0) {
    Write-Host "      ja liberado."
} else {
    Copy-Item $hbaFile "$hbaFile.bak_lan" -Force
    $extra = ""
    foreach ($alvo in $novas) {
        $extra += "host    all             all             $alvo            scram-sha-256`r`n"
    }
    # IPv6 tambem: o Windows resolve o nome do PC para fe80::... antes do IPv4,
    # e sem esta linha o outro caixa recebe "nenhuma entrada em pg_hba.conf".
    $extra += "host    all             all             fe80::/10        scram-sha-256`r`n"
    $extra += "host    all             all             ::1/128          scram-sha-256`r`n"
    $hba = $hba.TrimEnd() + "`r`n`r`n# Exodo - sincronizacao LAN (adicionado automaticamente)`r`n$extra"
    Set-Content -Path $hbaFile -Value $hba -NoNewline
    Write-Host "      pg_hba.conf atualizado: $($novas -join ', ') (backup: pg_hba.conf.bak_lan)"
}

# --- 3. Firewall -----------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Abrindo a porta $DbPort no Firewall (perfil Privado)..."
$regra = "Exodo PostgreSQL (LAN)"
try {
    # Recriar (em vez de pular se ja existe) garante porta E perfis certos. A
    # regra antiga valia so para o perfil Privado: como o Windows costuma
    # classificar a rede da loja como PUBLICA, ela simplesmente nao valia e o
    # outro PC continuava sem conectar.
    Remove-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $regra -Direction Inbound -Protocol TCP `
        -LocalPort $DbPort -Action Allow -Profile Any | Out-Null
    Write-Host "      regra '$regra' criada para TODOS os perfis de rede."
} catch {
    Write-Host "      AVISO: nao consegui criar a regra ($($_.Exception.Message))." -ForegroundColor Yellow
    Write-Host "      Libere a porta $DbPort manualmente, senao o outro PC nao conecta."
}

# --- 4. .env ---------------------------------------------------------------
Write-Host ""
$umParSo = (-not [string]::IsNullOrWhiteSpace($PeerHost)) -and ($PeerHost -notmatch '/')
if (-not $umParSo) {
    Write-Host "[4/5] Liberando a rede inteira: PAR_HOST nao muda aqui (quem escolhe o OUTRO PC e a tela Rede LAN do sistema)."
} elseif (-not (Test-Path $envFile)) {
    Write-Host "[4/5] AVISO: .env nao encontrado em $envFile - preencha PAR_HOST manualmente." -ForegroundColor Yellow
} else {
    Write-Host "[4/5] Gravando PAR_HOST/PAR_PORT no .env deste PC..."
    $envTxt = Get-Content $envFile -Raw
    $alterou = $false

    $envTxt = [regex]::Replace($envTxt, "(?m)^\s*PAR_HOST\s*=.*$", "PAR_HOST=$PeerHost", 1)
    if ($envTxt -notmatch "(?m)^\s*PAR_HOST\s*=") {
        $envTxt = $envTxt.TrimEnd() + "`r`nPAR_HOST=$PeerHost`r`n"
        $alterou = $true
    }
    $envTxt = [regex]::Replace($envTxt, "(?m)^\s*PAR_PORT\s*=.*$", "PAR_PORT=$DbPort", 1)
    if ($envTxt -notmatch "(?m)^\s*PAR_PORT\s*=") {
        $envTxt = $envTxt.TrimEnd() + "`r`nPAR_PORT=$DbPort`r`n"
        $alterou = $true
    }

    Copy-Item $envFile "$envFile.bak_lan" -Force
    Set-Content -Path $envFile -Value $envTxt -NoNewline
    Write-Host "      .env atualizado: PAR_HOST=$PeerHost PAR_PORT=$DbPort (backup: .env.bak_lan)"
}

# --- 5. Reiniciar ----------------------------------------------------------
Write-Host ""
if ($NaoReiniciar) {
    Write-Host "[5/5] Reinicio ignorado (-NaoReiniciar). O outro PC so conecta depois de reiniciar o PostgreSQL."
} else {
    Write-Host "[5/5] Reiniciando o PostgreSQL..."
    $reiniciou = $false
    # Preferir o SERVICO do Windows: e o mecanismo nativo e nao depende de
    # acertar a pasta de dados.
    $nomeServico = $null
    if ($ServicoPostgres) {
        $nomeServico = $ServicoPostgres.Name
    } else {
        $s = Get-Service | Where-Object { $_.Name -like "*postgres*" } | Select-Object -First 1
        if ($s) { $nomeServico = $s.Name }
    }
    if ($nomeServico) {
        try {
            Restart-Service -Name $nomeServico -Force -ErrorAction Stop
            $reiniciou = $true
        } catch {
            Write-Host "      AVISO: falha ao reiniciar o servico $nomeServico ($($_.Exception.Message))."
        }
    }
    if (-not $reiniciou -and (Test-Path $pgCtl)) {
        $logDir = Join-Path $AppDir "logs"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $log = Join-Path $logDir "postgresql.log"
        & $pgCtl -D $DataDir -l $log restart -w -t 30 | Out-Null
        $reiniciou = ($LASTEXITCODE -eq 0)
    }
    if ($reiniciou) {
        Write-Host "      PostgreSQL reiniciado." -ForegroundColor Green
    } else {
        Write-Host "      AVISO: nao consegui reiniciar automaticamente. Reinicie o servico PostgreSQL na mao." -ForegroundColor Yellow
    }
}

# --- resumo ----------------------------------------------------------------
Write-Host ""
Write-Host "============================================"
Write-Host "  PRONTO NESTE PC" -ForegroundColor Green
Write-Host "============================================"
if ($umParSo) {
    Write-Host "Agora RODE ESTE MESMO SCRIPT NO OUTRO computador (apontando para DESTE)"
    Write-Host "ou, se a loja tem varios caixas, rode sem informar IP: assim cada PC"
    Write-Host "libera a rede inteira e ninguem precisa decorar endereco."
} else {
    Write-Host "Rode ESTE MESMO SCRIPT em CADA computador da loja (nao precisa informar"
    Write-Host "o IP de ninguem). Depois, na tela Rede LAN, procure os PCs e escolha o par."
}
Write-Host ""
Write-Host "Para conferir se este PC esta liberado, no Postgres:"
Write-Host "    SHOW listen_addresses;   -- precisa responder *"
Write-Host ""
Write-Host "Teste de conexao daqui para o outro PC (troque o IP):"
Write-Host "    `$env:PGPASSWORD='<senha do banco>'; `"$pgBin\psql.exe`" -h 192.168.0.10 -p $DbPort -U exodo_user -d exodo_db -c 'SELECT 1'"

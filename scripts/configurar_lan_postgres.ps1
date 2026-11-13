# ============================================================================
# CONFIGURAR O POSTGRESQL PARA A REDE LOCAL - SISTEMA EXODO
# ============================================================================
# Prepara ESTE computador para o outro PC da loja conectar direto no banco
# local (sincronizacao_sem_nuvem / modo LAN):
#
#   0. CONFERE o pg_hba.conf ANTES de mexer em qualquer coisa: se tiver metodo
#      de autenticacao invalido (ex.: "md5-sha-256"), conserta para md5; se o
#      arquivo nao der para interpretar, ABORTA sem tocar no banco. Metodo
#      invalido derruba o PostgreSQL na hora de carregar o arquivo e o sistema
#      nao sobe - foi o que aconteceu na instalacao de 09/11/2026;
#   1. listen_addresses = '*' no postgresql.conf (o PostgreSQL passa a ouvir a
#      rede local, nao so o 127.0.0.1);
#   2. libera no pg_hba.conf a REDE LOCAL deste PC (senha obrigatoria) - ou um
#      IP/rede especifica, se voce pedir; remove os blocos antigos duplicados
#      que se acumulam a cada execucao;
#   3. abre a porta no Firewall do Windows;
#   4. grava PAR_HOST/PAR_PORT no .env deste PC;
#   5. reinicia o PostgreSQL do jeito certo (servico ou instancia manual),
#      CONFIRMA que voltou a responder e, se nao voltar, RESTAURA o
#      pg_hba.conf anterior - nunca deixa o banco fora do ar.
#
# Rode UMA VEZ EM CADA PC, como Administrador. Por padrao NAO precisa informar
# IP nenhum: ele libera a REDE LOCAL inteira (a sub-rede /24 deste PC). Assim
# uma loja com varios caixas nao precisa cruzar IP a IP.
#
#   Liberar a rede toda:   (sem argumento)
#   Liberar so um PC:      -PeerHost 192.168.0.12
#   Liberar uma rede:      -Subnet 192.168.0.0/24
#   So configurar, sem reiniciar:  -NaoReiniciar
#
# Depois disso, o SincronizadorNuvem de cada PC passa a atualizar os bancos
# tambem pela rede local. Nada aqui toca a nuvem.
#
# Tudo o que este script faz fica registrado em logs\configurar_lan.log
# (importante: o instalador chama este script escondido - runhidden).
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

# --- metodos de autenticacao que o PostgreSQL aceita ------------------------
# Qualquer outra coisa (ex.: "md5-sha-256") faz o servidor RECUSAR o arquivo
# inteiro e nao subir - por isso esta lista e o coracao desta versao.
$MetodosValidos = @(
    'trust', 'reject', 'scram-sha-256', 'md5', 'password',
    'gss', 'sspi', 'peer', 'ident', 'ldap', 'radius', 'pam', 'cert'
)

# --- log -------------------------------------------------------------------
$LogScript = $null

function Registrar([string]$Texto, [string]$Cor = "") {
    if ($Cor) { Write-Host $Texto -ForegroundColor $Cor } else { Write-Host $Texto }
    if ($LogScript) {
        try {
            $pasta = Split-Path -Parent $LogScript
            if ($pasta -and -not (Test-Path $pasta)) {
                New-Item -ItemType Directory -Path $pasta -Force | Out-Null
            }
            $limpo = ($Texto -replace "`r?`n", ' ').Trim()
            if ($limpo) {
                $carimbo = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Add-Content -Path $LogScript -Value "$carimbo  $limpo" -Encoding UTF8
            }
        } catch { }
    }
}

function Falhar($mensagem) {
    Write-Host ""
    Registrar "ERRO: $mensagem" 'Red'
    exit 1
}

# --- leitura/validacao do pg_hba.conf --------------------------------------

# Interpreta UMA linha do pg_hba.conf.
#   $null ............ linha vazia ou comentario (nada a fazer)
#   Invalida=true .... nao da para interpretar (aborta: nao da para consertar)
#   Metodo/Indice .... metodo de autenticacao e a posicao dele na linha
function Get-LinhaHba([string]$Linha) {
    $t = $Linha.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { return $null }
    $p = $t -split '\s+'
    $tipo = $p[0].ToLower()

    if ($tipo -eq 'local') {
        if ($p.Count -lt 4) {
            return [pscustomobject]@{
                Invalida = $true
                Motivo  = "linha 'local' precisa de 4 campos (tipo banco usuario metodo): '$t'"
            }
        }
        return [pscustomobject]@{
            Invalida = $false; Tipo = 'local'; Metodo = $p[3]; Indice = 3; Endereco = ''
        }
    }
    if ($tipo -eq 'host' -or $tipo -eq 'hostssl' -or $tipo -eq 'hostnossl') {
        if ($p.Count -lt 5) {
            return [pscustomobject]@{
                Invalida = $true
                Motivo  = "linha '$tipo' precisa de 5 campos (tipo banco usuario endereco metodo): '$t'"
            }
        }
        return [pscustomobject]@{
            Invalida = $false; Tipo = $tipo; Metodo = $p[4]; Indice = 4; Endereco = $p[3]
        }
    }
    if ($tipo -eq 'include' -or $tipo -eq 'include_if_exists') {
        # PG 15+ aceita include no pg_hba. Nao tem metodo; nao mexemos.
        return [pscustomobject]@{
            Invalida = $false; Tipo = $tipo; Metodo = ''; Indice = -1; Endereco = ''
        }
    }
    return [pscustomobject]@{
        Invalida = $true; Motivo = "tipo de linha desconhecido '$($p[0])': '$t'"
    }
}

# Devolve a lista de problemas do conteudo (vazia = arquivo utilizavel).
function Validar-ConteudoHba([string]$Texto) {
    $problemas = @()
    $n = 0
    foreach ($linha in ($Texto -split "`r?`n")) {
        $n++
        $info = Get-LinhaHba $linha
        if ($null -eq $info) { continue }
        if ($info.Invalida) {
            $problemas += "linha ${n}: $($info.Motivo)"
            continue
        }
        if ($info.Metodo -and ($MetodosValidos -notcontains $info.Metodo.ToLower())) {
            $problemas += "linha ${n}: metodo de autenticacao invalido '$($info.Metodo)' - o PostgreSQL NAO sobe com isso"
        }
    }
    return $problemas
}

# Troca metodo invalido por 'md5', mantendo o resto da linha intacto.
# Devolve Texto (consertado) + Correcoes (o que foi mudado).
function Consertar-ConteudoHba([string]$Texto) {
    $correcoes = @()
    $n = 0
    $saida = New-Object System.Collections.Generic.List[string]
    foreach ($linha in ($Texto -split "`r?`n")) {
        $n++
        $info = Get-LinhaHba $linha
        $trocou = $false
        if ($null -ne $info -and (-not $info.Invalida) -and $info.Indice -ge 0 -and
            $info.Metodo -and ($MetodosValidos -notcontains $info.Metodo.ToLower())) {
            $velho = $info.Metodo
            $novo = $linha
            if ($info.Tipo -eq 'local') {
                $novo = [regex]::Replace($linha, '^(\s*local\s+\S+\s+\S+\s+)\S+', '${1}md5')
            } else {
                $novo = [regex]::Replace($linha, '^(\s*host\w*\s+\S+\s+\S+\s+\S+\s+)\S+', '${1}md5')
            }
            if ($novo -ne $linha) {
                $correcoes += "linha ${n}: metodo '$velho' -> 'md5'"
                $linha = $novo
                $trocou = $true
            }
        }
        [void]$saida.Add($linha)
    }
    return [pscustomobject]@{ Texto = ($saida -join "`r`n"); Correcoes = $correcoes }
}

# Acha o PRIMEIRO bloco "# Exodo - sincronizacao LAN" (todos eles sao o rabo do
# arquivo, porque so acrescentamos no final), devolve o que fica antes + os
# enderecos que ja estavam liberados, para nao perder ninguem na hora de
# reescrever um bloco unico e sem duplicatas.
function Separar-BlocosExodo([string[]]$Linhas) {
    $vazio = [pscustomobject]@{
        Manter = @($Linhas); Enderecos = @(); Cortadas = 0; Recusou = $null
    }
    if ($null -eq $Linhas -or $Linhas.Count -eq 0) { return $vazio }

    $inicio = -1
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        if ($Linhas[$i] -match '^\s*#\s*Exodo\s*-\s*sincronizacao LAN') { $inicio = $i; break }
    }
    if ($inicio -lt 0) { return $vazio }

    $enderecos = @()
    for ($i = $inicio; $i -lt $Linhas.Count; $i++) {
        $t = $Linhas[$i].Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $info = Get-LinhaHba $t
        if ($null -eq $info -or $info.Invalida) {
            return [pscustomobject]@{
                Manter = @($Linhas); Enderecos = @(); Cortadas = 0
                Recusou = "linha $($i + 1): '$t'"
            }
        }
        if ($info.Tipo -like 'include*') {
            # Tem include depois do bloco: cortar poderia perder regra de gente.
            return [pscustomobject]@{
                Manter = @($Linhas); Enderecos = @(); Cortadas = 0
                Recusou = "linha $($i + 1): '$t'"
            }
        }
        if ($info.Endereco) { $enderecos += $info.Endereco }
    }

    $manter = @()
    if ($inicio -gt 0) { $manter = @($Linhas[0..($inicio - 1)]) }
    return [pscustomobject]@{
        Manter = $manter; Enderecos = $enderecos
        Cortadas = ($Linhas.Count - $inicio); Recusou = $null
    }
}

# --- execucao de ferramentas do PostgreSQL ---------------------------------
# Roda um .exe capturando saida e codigo de saida, sem deixar o
# $ErrorActionPreference=Stop transformar stderr em erro terminal.
function Executar-Nativo([string]$Arquivo, [string[]]$Argumentos) {
    if (-not (Test-Path $Arquivo)) {
        return [pscustomobject]@{ Saida = "nao encontrado: $Arquivo"; Codigo = 1 }
    }
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = (& $Arquivo @Argumentos 2>&1 | Out-String)
        $codigo = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eap
    }
    return [pscustomobject]@{ Saida = $saida; Codigo = $codigo }
}

# Espera o banco responder na porta. pg_isready e a prova real de que o
# servidor subiu (com pg_hba invalido ele nem chega a subir).
function Esperar-BancoPronto([int]$Porta, [int]$Segundos) {
    $pgIsReady = Join-Path $pgBin 'pg_isready.exe'
    for ($i = 0; $i -lt $Segundos; $i++) {
        if (Test-Path $pgIsReady) {
            $r = Executar-Nativo $pgIsReady @('-h', '127.0.0.1', '-p', "$Porta", '-t', '2')
            if ($r.Codigo -eq 0) { return $true }
        } else {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $ar = $tcp.BeginConnect('127.0.0.1', $Porta, $null, $null)
                $ok = $ar.AsyncWaitHandle.WaitOne(1000) -and $tcp.Connected
                $tcp.Close()
                if ($ok) { return $true }
            } catch { }
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

# Sobe/reinicia o PostgreSQL usando o mecanismo que ESTA em uso:
#   - servico rodando  -> reinicia o servico;
#   - instancia manual -> pg_ctl restart (servico parado + banco na mao);
#   - nada rodando     -> tenta o servico (volta sozinho no boot), senao pg_ctl.
# Devolve $true se mandou subir; a saida nunca e engolida.
function Reiniciar-Postgres([string]$Log) {
    $nomeServico = $null
    if ($ServicoPostgres) { $nomeServico = $ServicoPostgres.Name }
    if (-not $nomeServico) {
        $s = Get-Service -Name '*postgres*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($s) { $nomeServico = $s.Name }
    }

    $servicoRodando = $false
    if ($nomeServico) {
        try { $servicoRodando = ((Get-Service -Name $nomeServico -ErrorAction Stop).Status -eq 'Running') }
        catch { }
    }

    $pgRodando = $false
    if (Test-Path $pgCtl) {
        $r0 = Executar-Nativo $pgCtl @('-D', $DataDir, 'status')
        $pgRodando = ($r0.Codigo -eq 0)
    }

    if ($servicoRodando) {
        try {
            Restart-Service -Name $nomeServico -Force -ErrorAction Stop
            Registrar "      Servico $nomeServico reiniciado."
            return $true
        } catch {
            Registrar "      AVISO: servico $nomeServico nao reiniciou ($($_.Exception.Message))." 'Yellow'
        }
    }

    if ($pgRodando -and (Test-Path $pgCtl)) {
        $r = Executar-Nativo $pgCtl @('-D', $DataDir, '-l', $Log, 'restart', '-w', '-t', '30')
        if ($r.Codigo -eq 0) {
            Registrar "      PostgreSQL reiniciado (pg_ctl)."
            return $true
        }
        Registrar "      AVISO: pg_ctl restart falhou:" 'Yellow'
        Registrar $r.Saida
    }

    if ($nomeServico -and -not $pgRodando) {
        try {
            Start-Service -Name $nomeServico -ErrorAction Stop
            Registrar "      Servico $nomeServico iniciado."
            return $true
        } catch {
            Registrar "      AVISO: servico $nomeServico nao iniciou ($($_.Exception.Message))." 'Yellow'
        }
    }

    if (Test-Path $pgCtl) {
        $r = Executar-Nativo $pgCtl @('-D', $DataDir, '-l', $Log, 'start', '-w', '-t', '30')
        if ($r.Codigo -eq 0) {
            Registrar "      PostgreSQL iniciado (pg_ctl)."
            return $true
        }
        Registrar "      AVISO: pg_ctl start falhou:" 'Yellow'
        Registrar $r.Saida
    }
    return $false
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
$LogScript = Join-Path (Join-Path $AppDir "logs") "configurar_lan.log"

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
Registrar "--- inicio da configuracao LAN ---"

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

# --- 0. conferir o pg_hba.conf antes de mexer em NADA ----------------------
# Um metodo invalido nao impede a gravacao: impede o PostgreSQL de SUBIR. Por
# isso a conferencia vem primeiro, e uma falha aqui nao toca em arquivo nenhum.
Write-Host ""
Write-Host "[0/5] Conferindo o pg_hba.conf (metodos de autenticacao)..."
$hbaOriginal = Get-Content $hbaFile -Raw
$conserto = Consertar-ConteudoHba $hbaOriginal
if ($conserto.Correcoes.Count -gt 0) {
    Registrar "      ATENCAO: metodo(s) invalido(s) encontrado(s) no arquivo atual:" 'Yellow'
    foreach ($c in $conserto.Correcoes) { Registrar "        - $c" 'Yellow' }
    Registrar "      Sem consertar, o PostgreSQL recusa o arquivo e o banco nao sobe." 'Yellow'
}
$hba = $conserto.Texto

# Blocos antigos: corta duplicados e guarda os enderecos ja liberados.
$linhas = @($hba -split "`r?`n")
$sep = Separar-BlocosExodo $linhas
$dedupFeito = $false
if ($sep.Recusou) {
    Registrar "      AVISO: nao dedupliquei os blocos antigos ($($sep.Recusou))." 'Yellow'
} else {
    if ($sep.Cortadas -gt 0) {
        Registrar "      Removendo $($sep.Cortadas) linha(s) de blocos Exodo antigos (duplicados)."
    }
    $linhas = @($sep.Manter)
    $dedupFeito = $true
}

$problemas = @(Validar-ConteudoHba ($linhas -join "`r`n"))
if ($problemas.Count -gt 0) {
    Falhar ("o pg_hba.conf nao da para interpretar, entao NADA foi alterado e o PostgreSQL " +
            "nao foi reiniciado:`r`n  " + ($problemas -join "`r`n  "))
}
Registrar "      pg_hba.conf utilizavel."

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
    $stampConf = Get-Date -Format 'yyyyMMdd_HHmmss'
    Copy-Item $confFile "$confFile.bak_lan_$stampConf" -Force
    Copy-Item $confFile "$confFile.bak_lan" -Force
    [System.IO.File]::WriteAllText($confFile, $conf, [System.Text.Encoding]::Default)
    Registrar "      postgresql.conf atualizado (backup: postgresql.conf.bak_lan_$stampConf)"
} else {
    Registrar "      ja estava correto."
}

# --- 2. pg_hba.conf --------------------------------------------------------
# Quem pode entrar: um IP (-PeerHost), uma rede (-Subnet) ou, por padrao, a
# rede local inteira (a sub-rede /24 deste PC).
$alvos = @()
if (-not [string]::IsNullOrWhiteSpace($Subnet)) {
    $alvos += $Subnet.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($PeerHost)) {
    if ($PeerHost -match '/') {
        $alvos += $PeerHost.Trim()
    } else {
        # O pg_hba.conf so aceita ENDERECO (IP ou rede), nunca nome de
        # computador: uma linha "NOME/32" e invalida e derruba o PostgreSQL
        # no proximo restart. Se vier um nome, resolve para o IP de hoje.
        $ehIp = $false
        try {
            $ipTentativa = $null
            $ehIp = [System.Net.IPAddress]::TryParse($PeerHost.Trim(), [ref]$ipTentativa)
        } catch { $ehIp = $false }
        if (-not $ehIp) {
            $ipResolvido = $null
            try {
                $ipResolvido = [System.Net.Dns]::GetHostAddresses($PeerHost.Trim()) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -First 1 -ExpandProperty IPAddressToString
            } catch { }
            if ($ipResolvido) {
                Registrar "      Nome '$($PeerHost.Trim())' resolvido para $ipResolvido (o pg_hba.conf usa IP)."
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

# Prova que cada alvo e um endereco que o PostgreSQL aceita. Um valor torto
# (ex.: "minha-loja/24") passaria em silencio aqui e so derrubaria o banco no
# restart - exatamente o tipo de susto que a instalacao de 09/11 deu.
foreach ($a in $alvos) {
    $partes = $a -split '/'
    $ipOk = $false
    try {
        $ipTeste = $null
        $ipOk = [System.Net.IPAddress]::TryParse($partes[0], [ref]$ipTeste)
    } catch { $ipOk = $false }
    if (-not $ipOk) {
        Falhar "'$a' nao e um IP/rede valido. O pg_hba.conf so aceita endereco (ex.: 192.168.0.12 ou 192.168.0.0/24), nunca nome de computador."
    }
    if ($partes.Count -eq 2) {
        # Mascara: 0..32 em IPv4, 0..128 em IPv6. Um valor maior faz o
        # PostgreSQL recusar o arquivo inteiro no restart.
        $maxMascara = if ($partes[0] -match ':') { 128 } else { 32 }
        $mascara = 0
        if (-not [int]::TryParse($partes[1], [ref]$mascara) -or $mascara -lt 0 -or $mascara -gt $maxMascara) {
            Falhar "'$a' tem mascara invalida (deve ser 0..$maxMascara para este endereco)."
        }
    }
}

$alvos = @($alvos | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
Write-Host "[2/5] Liberando no pg_hba.conf: $($alvos -join ', ')"

# Enderecos que ja estavam no bloco Exodo (nada de perder o par configurado
# numa rodada anterior) + os de hoje + os que o Windows precisa em IPv6.
$enderecos = @()
if ($dedupFeito) { $enderecos += @($sep.Enderecos) }
$enderecos += $alvos
$enderecos += @('fe80::/10', '::1/128')
$enderecos = @($enderecos | Where-Object { $_ } | ForEach-Object { $_.Trim() } | Select-Object -Unique)

$extra = ""
foreach ($end in $enderecos) {
    $extra += "host    all             all             $end            md5`r`n"
}
$hba = (($linhas -join "`r`n").TrimEnd()) +
       "`r`n`r`n# Exodo - sincronizacao LAN (adicionado automaticamente)`r`n" + $extra

# Prova final: so grava se o arquivo que vai para o disco for interpretavel.
$problemasFinais = @(Validar-ConteudoHba $hba)
if ($problemasFinais.Count -gt 0) {
    Falhar ("o pg_hba.conf ficaria invalido, entao NADA foi alterado e o PostgreSQL nao foi " +
            "reiniciado:`r`n  " + ($problemasFinais -join "`r`n  "))
}

if ($hba -ne $hbaOriginal) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    Copy-Item $hbaFile "$hbaFile.bak_lan_$stamp" -Force
    Copy-Item $hbaFile "$hbaFile.bak_lan" -Force
    [System.IO.File]::WriteAllText($hbaFile, $hba, [System.Text.Encoding]::Default)
    Registrar "      pg_hba.conf atualizado (backup: pg_hba.conf.bak_lan_$stamp)"
} else {
    Registrar "      pg_hba.conf ja estava correto."
}

# Guarda a versao CONsertada do arquivo, para o passo 5 poder voltar atras
# sem reintroduzir um metodo invalido.
$hbaValidoAntes = $conserto.Texto

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
        -LocalPort $DbPort -RemoteAddress LocalSubnet -Action Allow -Profile Any | Out-Null
    # Descoberta automatica dos outros dispositivos Exodo (UDP broadcast).
    $regraDescoberta = "Exodo Sync LAN - Descoberta UDP"
    Remove-NetFirewallRule -DisplayName $regraDescoberta -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $regraDescoberta -Direction Inbound -Protocol UDP `
        -LocalPort 45872 -RemoteAddress LocalSubnet -Action Allow -Profile Any | Out-Null
    Registrar "      PostgreSQL e descoberta UDP liberados somente para a rede local."
} catch {
    Falhar "nao consegui configurar as regras de Firewall para PostgreSQL/descoberta LAN: $($_.Exception.Message)"
}

# --- 4. .env ---------------------------------------------------------------
Write-Host ""
$umParSo = (-not [string]::IsNullOrWhiteSpace($PeerHost)) -and ($PeerHost -notmatch '/')
if (-not $umParSo) {
    Write-Host "[4/5] Ativando descoberta automatica (sem IP manual)."
    if (-not (Test-Path $envFile)) { Falhar ".env nao encontrado em $envFile" }
    $envTxt = Get-Content $envFile -Raw
    $envNovo = [regex]::Replace($envTxt, "(?m)^\s*LAN_SYNC\s*=.*$", "LAN_SYNC=true", 1)
    if ($envNovo -eq $envTxt -and $envTxt -notmatch "(?m)^\s*LAN_SYNC\s*=") {
        $envNovo = $envTxt.TrimEnd() + "`r`nLAN_SYNC=true`r`n"
    }
    if ($envNovo -ne $envTxt) {
        Copy-Item $envFile "$envFile.bak_lan" -Force
        [System.IO.File]::WriteAllText($envFile, $envNovo, [System.Text.Encoding]::Default)
    }
    Registrar "      LAN_SYNC=true configurado; nenhum IP precisa ser informado."
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
    [System.IO.File]::WriteAllText($envFile, $envTxt, [System.Text.Encoding]::Default)
    Registrar "      .env atualizado: PAR_HOST=$PeerHost PAR_PORT=$DbPort"
}

# --- 5. Reiniciar e CONFIRMAR ---------------------------------------------
Write-Host ""
$pgLog = Join-Path (Join-Path $AppDir "logs") "postgresql.log"

if ($NaoReiniciar) {
    Write-Host "[5/5] Reinicio ignorado (-NaoReiniciar). O outro PC so conecta depois de reiniciar o PostgreSQL."
    Registrar "      Reinicio ignorado (-NaoReiniciar)."
} else {
    Write-Host "[5/5] Reiniciando o PostgreSQL e confirmando que voltou..."
    $pronto = $false
    if (Reiniciar-Postgres $pgLog) {
        $pronto = Esperar-BancoPronto ([int]$DbPort) 30
    }

    if (-not $pronto) {
        Registrar "      O PostgreSQL NAO voltou apos a mudanca." 'Red'
        Registrar "      Restaurando o pg_hba.conf de antes desta rodada..." 'Yellow'
        try {
            [System.IO.File]::WriteAllText($hbaFile, $hbaValidoAntes, [System.Text.Encoding]::Default)
        } catch {
            Falhar "nao consegui restaurar o pg_hba.conf: $($_.Exception.Message)"
        }
        $restaurou = $false
        if (Reiniciar-Postgres $pgLog) {
            $restaurou = Esperar-BancoPronto ([int]$DbPort) 30
        }
        if ($restaurou) {
            Falhar ("a configuracao desta rodada derrubou o banco; RESTAUREI o pg_hba.conf " +
                    "anterior e o PostgreSQL voltou. Nao ha mudanca LAN neste PC - veja as " +
                    "linhas acima e o pg_hba.conf antes de rodar de novo.")
        }
        Registrar "      Restaurei o arquivo e o banco AINDA nao subiu: o problema NAO e o pg_hba.conf." 'Yellow'
        if (Test-Path $pgLog) {
            Registrar "      Ultimas linhas de $pgLog :"
            Get-Content $pgLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object {
                Registrar "        $_"
            }
        }
        Falhar ("PostgreSQL fora do ar. Causas comuns: porta $DbPort ocupada por outra " +
                "instancia, memoria compartilhada de um servidor antigo ainda viva, ou " +
                "permissao da pasta de dados.")
    }

    Registrar "      PostgreSQL respondendo na porta $DbPort." 'Green'

    if ($ServicoPostgres -and $ServicoPostgres.Name) {
        $st = Get-Service -Name $ServicoPostgres.Name -ErrorAction SilentlyContinue
        if ($st -and $st.Status -ne 'Running') {
            Registrar ("      AVISO: o servico $($ServicoPostgres.Name) continua '$($st.Status)' - o " +
                       "banco esta rodando fora do servico e NAO volta sozinho no reboot. Para " +
                       "gerenciar pelo servico: pg_ctl -D `"$DataDir`" stop; net start $($ServicoPostgres.Name)") 'Yellow'
        }
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
Write-Host ""
Write-Host "Log desta execucao: $LogScript"
Registrar "--- fim da configuracao LAN ---"

# ============================================================================
# SETUP POSTGRESQL - SISTEMA EXODO
# ============================================================================
# Este script e chamado pelo instalador Inno Setup para configurar
# o PostgreSQL embarcado na maquina do cliente.
#
# Parametros:
#   -PostgresDir: Caminho para a pasta postgresql (contem bin\initdb.exe)
#   -DataDir:     Caminho para a pasta data (cluster PostgreSQL)
#   -AppDir:      Caminho para a raiz do app (contem scripts\ e .env)
# ============================================================================
# IMPORTANTE: este arquivo deve conter SOMENTE caracteres ASCII.
# Emojis ou acentos quebram o PowerShell 5.1 (Windows) que o le como ANSI.
# ============================================================================

param(
    [string]$PostgresDir,
    [string]$DataDir,
    [string]$AppDir,
    [string]$DbUser = "exodo_user",
    [string]$DbPassword = "ex@#$",
    [string]$DbName = "exodo_db",
    [string]$DbPort = "5432"
)

$ErrorActionPreference = "Continue"
# NOTA: NUNCA use "Stop" aqui - comandos nativos (pg_ctl/initdb) escrevem
# no stderr em situacoes normais (ex: stop sem instancia rodando) e com
# "Stop" o script inteiro aborta. Usamos $LASTEXITCODE para validar.

# Descobrir caminhos absolutos
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $AppDir) { $AppDir = Split-Path $ScriptDir -Parent }
if (-not $PostgresDir) { $PostgresDir = Join-Path $AppDir "postgresql" }
if (-not $DataDir) { $DataDir = Join-Path $AppDir "pgdata" }

$pgBin = Join-Path $PostgresDir "bin"
$initdb = Join-Path $pgBin "initdb.exe"
$pgCtl = Join-Path $pgBin "pg_ctl.exe"
$psql = Join-Path $pgBin "psql.exe"
$createdb = Join-Path $pgBin "createdb.exe"
$logFile = Join-Path $AppDir "logs\postgres_install.log"

# Garantir que a pasta de logs existe
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host $Message
}

function Test-PostgresConnection {
    param([int]$Retries = 5, [int]$DelaySeconds = 3)
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $result = & $psql -U $DbUser -d postgres -h localhost -p $DbPort -c "SELECT 1" 2>&1
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {
            # Ignorar erro e tentar novamente
        }
        if ($i -lt $Retries) {
            Write-Log "Aguardando PostgreSQL iniciar... (tentativa $i/$Retries)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $false
}

Write-Log "========================================"
Write-Log "INICIANDO CONFIGURACAO DO POSTGRESQL"
Write-Log "========================================"
Write-Log "PostgresDir: $PostgresDir"
Write-Log "DataDir: $DataDir"
Write-Log "AppDir: $AppDir"

# 1. Verificar se PostgreSQL existe
if (-not (Test-Path $initdb)) {
    Write-Log "ERRO: PostgreSQL nao encontrado em: $pgBin"
    Write-Log "   Verifique se extraiu o PostgreSQL ZIP em: $PostgresDir"
    exit 1
}
Write-Log "PostgreSQL encontrado em: $pgBin"

# 1.5 Parar servico/instancia existente (importante em upgrades para liberar a porta 5432)
sc.exe stop PostgreSQL_Exodo 2>&1 | Out-Null
Start-Sleep -Seconds 2
$oldData = Join-Path $AppDir "data"
if ((Test-Path (Join-Path $oldData "postgresql.conf")) -and ($oldData -ne $DataDir)) {
    Write-Log "Parando instancia antiga (cluster em $oldData)..."
    & $pgCtl -D $oldData stop -m fast 2>&1 | Out-Null
}

# 2. Inicializar cluster de dados (se ainda nao existir)
$pgConfFile = Join-Path $DataDir "postgresql.conf"
if (-not (Test-Path $pgConfFile)) {
    Write-Log "Inicializando cluster de dados PostgreSQL..."

    try {
        # Criar diretorio de dados se nao existir; limpar se existir sem cluster valido
        if (-not (Test-Path $DataDir)) {
            New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
        } elseif (-not (Test-Path $pgConfFile)) {
            # CINTO DE SEGURANCA: nunca apagar se contiver assets do Flutter
            if ((Test-Path (Join-Path $DataDir "flutter_assets")) -or (Test-Path (Join-Path $DataDir "app.so")) -or (Test-Path (Join-Path $DataDir "icudtl.dat"))) {
                Write-Log "ERRO FATAL: $DataDir contem assets do app (flutter_assets/app.so/icudtl.dat). Abortando para nao apagar o app."
                exit 1
            }
            Write-Log "Limpando diretorio de dados incompleto: $DataDir"
            Get-ChildItem -Path $DataDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        # initdb sem senha primeiro (depois alteramos via SQL)
        # Usar --auth=trust temporariamente para poder conectar sem senha
        # A senha sera configurada depois, e o pg_hba.conf sera alterado para md5
        # NOTA: os arquivos de log do initdb ficam em logs\ (NAO dentro do data dir,
        #       senao o initdb reclama que o diretorio nao esta vazio)
        $initdbOut = Join-Path $logDir "initdb_out.txt"
        $initdbErr = Join-Path $logDir "initdb_err.txt"
        $proc = Start-Process -FilePath $initdb -ArgumentList "-D `"$DataDir`" --username=$DbUser --auth=trust" -Wait -NoNewWindow -PassThru -RedirectStandardOutput $initdbOut -RedirectStandardError $initdbErr

        if ($proc.ExitCode -eq 0) {
            Write-Log "Cluster inicializado com sucesso!"
        } else {
            $errMsg = Get-Content $initdbErr -Raw -ErrorAction SilentlyContinue
            Write-Log "initdb retornou codigo $($proc.ExitCode): $errMsg"
            Write-Log "ERRO FATAL: nao foi possivel inicializar o cluster. Veja logs/initdb_err.txt"
            exit 1
        }
    } catch {
        Write-Log "Erro ao executar initdb: $($_.Exception.Message)"
        # Pode ja existir cluster
    }
} else {
    Write-Log "Cluster de dados ja existe em: $DataDir"
}

# 3. Configurar a porta no postgresql.conf (o initdb usa 5432 por padrao)
# NOTA: use [IO.File]::WriteAllText - o Set-Content -Encoding UTF8 do PS 5.1
#       grava BOM no inicio do arquivo e o PostgreSQL recusa ler o conf.
$confFile = Join-Path $DataDir "postgresql.conf"
if (Test-Path $confFile) {
    $conf = [System.IO.File]::ReadAllText($confFile)
    # Se a linha port ja existe, substitui; se nao existe, acrescenta UMA vez
    if ($conf -notmatch '(?m)^#?\s*port\s*=') { $conf += "`nport = $DbPort`n" }
    $newConf = $conf -replace '(?m)^#?\s*port\s*=.*$', "port = $DbPort"
    [System.IO.File]::WriteAllText($confFile, $newConf)
    Write-Log "Porta $DbPort definida no postgresql.conf"
}

# 3b. pg_hba.conf esta em trust (configurado no initdb)
Write-Log "pg_hba.conf em modo trust (temporario)"

# DEFINIR A SENHA AQUI (ANTES do teste de conexao): em instalacao nova o cluster
# esta em trust (senha ignorada, inofensivo), mas em REINSTALACAO/UPGRADE o
# pg_hba.conf ja esta em md5 - sem PGPASSWORD o teste do passo 4 falha, o script
# derrubaria um servico SAUDAVEL e abortaria a instalacao. Este foi um bug real
# que impedia o sistema de abrir ao instalar versao por cima.
$env:PGPASSWORD = $DbPassword

# 4. Iniciar PostgreSQL - via servico do Windows (nao herda o console e NAO TRAVA)
# NOTA: o comando 'pg_ctl start' capturado pelo PowerShell fica preso esperando o
#       postgres.exe fechar o handle herdado (trava a instalacao na maquina nova).
#       Por isso usamos o servico do Windows (pg_ctl register + sc start).
# IMPORTANTE: se o servico nao conseguir abrir o banco (ex: permissao ACL no data dir),
#       o script SEMPRE cai no inicio manual (comprovadamente funcional) - nunca desiste.
Write-Log "Iniciando PostgreSQL (registrando servico do Windows)..."
$pgLog = Join-Path $AppDir "logs\postgresql.log"

# Parar instancia anterior se estiver rodando (ex: instalacao cancelada antes)
& $pgCtl -D $DataDir stop -m fast 2>&1 | Out-Null
Start-Sleep -Seconds 2

# Ajustar ACLs do data dir: o servico roda como LocalSystem (SID S-1-5-18) e o cluster
# foi criado pelo admin (SID S-1-5-32-544) - sem permissao o servico nao abre o banco.
# Usar SIDs evita problema de idioma nos nomes (Administrators/Administradores).
try {
    & icacls.exe "$DataDir" /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /T /C 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Log "ACLs do data dir ajustadas (SYSTEM + Administradores)." }
    else { Write-Log "Aviso: icacls retornou codigo $LASTEXITCODE ao ajustar ACLs (nao fatal)." }
} catch {
    Write-Log "Aviso: nao foi possivel ajustar ACLs: $($_.Exception.Message)"
}
try {
    & icacls.exe "$AppDir" /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /T /C 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log "Aviso: icacls AppDir retornou codigo $LASTEXITCODE (nao fatal)." }
} catch {
    Write-Log "Aviso: nao foi possivel ajustar ACLs do AppDir: $($_.Exception.Message)"
}

# Remover servico anterior se existir
& sc.exe delete "PostgreSQL_Exodo" 2>&1 | Out-Null
Start-Sleep -Seconds 1

# Registrar como servico Windows
$registerArgs = "-D `"$DataDir`" register -N `"PostgreSQL_Exodo`""
$regProc = Start-Process -FilePath $pgCtl -ArgumentList $registerArgs -Wait -NoNewWindow -PassThru
if ($regProc.ExitCode -eq 0) {
    Write-Log "Servico PostgreSQL_Exodo registrado!"

    # Configurar para iniciar automaticamente
    & sc.exe config "PostgreSQL_Exodo" start= auto 2>&1 | Out-Null
    & sc.exe failure "PostgreSQL_Exodo" reset=86400 actions=restart/1000/restart/1000/restart/1000 2>&1 | Out-Null

    # Iniciar servico
    & sc.exe start "PostgreSQL_Exodo" 2>&1 | Out-Null
    Start-Sleep -Seconds 4
    # O codigo 4 do sc = RUNNING (independente do idioma: STATE/ESTADO)
    $svcQuery = (& sc.exe query "PostgreSQL_Exodo" 2>&1) -join " "
    if ($svcQuery -match ":\s*4\s") {
        Write-Log "Servico PostgreSQL_Exodo RODANDO!"
    } else {
        Write-Log "AVISO: servico registrado mas estado nao confirmado: $svcQuery"
    }
} else {
    Write-Log "Falha ao registrar servico (exit $($regProc.ExitCode))."
}

# Aguardar conexao (como esta em trust, nao precisa de senha)
Write-Log "Aguardando conexao com PostgreSQL..."
if (-not (Test-PostgresConnection -Retries 8 -DelaySeconds 3)) {
    Write-Log "ERRO: banco nao respondeu pelo servico. Derrubando servico e iniciando MANUALMENTE..."
    # Evitar conflito de porta antes do inicio manual
    & sc.exe stop "PostgreSQL_Exodo" 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & sc.exe delete "PostgreSQL_Exodo" 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    & $pgCtl -D $DataDir stop -m fast 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    # Inicio manual via cmd (redireciona para arquivo - sem pipe, sem travamento)
    cmd /c "`"$pgCtl`" -D `"$DataDir`" -l `"$pgLog`" start -w -t 30 > `"$logDir\pgctl_start.log`" 2>&1"
    Write-Log "Inicio manual executado (veja logs\pgctl_start.log se houver erro)"
    if (-not (Test-PostgresConnection -Retries 8 -DelaySeconds 3)) {
        Write-Log "ERRO FATAL: PostgreSQL nao subiu nem pelo servico nem manualmente"
        Write-Log "Veja o log do servidor: $pgLog"
        & $pgCtl -D $DataDir status 2>&1
        exit 1
    }
    # TENTAR NOVAMENTE registrar o servico (agora que o banco esta de pe, o registro
    # costuma funcionar e preserva o auto-start no boot)
    # Registrar o servico de novo para preservar auto-start no proximo boot.
    # IMPORTANTE: a instancia manual ja esta segurando a porta 5432, entao NAO
    # fazemos sc start agora (falharia por porta em uso). O servico registrado
    # assumira no proximo boot; o banco JA esta rodando manualmente neste momento.
    $registerArgs2 = "-D `"$DataDir`" register -N `"PostgreSQL_Exodo`""
    $regProc2 = Start-Process -FilePath $pgCtl -ArgumentList $registerArgs2 -Wait -NoNewWindow -PassThru
    if ($regProc2.ExitCode -eq 0) {
        & sc.exe config "PostgreSQL_Exodo" start= auto 2>&1 | Out-Null
        & sc.exe failure "PostgreSQL_Exodo" reset=86400 actions=restart/1000/restart/1000/restart/1000 2>&1 | Out-Null
        Write-Log "Servico PostgreSQL_Exodo registrado apos inicio manual (assume no proximo boot - auto-start preservado)."
    } else {
        Write-Log "AVISO: nao foi possivel registrar o servico apos inicio manual - o banco sobe sozinho pelo Sincronizador."
    }
}
Write-Log "PostgreSQL iniciado e respondendo na porta $DbPort!"

# 5. Configurar senha do usuario (agora que estamos conectados via trust)
Write-Log "Configurando senha do usuario '$DbUser'..."
try {
    & $psql -U $DbUser -d postgres -h localhost -p $DbPort -c "ALTER USER $DbUser WITH PASSWORD '$DbPassword';" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Senha configurada com sucesso!"
    } else {
        Write-Log "ERRO ao configurar senha (exit $LASTEXITCODE)"
    }
} catch {
    Write-Log "Erro ao configurar senha: $($_.Exception.Message)"
}

# IMPORTANTE: a partir daqui a autenticacao e por senha (md5) -
#    enviamos a senha via PGPASSWORD para todas as conexoes seguintes
$env:PGPASSWORD = $DbPassword

# 5b. Agora que a senha foi configurada, ativar md5 no pg_hba.conf
Write-Log "Ativando autenticacao md5 no pg_hba.conf..."
$hbaFile = Join-Path $DataDir "pg_hba.conf"
if (Test-Path $hbaFile) {
    try {
        $content = [System.IO.File]::ReadAllText($hbaFile)
        $content = $content -replace 'host\s+all\s+all\s+127\.0\.0\.1/32\s+\w+', "host    all             all             127.0.0.1/32            md5"
        $content = $content -replace 'host\s+all\s+all\s+::1/128\s+\w+', "host    all             all             ::1/128                 md5"
        [System.IO.File]::WriteAllText($hbaFile, $content)
        Write-Log "pg_hba.conf alterado para md5"

        # Recarregar configuracao sem parar o servico
        & $pgCtl -D $DataDir reload 2>&1 | Out-Null
        Write-Log "Configuracao recarregada!"
    } catch {
        Write-Log "Aviso: nao foi possivel alterar pg_hba.conf: $($_.Exception.Message)"
    }
}

# 6. Criar banco de dados
Write-Log "Verificando banco de dados '$DbName'..."
try {
    $dbExists = & $psql -U $DbUser -d postgres -h localhost -p $DbPort -t -c "SELECT 1 FROM pg_database WHERE datname='$DbName'" 2>&1
    if ($dbExists.Trim() -eq "1") {
        Write-Log "Banco '$DbName' ja existe"
    } else {
        Write-Log "Criando banco de dados '$DbName'..."
        & $createdb -U $DbUser -h localhost -p $DbPort -O $DbUser $DbName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Banco '$DbName' criado com sucesso!"
        } else {
            Write-Log "createdb falhou, tentando via SQL..."
            & $psql -U $DbUser -d postgres -h localhost -p $DbPort -c "CREATE DATABASE $DbName OWNER $DbUser;" 2>&1
        }
    }
} catch {
    Write-Log "Erro ao verificar/criar banco: $($_.Exception.Message)"
}

# 7. Executar script SQL de inicializacao
$sqlFile = Join-Path $AppDir "scripts\init_db.sql"
if (Test-Path $sqlFile) {
    Write-Log "Executando script SQL de inicializacao: $sqlFile"
    try {
        & $psql -U $DbUser -d $DbName -h localhost -p $DbPort -f $sqlFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Script SQL executado com sucesso!"
        } else {
            Write-Log "ERRO ao executar script SQL (exit $LASTEXITCODE)"
        }
    } catch {
        Write-Log "Erro ao executar script SQL: $($_.Exception.Message)"
    }
} else {
    Write-Log "Script SQL nao encontrado em: $sqlFile"
    # Tentar caminho alternativo
    $altSqlFile = Join-Path $ScriptDir "init_db.sql"
    if (Test-Path $altSqlFile) {
        Write-Log "Usando script alternativo: $altSqlFile"
        & $psql -U $DbUser -d $DbName -h localhost -p $DbPort -f $altSqlFile 2>&1
    }
}

# 7a. Migracao de schema (uuid -> text): garante que instalacoes antigas
#     (com ids UUID e tabelas fantasma) sincronizem com a nuvem (ids TEXT).
#     Idempotente: nao faz nada em instalacoes ja no schema correto.
Write-Log "Executando migracao de schema (uuid->text)..."
$migrarScript = Join-Path $ScriptDir "migrar_schema.ps1"
if (-not (Test-Path $migrarScript)) { $migrarScript = Join-Path $AppDir "scripts\migrar_schema.ps1" }
if (Test-Path $migrarScript) {
    $migOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $migrarScript -DbHost localhost -DbPort $DbPort -DbUser $DbUser -DbPassword $DbPassword -DbName $DbName 2>&1
    $migOut | ForEach-Object { Write-Log $_ }
} else {
    Write-Log "AVISO: migrar_schema.ps1 nao encontrado - schema nao migrado (apenas instalacoes novas serao criadas corretas)"
}

# 7b. Verificar que as tabelas foram criadas (prova de que o banco esta OK)
Write-Log "Verificando tabelas criadas no banco '$DbName'..."
$tableCount = ((& $psql -U $DbUser -d $DbName -h localhost -p $DbPort -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'") -join " ").Trim()
$tablesNum = 0
if ($tableCount -match '^\d+$') { $tablesNum = [int]$tableCount }
Write-Log "Tabelas encontradas no banco '$DbName': $tablesNum"
if ($tablesNum -lt 1) {
    Write-Log "ERRO FATAL: nenhuma tabela foi criada - banco NAO configurado corretamente"
    exit 1
}

# 8. Garantir que o servico iniciara automaticamente com o Windows
# (o servico ja foi registrado e iniciado na etapa 4)
Write-Log "Configurando inicializacao automatica do servico PostgreSQL_Exodo..."
try {
    & sc.exe config "PostgreSQL_Exodo" start= auto 2>&1 | Out-Null
    & sc.exe failure "PostgreSQL_Exodo" reset=86400 actions=restart/1000/restart/1000/restart/1000 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # Se o servico nao estiver rodando, inicia
    $svcQuery = (& sc.exe query "PostgreSQL_Exodo" 2>&1) -join " "
    if ($svcQuery -match "1060" -or $svcQuery -match "nao existe|does not exist") {
        Write-Log "AVISO: servico PostgreSQL_Exodo NAO registrado - o banco foi iniciado manualmente e NAO iniciara sozinho ao ligar o PC"
    } elseif ($svcQuery -notmatch ":\s*4\s") {
        Write-Log "Servico parado - iniciando..."
        & sc.exe start "PostgreSQL_Exodo" 2>&1 | Out-Null
        Start-Sleep -Seconds 3
    }

    # Confirmar que o banco aceita conexoes (por servico OU pela instancia manual)
    if (-not (Test-PostgresConnection -Retries 5 -DelaySeconds 3)) {
        Write-Log "ERRO: PostgreSQL nao aceita conexoes"
        exit 1
    }
    # Verificar estado REAL do servico (nao inferir sucesso apenas pela conexao)
    $svcState = (& sc.exe query "PostgreSQL_Exodo" 2>&1) -join " "
    if ($svcState -match ":\s*4\s") {
        Write-Log "Servico PostgreSQL_Exodo configurado com inicio automatico e banco acessivel!"
    } elseif ($svcState -match "1060" -or $svcState -match "nao existe|does not exist") {
        Write-Log "AVISO: servico NAO registrado - banco rodando manualmente e NAO iniciara sozinho ao ligar o PC"
    } else {
        Write-Log "AVISO: banco acessivel, mas servico parado (estado: $svcState). O servico assumira no proximo boot."
    }
} catch {
    Write-Log "Erro ao configurar servico: $($_.Exception.Message)"
    # Garantir que PostgreSQL esta rodando (fallback via cmd - sem pipe, sem travamento)
    $statusOut = (& $pgCtl -D $DataDir status 2>&1) -join " "
    if ($statusOut -notmatch "executando|running") {
        cmd /c "`"$pgCtl`" -D `"$DataDir`" -l `"$pgLog`" start -w -t 30 > `"$logDir\pgctl_start_fallback.log`" 2>&1"
        Write-Log "Inicio manual de seguranca executado"
    }
    if (-not (Test-PostgresConnection -Retries 5 -DelaySeconds 3)) {
        Write-Log "ERRO: PostgreSQL nao subiu apos erro no servico"
        exit 1
    }
}

Write-Log ""
Write-Log "========================================"
Write-Log "CONFIGURACAO DO POSTGRESQL CONCLUIDA!"
Write-Log "========================================"
Write-Log "Host: localhost"
Write-Log "Porta: $DbPort"
Write-Log "Banco: $DbName"
Write-Log "Usuario: $DbUser"
Write-Log "Arquivo .env: $AppDir\.env"
Write-Log "Log de instalacao: $logFile"
Write-Log "========================================"

<#
.SYNOPSIS
    Backup da "nuvem local" (Supabase rodando na VM Ubuntu-Supabase).

.DESCRIPTION
    Gera um pacote .tar.gz com:
      - exodo_nuvem.dump  : pg_dump -Fc do banco "postgres" (todos os schemas)
      - docker-compose.yml e .env da stack Supabase (CONTEM SEGREDOS)
      - volumes/storage   : arquivos dos buckets

    O pacote e baixado para F:\Backups_NuvemLocal\<data_hora>\ e os backups
    mais antigos que -ManterDias sao apagados.

    Nao para a VM e nao altera nada: o pg_dump roda em paralelo ao uso normal.

.PARAMETER Destino
    Pasta onde os backups serao gravados. Padrao: F:\Backups_NuvemLocal

.PARAMETER ManterDias
    Quantos dias de backup manter. Padrao: 7

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1

.NOTES
    Requer: VM "Ubuntu-Supabase" rodando e chave SSH ~/.ssh/id_ed25519_vm.
    Restauracao: veja MIGRAR_NUVEM_LOCAL.md
#>
[CmdletBinding()]
param(
    [string]$Destino = 'F:\Backups_NuvemLocal',
    [int]$ManterDias = 7
)

$ErrorActionPreference = 'Stop'

$VBox       = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$Chave      = Join-Path $env:USERPROFILE '.ssh\id_ed25519_vm'
$SshHost    = 'charles@127.0.0.1'
$SshArgs    = @('-i', $Chave, '-p', '2222', '-o', 'BatchMode=yes',
                '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10')
$PastaVm    = '/home/charles/supabase'

function Write-Passo([string]$Texto) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Texto)
}

# ---------------------------------------------------------------------------
# 0) Pre-checagens
# ---------------------------------------------------------------------------
if (-not (Test-Path $Chave)) {
    throw "Chave SSH nao encontrada: $Chave"
}
if (-not (Test-Path $VBox)) {
    throw "VBoxManage nao encontrado: $VBox"
}

$estado = (& $VBox showvminfo 'Ubuntu-Supabase' --machinereadable 2>$null |
           Select-String '^VMState=').Line
if ($estado -notmatch 'running') {
    throw "A VM 'Ubuntu-Supabase' nao esta rodando ($estado). Suba a VM antes do backup."
}

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
try {
    # Pastas de backup contem chaves: restringe o acesso ao usuario atual.
    icacls $Destino /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" 2>$null | Out-Null
} catch { }

$ts        = Get-Date -Format 'yyyyMMdd_HHmmss'
$pasta     = Join-Path $Destino $ts
$tarRemoto = "/tmp/exodo_nuvem_$ts.tar.gz"
New-Item -ItemType Directory -Path $pasta -Force | Out-Null

# ---------------------------------------------------------------------------
# 1) Dump + pacote dentro da VM
# ---------------------------------------------------------------------------
Write-Passo "Gerando dump do banco e empacotando na VM..."

$remoto = @"
set -euo pipefail
cd $PastaVm
docker exec supabase-db pg_dump -U supabase_admin -d postgres -Fc > /tmp/exodo_nuvem.dump
tar czf $tarRemoto -C /tmp exodo_nuvem.dump -C $PastaVm docker-compose.yml .env volumes/storage
rm -f /tmp/exodo_nuvem.dump
stat -c '%s' $tarRemoto
"@

# Envia o script em base64: evita o CRLF que o ssh do Windows adiciona ao
# final do stream e que o bash interpretaria como parte dos nomes de arquivo.
$b64   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($remoto -replace "`r", '')))
$saida = ssh @SshArgs $SshHost "echo $b64 | base64 -d | bash -s" 2>&1
$linhaTamanho = ($saida | Where-Object { "$_" -match '^\d+$' } | Select-Object -Last 1)
if (-not $linhaTamanho) {
    throw "Falha ao gerar o backup na VM:`n$($saida -join "`n")"
}

# ---------------------------------------------------------------------------
# 2) Baixar para o Windows
# ---------------------------------------------------------------------------
Write-Passo "Baixando pacote ($([math]::Round([int64]$linhaTamanho / 1MB, 2)) MB)..."

$arquivo = Join-Path $pasta "nuvem_$ts.tar.gz"
scp -i $Chave -P 2222 -o BatchMode=yes -o StrictHostKeyChecking=no `
    "${SshHost}:$tarRemoto" $arquivo 2>&1 | Out-Null
if (-not (Test-Path $arquivo)) {
    throw "Falha no scp: o arquivo nao chegou em $arquivo"
}

ssh @SshArgs $SshHost "rm -f $tarRemoto" 2>&1 | Out-Null

# ---------------------------------------------------------------------------
# 3) Manifesto + hash
# ---------------------------------------------------------------------------
$info  = Get-Item $arquivo
# Get-FileHash depende de modulo que pode nao carregar; usa .NET direto.
$sha   = [System.Security.Cryptography.SHA256]::Create()
$fs    = [System.IO.File]::OpenRead($arquivo)
try {
    $hash = -join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') })
} finally {
    $fs.Close(); $sha.Dispose()
}
$texto = @"
Backup da nuvem local (Supabase / VM Ubuntu-Supabase)
Data............: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Arquivo.........: $($info.Name)
Tamanho.........: $($info.Length) bytes
SHA256..........: $hash

Conteudo do pacote:
  - exodo_nuvem.dump : pg_dump -Fc do banco "postgres" (usuario supabase_admin)
  - docker-compose.yml, .env : configuracao da stack (CONTEM SEGREDOS)
  - volumes/storage : arquivos dos buckets

Restauracao: MIGRAR_NUVEM_LOCAL.md (secao "Restaurar a nuvem")
"@
$texto | Set-Content -Path (Join-Path $pasta 'MANIFESTO.txt') -Encoding UTF8

# ---------------------------------------------------------------------------
# 4) Retencao
# ---------------------------------------------------------------------------
$limite = (Get-Date).AddDays(-$ManterDias)
Get-ChildItem $Destino -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{8}_\d{6}$' -and $_.CreationTime -lt $limite } |
    ForEach-Object {
        Write-Passo "Removendo backup antigo: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force
    }

Write-Passo ("Backup concluido: {0} ({1} MB)" -f $arquivo, [math]::Round($info.Length / 1MB, 2))

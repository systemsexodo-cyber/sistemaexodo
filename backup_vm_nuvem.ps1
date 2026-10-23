<#
.SYNOPSIS
    Backup COMPLETO da VM "Ubuntu-Supabase" (a nuvem local inteira).

.DESCRIPTION
    Diferente do backup_nuvem_local.ps1 (que salva dump + storage), este
    script salva a VM COMPLETA: disco, configuração e tudo mais. Serve para
    restaurar o SERVIDOR INTEIRO em outra máquina/disco se este PC morrer.

    Fluxo (a VM continua RODANDO, a loja nao para):
      1. tira um snapshot consistente do disco da VM (segundos);
      2. clona a VM a partir do snapshot para F:\Backups_VM\<nome>_<data>
         (full clone, standalone, com MACs originais preservados);
      3. apaga o snapshot da VM original (os writes voltam pro disco base);
      4. gera MANIFESTO.txt e apaga os backups mais antigos (retencao).

    Restaurar no PC novo:
      - VirtualBox instalado > Gerar > Importar Appliance... > escolher o
        Ubuntu-Supabase_<data>.vbox  (ou copiar a pasta e rodar
        "VBoxManage registervm <pasta>\<nome>.vbox");

.PARAMETER Destino
    Pasta onde os backups serao gravados. Padrao: F:\Backups_VM
    (precisa de ~16 GB livres por backup; mantem -ManterBackups por padrao 3).

.PARAMETER ManterBackups
    Quantos backups manter. Padrao: 3.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_vm_nuvem.ps1

.NOTES
    Requer: VirtualBox e a VM "Ubuntu-Supabase" registrada.
    Nao requer a VM estar parada; NAO funciona com a VM salva (saved state).
    Atencao: o backup vai para o MESMO disco (F:) onde vive o VDI original.
    Ele protege contra exclusao/correcao do VM, nao contra morte do disco.
#>
[CmdletBinding()]
param(
    [string]$Destino = 'F:\Backups_VM',
    [int]$ManterBackups = 3,
    [string]$NomeVm = 'Ubuntu-Supabase'
)

$ErrorActionPreference = 'Stop'

$VBox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

function Write-Passo([string]$Texto) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Texto)
}

# Executa o VBoxManage isolando stdout/stderr em arquivos temporarios.
# Motivo: o VBoxManage manda o progresso ("0%...100%") para o STDERR, e o
# PowerShell 5.1 converte aquilo em ErrorRecord - com $ErrorActionPreference
# = 'Stop' isso abortava o script no meio do snapshot. O exit code e a unica
# coisa confiavel.
function Invoke-VBox {
    param([string[]]$Argumentos)
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $VBox -ArgumentList $Argumentos `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $saida = @()
        if (Test-Path $outFile) { $saida += Get-Content $outFile -ErrorAction SilentlyContinue }
        if (Test-Path $errFile) { $saida += Get-Content $errFile -ErrorAction SilentlyContinue }
        [pscustomobject]@{ Codigo = $proc.ExitCode; Saida = $saida }
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 0) Pre-checagens
# ---------------------------------------------------------------------------
if (-not (Test-Path $VBox)) {
    throw "VBoxManage nao encontrado: $VBox"
}

$estado = (Invoke-VBox @('showvminfo', $NomeVm, '--machinereadable')).Saida |
          Select-String '^VMState=' | Select-Object -First 1
$estado = $estado.Line
if (-not $estado) {
    throw "VM '$NomeVm' nao encontrada no VirtualBox."
}
$rodando = $estado -match 'running'
if (-not $rodando -and $estado -notmatch 'poweroff|aborted') {
    throw "VM '$NomeVm' em estado '$estado'. So funciona com a VM rodando ou desligada."
}

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$livre = (Get-PSDrive -Name ($Destino.Substring(0,1))).Free
if ($livre -lt 20GB) {
    throw "Espaco insuficiente em $($Destino.Substring(0,1)): $([math]::Round($livre/1GB,1)) GB livre (minimo 20 GB)."
}

$ts    = Get-Date -Format 'yyyyMMdd_HHmmss'
$nome  = "${NomeVm}_bk_$ts"
$pasta = Join-Path $Destino $nome
if (Test-Path $pasta) { throw "A pasta de destino ja existe: $pasta" }

# ---------------------------------------------------------------------------
# 1) Snapshot (so se a VM estiver rodando; leva ~1s e nao derruba nada)
# ---------------------------------------------------------------------------
$snapshot = "backup_$ts"
if ($rodando) {
    Write-Passo "Tirando snapshot '$snapshot' da VM (a loja continua no ar)..."
    # as aspas em volta do valor sao obrigatorias: o Start-Process nao cita
    # argumentos com espaco e o VBoxManage partiria a descricao em dois.
    $r = Invoke-VBox @('snapshot', $NomeVm, 'take', $snapshot,
                       "--description=`"backup automatico $ts`"")
    if ($r.Codigo -ne 0) {
        throw "Falha ao tirar snapshot da VM (codigo $($r.Codigo)):`n$($r.Saida -join "`n")"
    }
}

# ---------------------------------------------------------------------------
# 2) Clone completo a partir do snapshot
# ---------------------------------------------------------------------------
# Nota: NAO usar --options=keepallmacs aqui: o VBox 7.2 rejeita (E_INVALIDARG).
# Sem essa opcao o clone recebe MACs novos - nao importa para backup; se um
# dia for restaurar no lugar do original, confira a reserva DHCP do roteador.
Write-Passo "Clonando a VM para $pasta (14 GB; pode levar varios minutos)..."
$inicio = Get-Date
$cloneArgs = @('clonevm', $NomeVm, '--mode=machine', "--name=$nome",
               "--basefolder=$Destino")
if ($rodando) { $cloneArgs += "--snapshot=$snapshot" }
try {
    $r = Invoke-VBox $cloneArgs
    if ($r.Codigo -ne 0) {
        throw "Falha no clone (codigo $($r.Codigo)):`n$($r.Saida -join "`n")"
    }
    $duracao = (Get-Date) - $inicio
} finally {
    # Sempre apagar o snapshot da VM original (funde os writes de volta no
    # disco base). Sem isto, um clone falho deixava o snapshot pendurado e o
    # disco divergente da VM crescendo sem limite.
    if ($rodando -and (Invoke-VBox @('snapshot', $NomeVm, 'list')).Saida -match $snapshot) {
        Write-Passo "Removendo o snapshot da VM original (funde os writes de volta)..."
        $rd = Invoke-VBox @('snapshot', $NomeVm, 'delete', $snapshot)
        if ($rd.Codigo -ne 0) {
            Write-Passo "AVISO: snapshot nao removido (codigo $($rd.Codigo)). rode: VBoxManage snapshot $NomeVm delete $snapshot"
        }
    }
    # Se o clone falhou no meio, apaga a pasta incompleta para nao poluir.
    if ($r -and $r.Codigo -ne 0 -and (Test-Path $pasta)) {
        Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 4) Backup FRIO + manifesto + retencao
# ---------------------------------------------------------------------------
# O clone herda o .sav do snapshot (estado da RAM no instante do backup, ~1,3
# GB). Sem ele a VM importada da um BOOT LIMPO a partir do disco (que ja esta
# consistente no ponto do snapshot) em vez de tentar retomar a RAM antiga.
$vboxFile = Join-Path $pasta "$nome.vbox"
if (Test-Path $vboxFile) {
    $xml = Get-Content $vboxFile -Raw
    $xmlNovo = $xml -replace '\s*stateFile="[^"]*"', ''
    if ($xmlNovo -ne $xml) {
        Set-Content -Path $vboxFile -Value $xmlNovo -Encoding UTF8
        Get-ChildItem (Join-Path $pasta 'Snapshots') -Filter '*.sav' -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Write-Passo "Estado de memoria removido (backup frio; boot limpo na importacao)."
    }
}
if (-not (Test-Path $vboxFile)) {
    throw "Clone incompleto: $vboxFile nao encontrado. Apague $pasta e tente de novo."
}
$tamanho = (Get-ChildItem $pasta -Recurse -File | Measure-Object -Sum Length).Sum
$texto = @"
Backup COMPLETO da VM da nuvem local (Supabase)
Data............: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
VM..............: $NomeVm (estado: $estado)
Pasta...........: $pasta
Tamanho.........: $([math]::Round($tamanho/1GB,2)) GB em $(((Get-ChildItem $pasta -File).Count) + ((Get-ChildItem $pasta -Directory).Count)) itens
Duracao clone...: $([math]::Round($duracao.TotalMinutes,1)) min

RESTAURAR em outra maquina:
  1. Instale o VirtualBox.
  2. Gerar > Importar Appliance... > aponte para:
       $vboxFile
  3. Conferir as portas NAT (8001->8000, 5434->5432, 6543->6543, 2222->22).
  4. Inicie a VM e espere http://localhost:8001/rest/v1/ responder 200.

Este backup protege contra exclusao/correcao da VM. NAO protege contra
morte do DISCO F: (o VDI original e este backup moram no mesmo disco).
Mantenha tambem o dump (backup_nuvem_local.ps1) copiado para fora do PC.
"@
$texto | Set-Content -Path (Join-Path $pasta 'MANIFESTO.txt') -Encoding UTF8
Write-Passo "Manifesto gravado."

$antigos = Get-ChildItem $Destino -Directory |
    Where-Object { $_.Name -like "${NomeVm}_bk_*" } |
    Sort-Object Name
if ($antigos.Count -gt $ManterBackups) {
    $antigos | Select-Object -First ($antigos.Count - $ManterBackups) | ForEach-Object {
        Write-Passo "Removendo backup antigo: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force
    }
}

Write-Passo ("Backup da VM concluido: {0} ({1} GB, {2} min)." -f
    $pasta, [math]::Round($tamanho/1GB,2), [math]::Round($duracao.TotalMinutes,1))

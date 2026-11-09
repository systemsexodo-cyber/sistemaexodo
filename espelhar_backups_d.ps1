<#
.SYNOPSIS
    Mantem o disco D: com os mesmos backups dos discos C: e F:.

.DESCRIPTION
    Roda depois dos backups automaticos e:
      - copia C:\ExodoBackups para D:\ExodoBackups_App;
      - copia dumps faltantes de F:\ExodoBackups para D:\ExodoBackups;
      - confere se o backup da nuvem local e o clone da VM chegaram em D:.

    Nunca apaga nada. Log em D:\Backups_Logs\espelhamento.log.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\espelhar_backups_d.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$LogDir  = 'D:\Backups_Logs'
$LogFile = Join-Path $LogDir 'espelhamento.log'

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Mensagem)
    $linha = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensagem
    Write-Host $linha
    Add-Content -Path $LogFile -Value $linha
}

function Invoke-Robocopy {
    param(
        [string]$Origem,
        [string]$Destino,
        [string[]]$Excluir = @()
    )

    if (-not (Test-Path $Origem)) {
        Write-Log "ORIGEM AUSENTE: $Origem"
        return
    }
    if (-not (Test-Path $Destino)) {
        New-Item -ItemType Directory -Path $Destino -Force | Out-Null
    }

    $roboArgs = @($Origem, $Destino, '/E', '/XO', '/R:1', '/W:1',
                  '/NFL', '/NDL', '/NJH', '/NJS')
    if ($Excluir.Count -gt 0) {
        $roboArgs += '/XF'
        $roboArgs += $Excluir
    }

    $saida  = & robocopy @roboArgs
    $codigo = $LASTEXITCODE

    if ($codigo -ge 8) {
        Write-Log "ERRO robocopy ($codigo): $Origem -> $Destino"
        $saida | Add-Content -Path $LogFile
    } else {
        Write-Log "OK robocopy ($codigo): $Origem -> $Destino"
    }
}

function Get-UltimaPasta {
    param([string]$Caminho, [string]$Filtro)
    if (-not (Test-Path $Caminho)) { return $null }
    return Get-ChildItem $Caminho -Directory -Filter $Filtro -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1
}

if (-not (Test-Path 'D:\')) {
    Write-Log 'DISCO D: NAO DISPONIVEL - espelhamento cancelado.'
    exit 1
}

Write-Log '=== Inicio do espelhamento para D: ==='

# 1) Backups gerados pelo aplicativo (C:) -> D:
Invoke-Robocopy -Origem 'C:\ExodoBackups' -Destino 'D:\ExodoBackups_App'

# 2) Dumps do PostgreSQL local: garante em D: os que faltarem em F:
Invoke-Robocopy -Origem 'F:\ExodoBackups' -Destino 'D:\ExodoBackups' `
    -Excluir @('backup_info.json', 'backup_log.txt')

# 3) Nuvem local: confere se a tarefa BackupNuvemLocal_D esta gravando em D:
$nuvemF = Get-UltimaPasta 'F:\Backups_NuvemLocal' '2026*'
$nuvemD = Get-UltimaPasta 'D:\Backups_NuvemLocal' '2026*'
if ($nuvemF) { Write-Log "Nuvem F: ultimo pacote $($nuvemF.Name)" }
else         { Write-Log 'Nuvem F: NENHUM pacote encontrado' }
if ($nuvemD) { Write-Log "Nuvem D: ultimo pacote $($nuvemD.Name)" }
else         { Write-Log 'Nuvem D: NENHUM pacote encontrado' }
if ($nuvemF -and $nuvemD -and $nuvemD.Name.Substring(0, 8) -lt $nuvemF.Name.Substring(0, 8)) {
    Write-Log 'AVISO: backup da nuvem em D esta mais antigo que o de F. Verifique a tarefa BackupNuvemLocal_D.'
}

# 4) VM: confere se a tarefa BackupVMNuvem_D esta clonando em D:
$vmF = Get-UltimaPasta 'F:\Backups_VM' 'Ubuntu-Supabase_bk_*'
$vmD = Get-UltimaPasta 'D:\Backups_VM' 'Ubuntu-Supabase_bk_*'
if ($vmF) { Write-Log "VM F: ultimo clone $($vmF.Name)" }
else      { Write-Log 'VM F: NENHUM clone encontrado' }
if ($vmD) { Write-Log "VM D: ultimo clone $($vmD.Name)" }
else      { Write-Log 'VM D: NENHUM clone encontrado' }
if ($vmF -and $vmD -and $vmD.Name -lt $vmF.Name) {
    Write-Log 'AVISO: clone da VM em D esta mais antigo que o de F. Verifique a tarefa BackupVMNuvem_D.'
}

Write-Log '=== Fim do espelhamento ==='

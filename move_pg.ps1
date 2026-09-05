$ErrorActionPreference = 'Continue'
$dest = 'C:Program FilesPostgreSQL_removido_bak_20260802'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$out = @()
if (Test-Path 'C:Program FilesPostgreSQL') { Move-Item 'C:Program FilesPostgreSQL' "$dest" -Force; $out += '15-movido' } else { $out += '15-inexistente' }
if (Test-Path 'C:Program FilesPostgreSQL8') { Move-Item 'C:Program FilesPostgreSQL8' "$dest8" -Force; $out += '18-movido' } else { $out += '18-inexistente' }
$rest = Get-ChildItem 'C:Program FilesPostgreSQL' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$out += 'restante: ' + ($rest -join ', ')
$out += 'destino: ' + ((Get-ChildItem $dest | Select-Object -ExpandProperty Name) -join ', ')
Set-Content -Path 'C:Program Filespg_move_result.txt' -Value ($out -join ' | ')

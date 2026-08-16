$ErrorActionPreference = 'Continue'
$log = 'C:Userscharles.antigravitysistema_exodo_15-04-2026elev_result.txt'
try {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:Userscharles.antigravitysistema_exodo_15-04-2026move_pg.ps1' -ErrorAction Stop
    Set-Content -Path $log -Value 'ELEVACAO-OK'
} catch {
    Set-Content -Path $log -Value ('ERRO: ' + $_.Exception.Message)
}

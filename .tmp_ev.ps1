$desde = (Get-Date).AddMinutes(-25)
$eventos = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$desde} -ErrorAction SilentlyContinue
$alvo = $eventos | Where-Object { $_.Message -match 'xenia' }
if (-not $alvo) { Write-Output 'NENHUM EVENTO COM XENIA NOS ULTIMOS 25 MIN' } else {
  foreach ($e in $alvo) {
    Write-Output ('--- ' + $e.TimeCreated.ToString('HH:mm:ss') + ' | ' + $e.Id + ' | ' + $e.ProviderName + ' ---')
    Write-Output $e.Message
    Write-Output ''
  }
}
Write-Output '=== erros criticos recentes (qualquer app) ==='
$eventos | Where-Object { $_.LevelDisplayName -in @('Erro','Critical') -or $_.Id -in @(1000,1001,4101) } | Select-Object -First 6 | ForEach-Object {
  Write-Output ('* ' + $_.TimeCreated.ToString('HH:mm:ss') + ' [' + $_.Id + '] ' + $_.ProviderName + ' :: ' + (($_.Message -split "`n")[0]))
}

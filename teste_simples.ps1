# SCRIPT DE DIAGNÓSTICO
Write-Host "Iniciando script..." -ForegroundColor Green
$branch = git branch --show-current
Write-Host "Branch atual detectada: $branch" -ForegroundColor Yellow
$msg = Read-Host "Se você consegue ler isso, digite algo e dê ENTER"
Write-Host "Você digitou: $msg"
Read-Host "Pressione ENTER para fechar"

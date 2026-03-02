# 📅 Script para Agendar o Envio Automático de XMLs para Contabilidade
# Este script cria uma Tarefa Agendada no Windows para rodar todo dia às 23:00.

$ProjectRoot = Get-Location
$ScriptPath = Join-Path $ProjectRoot "enviar_xmls_contabilidade.ps1"
$TaskName = "Exodo_Envio_XML_Contabilidade"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   AGENDANDO ENVIO AUTOMÁTICO DE XMLs" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

if (-not (Test-Path $ScriptPath)) {
    Write-Host "[ERRO] Script $ScriptPath não encontrado!" -ForegroundColor Red
    exit
}

# Comando para rodar o PowerShell com esse script
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
# Gatilho: Diariamente às 23:00
$Trigger = New-ScheduledTaskTrigger -Daily -At 11pm
# Configurações: Rodar mesmo se não estiver logado (opcional, aqui vamos manter simples)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Write-Host "[1/2] Criando tarefa agendada '$TaskName'..." -ForegroundColor Yellow

try {
    Register-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -TaskName $TaskName -Description "Gera ZIP e envia XMLs de NFC-e para o Google Drive da Contabilidade todo dia." -Force
    Write-Host "✅ Tarefa agendada com sucesso!" -ForegroundColor Green
}
catch {
    Write-Host "[ERRO] Falha ao registrar tarefa: $_" -ForegroundColor Red
    Write-Host "DICA: Tente rodar este script como Administrador."
}

Write-Host ""
Write-Host "[2/2] Testando o envio agora para garantir que tudo funciona..." -ForegroundColor Yellow
& $ScriptPath

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Agendamento concluído. Os XMLs serão enviados diariamente."
Write-Host "Você pode ver a tarefa no 'Agendador de Tarefas' do Windows."
Write-Host "===============================================" -ForegroundColor Cyan
# pause

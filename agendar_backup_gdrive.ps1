# ============================================================
# AGENDAMENTO AUTOMÁTICO DE BACKUP (GOOGLE DRIVE)
# ============================================================
# Este script configura o Windows para rodar o backup do seu
# projeto todos os dias em um horário específico.
# ============================================================

$projectPath = $PSScriptRoot
if (-not $projectPath) { $projectPath = Get-Location }

$scriptPath = Join-Path $projectPath "backup_projeto_gdrive_automatico.ps1"
$taskName = "Backup_SistemaExodo_GDrive"
$startTime = "07:00" # Horário ajustado conforme pedido: 07:00 da manhã

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURANDO BACKUP AUTOMÁTICO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Verificar se o script de backup existe
if (-not (Test-Path $scriptPath)) {
    Write-Host "!!! ERRO: Script de backup não encontrado em: $scriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nEste script irá criar uma tarefa no Windows para:"
Write-Host "- Rodar TODO DIA às $startTime"
Write-Host "- Local: $scriptPath"
Write-Host ""

$confirm = Read-Host "Deseja prosseguir com o agendamento? (S/N)"
if ($confirm -ne 's' -and $confirm -ne 'S') {
    Write-Host "Cancelado pelo usuário."
    exit
}

# 2. Criar a ação da tarefa
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# 3. Criar o gatilho (diário)
$trigger = New-ScheduledTaskTrigger -Daily -At $startTime

# 4. Configurações da tarefa
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# 5. Registrar a tarefa
try {
    # Remover se já existir
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Realiza o backup automático do código do Sistema Exodo para o Google Drive." `
        -Force
        
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  ✅ AGENDAMENTO CONCLUÍDO COM SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "O backup rodará automaticamente todos os dias às $startTime."
    Write-Host "Você pode ver e gerenciar a tarefa no 'Agendador de Tarefas' do Windows."
}
catch {
    Write-Host "`n!!! ERRO ao criar tarefa: $_" -ForegroundColor Red
    Write-Host "DICA: Tente rodar este script (VS Code) como ADMINISTRADOR." -ForegroundColor Yellow
}

Write-Host "`nPressione qualquer tecla para sair..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

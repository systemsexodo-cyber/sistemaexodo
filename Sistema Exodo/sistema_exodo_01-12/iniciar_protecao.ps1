# ============================================================
# INICIAR SISTEMA DE PROTEÇÃO E SALVAMENTO AUTOMÁTICO
# ============================================================
# Este script inicia o sistema de salvamento inteligente
# em uma janela minimizada
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INICIANDO SISTEMA DE PROTEÇÃO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do script
if ($PSScriptRoot) {
    $scriptPath = Join-Path $PSScriptRoot "salvamento_inteligente.ps1"
    $projectPath = Split-Path $PSScriptRoot -Parent
} else {
    $scriptPath = Join-Path (Get-Location).Path "salvamento_inteligente.ps1"
    $projectPath = (Get-Location).Path
}

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERRO: Script não encontrado: $scriptPath" -ForegroundColor Red
    exit 1
}

# Verificar se é repositório Git e garantir que está na branch modo-dev
$gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    Set-Location $gitCheck
    $currentBranch = git branch --show-current 2>$null
    
    if ($currentBranch -ne "modo-dev") {
        Write-Host "Mudando para branch modo-dev..." -ForegroundColor Yellow
        $checkoutResult = git checkout modo-dev 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "AVISO: Não foi possível mudar para modo-dev. Continuando na branch atual: $currentBranch" -ForegroundColor Yellow
        } else {
            Write-Host "OK: Agora na branch modo-dev" -ForegroundColor Green
        }
        Write-Host ""
    } else {
        Write-Host "OK: Já está na branch modo-dev" -ForegroundColor Green
        Write-Host ""
    }
    
    # Fazer commit inicial se houver alterações
    Write-Host "Verificando alterações pendentes..." -ForegroundColor Yellow
    $status = git status --porcelain 2>&1
    if ($status) {
        Write-Host "Alterações encontradas. Fazendo commit inicial..." -ForegroundColor Cyan
        
        # Remover arquivos grandes do staging antes de commitar
        $largeFiles = git ls-files | Where-Object {
            $file = $_
            if (Test-Path $file) {
                $size = (Get-Item $file -ErrorAction SilentlyContinue).Length
                ($file -like "*.zip") -and ($size -gt 50MB)
            } else {
                $false
            }
        }
        
        if ($largeFiles) {
            Write-Host "Removendo arquivos ZIP grandes do staging..." -ForegroundColor Yellow
            $largeFiles | ForEach-Object {
                git rm --cached $_ 2>&1 | Out-Null
            }
        }
        
        # Adicionar alterações (exceto arquivos grandes)
        git add . 2>&1 | Out-Null
        
        # Fazer commit
        $commitMsg = "Salvamento automático - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $commitResult = git commit --no-verify -m $commitMsg 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Commit inicial realizado com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "AVISO: Não foi possível fazer commit inicial" -ForegroundColor Yellow
        }
        Write-Host ""
        
        # Testar push limpo
        Write-Host "Testando push limpo..." -ForegroundColor Yellow
        $pushTest = git push origin modo-dev --no-verify 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Push testado com sucesso! Sistema funcionando corretamente." -ForegroundColor Green
        } else {
            if ($pushTest -match "exceeds.*file size limit") {
                Write-Host "AVISO: Ainda há arquivos grandes no histórico remoto." -ForegroundColor Yellow
                Write-Host "O sistema usará push limpo automaticamente." -ForegroundColor Gray
            } else {
                Write-Host "AVISO: Push falhou, mas o sistema continuará tentando." -ForegroundColor Yellow
            }
        }
        Write-Host ""
    } else {
        Write-Host "Nenhuma alteração pendente." -ForegroundColor Green
        Write-Host ""
    }
}

Write-Host "Iniciando salvamento inteligente..." -ForegroundColor Yellow
Write-Host "  - Commit automático: a cada 5 minutos" -ForegroundColor Gray
Write-Host "  - Push automático: a cada 10 minutos" -ForegroundColor Gray
Write-Host "  - Backups automáticos antes de cada operação" -ForegroundColor Gray
Write-Host "  - Push limpo (sem arquivos grandes)" -ForegroundColor Gray
Write-Host ""

# Iniciar em janela minimizada
$scriptFullPath = Resolve-Path $scriptPath
Start-Process powershell.exe -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptFullPath`"" -WindowStyle Minimized

Write-Host "========================================" -ForegroundColor Green
Write-Host "  SISTEMA INICIADO COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "O script está rodando em background (janela minimizada)." -ForegroundColor Yellow
Write-Host ""
Write-Host "Para parar:" -ForegroundColor Cyan
Write-Host "  - Feche a janela PowerShell minimizada na barra de tarefas" -ForegroundColor White
Write-Host "  - Ou pressione Ctrl+C na janela do script" -ForegroundColor White
Write-Host ""
Write-Host "Para verificar logs:" -ForegroundColor Cyan
Write-Host "  Get-Content .salvamento_logs\sessao.log" -ForegroundColor White
Write-Host ""


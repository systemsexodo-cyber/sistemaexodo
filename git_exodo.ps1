function Show-Header {
    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Host "         SISTEMA EXODO - GERENCIADOR GIT PROFISSIONAL     " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
}

function Show-Menu {
    Write-Host "`nBranch Atual: " -NoNewline; Write-Host "$(git branch --show-current)" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "1. [AUTO] Salvar e Enviar tudo (Add + Commit + Push)" -ForegroundColor Green
    Write-Host "2. Sincronizar (Pull + Merge)" -ForegroundColor White
    Write-Host "3. Ver Status Detalhado" -ForegroundColor White
    Write-Host "4. Trocar de Branch" -ForegroundColor White
    Write-Host "5. Criar Nova Branch" -ForegroundColor White
    Write-Host "6. Preparar Deploy (Merge para Main)" -ForegroundColor Magenta
    Write-Host "Q. Sair" -ForegroundColor Red
    Write-Host ""
}

function Get-CommitMessage {
    Write-Host "`nTipo de alteracao:" -ForegroundColor Yellow
    Write-Host "1. Feat | 2. Fix | 3. Docs | 4. Style | 5. Refactor | 6. Perf | 7. Chore"
    $typeChoice = Read-Host "Escolha o numero (Padrao: 7)"
    
    $prefix = switch($typeChoice) {
        "1" { "feat: " }
        "2" { "fix: " }
        "3" { "docs: " }
        "4" { "style: " }
        "5" { "refactor: " }
        "6" { "perf: " }
        default { "chore: " }
    }

    $msg = Read-Host "Descreva o que foi feito"
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "alteracoes automaticas $((Get-Date).ToString('yyyy-MM-dd HH:mm'))" }
    return "$prefix$msg"
}

function Invoke-GitAutoPush {
    Write-Host "`n>>> Analisando arquivos grandes..." -ForegroundColor Yellow
    $largeFiles = Get-ChildItem -Recurse -File | Where-Object { $_.Length -gt 50MB -and $_.FullName -notmatch ".git|node_modules|build" }
    if ($largeFiles) {
        Write-Host "!!! ATENCAO: Arquivos > 50MB detectados!" -ForegroundColor Red
        $largeFiles | ForEach-Object { Write-Host "  - $($_.Name)" }
        $confirm = Read-Host "Continuar? (s/N)"
        if ($confirm -ne 's') { return }
    }

    Write-Host ">>> Rodando Flutter Analyze..." -ForegroundColor Yellow
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        $confirm = Read-Host "Foram encontrados avisos. Continuar mesmo assim? (s/N)"
        if ($confirm -ne 's') { return }
    }

    git add .
    $fullMsg = Get-CommitMessage
    git commit -m "$fullMsg"
    
    $branch = git branch --show-current
    Write-Host ">>> Enviando para origin/$branch..." -ForegroundColor Cyan
    git push origin $branch
    if ($LASTEXITCODE -eq 0) { Write-Host "v SUCESSO!" -ForegroundColor Green }
}

# --- LOOP PRINCIPAL ---
$exit = $false
while (-not $exit) {
    Show-Header
    Show-Menu
    $choice = Read-Host "Sua opcao"

    switch ($choice) {
        "1" { Invoke-GitAutoPush }
        "2" { git pull origin $(git branch --show-current) }
        "3" { git status; git log --oneline -n 5 }
        "4" { 
            git branch
            $newBranch = Read-Host "Mudar para qual branch?"
            git checkout $newBranch
        }
        "5" {
            $name = Read-Host "Nome da nova branch"
            git checkout -b $name
        }
        "6" {
            $current = git branch --show-current
            git checkout main
            git merge $current
            git push origin main
            git checkout $current
            Write-Host "v Deploy pronto!" -ForegroundColor Green
        }
        "q" { $exit = $true }
        "Q" { $exit = $true }
        default { Write-Host "Opcao invalida" -ForegroundColor Red }
    }
    
    if (-not $exit) {
        Write-Host "`nPreressione ENTER para continuar..."
        [void][System.Console]::ReadLine()
    }
}

Write-Host "Ate logo!" -ForegroundColor Cyan

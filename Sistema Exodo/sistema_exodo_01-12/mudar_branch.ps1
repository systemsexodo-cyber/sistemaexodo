# ============================================================
# SCRIPT PARA MUDAR DE BRANCH COM SEGURANÇA
# ============================================================
# Este script facilita a mudança de branch, salvando
# automaticamente alterações não commitadas antes de mudar
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$BranchDestino
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MUDANDO DE BRANCH" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Detectar diretório do projeto
if ($PSScriptRoot) {
    $projectPath = $PSScriptRoot
} else {
    $projectPath = (Get-Location).Path
}

# Encontrar repositório Git
$gitCheck = git -C $projectPath rev-parse --show-toplevel 2>$null
if ($gitCheck) {
    Set-Location $gitCheck
} else {
    Write-Host "ERRO: Nao e um repositorio Git valido!" -ForegroundColor Red
    exit 1
}

# Verificar branch atual
$branchAtual = git branch --show-current 2>$null
Write-Host "Branch atual: $branchAtual" -ForegroundColor Yellow
Write-Host "Branch destino: $BranchDestino" -ForegroundColor Yellow
Write-Host ""

# Verificar se já está na branch destino
if ($branchAtual -eq $BranchDestino) {
    Write-Host "Voce ja esta na branch $BranchDestino!" -ForegroundColor Green
    exit 0
}

# Verificar se a branch existe
$branchExiste = git branch -a | Select-String "^\s*$BranchDestino$|remotes/.*/$BranchDestino$"
if (-not $branchExiste) {
    Write-Host "AVISO: Branch '$BranchDestino' nao encontrada." -ForegroundColor Yellow
    $criar = Read-Host "Deseja criar a branch? (S/N)"
    if ($criar -eq "S" -or $criar -eq "s") {
        Write-Host "Criando branch $BranchDestino..." -ForegroundColor Yellow
        git checkout -b $BranchDestino 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Branch criada e ativada com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "ERRO ao criar branch!" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Operacao cancelada." -ForegroundColor Yellow
        exit 0
    }
    exit 0
}

# Verificar se há alterações não commitadas
Write-Host "Verificando alteracoes pendentes..." -ForegroundColor Yellow
$status = git status --porcelain 2>$null

if ($status) {
    Write-Host "Alteracoes nao commitadas encontradas:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    
    Write-Host "Opcoes:" -ForegroundColor Cyan
    Write-Host "  1. Fazer stash (salvar temporariamente)" -ForegroundColor White
    Write-Host "  2. Descartar alteracoes" -ForegroundColor White
    Write-Host "  3. Fazer commit antes de mudar" -ForegroundColor White
    Write-Host "  4. Cancelar" -ForegroundColor White
    Write-Host ""
    
    $opcao = Read-Host "Escolha uma opcao (1-4)"
    
    switch ($opcao) {
        "1" {
            Write-Host "Fazendo stash das alteracoes..." -ForegroundColor Yellow
            git stash push -m "Stash antes de mudar para $BranchDestino - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Alteracoes salvas no stash!" -ForegroundColor Green
            } else {
                Write-Host "ERRO ao fazer stash!" -ForegroundColor Red
                exit 1
            }
        }
        "2" {
            Write-Host "AVISO: Descartando todas as alteracoes nao commitadas!" -ForegroundColor Red
            $confirmar = Read-Host "Tem certeza? (S/N)"
            if ($confirmar -eq "S" -or $confirmar -eq "s") {
                git restore .
                git clean -fd
                Write-Host "Alteracoes descartadas!" -ForegroundColor Yellow
            } else {
                Write-Host "Operacao cancelada." -ForegroundColor Yellow
                exit 0
            }
        }
        "3" {
            Write-Host "Fazendo commit das alteracoes..." -ForegroundColor Yellow
            git add .
            $mensagem = Read-Host "Mensagem do commit (ou Enter para usar padrao)"
            if ([string]::IsNullOrWhiteSpace($mensagem)) {
                $mensagem = "Alteracoes antes de mudar para $BranchDestino - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            }
            git commit -m $mensagem --no-verify
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Commit realizado com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "ERRO ao fazer commit!" -ForegroundColor Red
                exit 1
            }
        }
        "4" {
            Write-Host "Operacao cancelada." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Opcao invalida. Operacao cancelada." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host ""
}

# Mudar para a branch destino
Write-Host "Mudando para branch $BranchDestino..." -ForegroundColor Yellow
$checkoutResult = git checkout $BranchDestino 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  MUDANCA DE BRANCH REALIZADA!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Branch atual: $BranchDestino" -ForegroundColor Cyan
    Write-Host ""
    
    # Verificar se há stash para aplicar
    $stashList = git stash list 2>$null
    if ($stashList) {
        Write-Host "AVISO: Ha alteracoes salvas no stash." -ForegroundColor Yellow
        Write-Host "Para aplicar: git stash pop" -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERRO AO MUDAR DE BRANCH!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhes do erro:" -ForegroundColor Red
    Write-Host $checkoutResult -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "✅ Processo concluído!" -ForegroundColor Green
Write-Host ""





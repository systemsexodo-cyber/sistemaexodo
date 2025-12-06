# ============================================================
# CONFIGURAÇÃO COMPLETA DO PROJETO
# ============================================================
# Este script executa todos os scripts importantes para
# proteger e configurar seu projeto automaticamente
# ============================================================

# Cores para output
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Detail { param($msg) Write-Host $msg -ForegroundColor Gray }

Write-Info "========================================"
Write-Info "  CONFIGURAÇÃO COMPLETA DO PROJETO"
Write-Info "========================================"
Write-Info ""
Write-Info "Este script vai configurar tudo que é necessário"
Write-Info "para proteger seu projeto automaticamente."
Write-Info ""
Write-Warning "Pressione Enter para continuar ou Ctrl+C para cancelar..."
Read-Host

# Detectar diretório do script
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} else {
    $scriptDir = (Get-Location).Path
}

Set-Location $scriptDir

# 1. Verificar/Configurar Git
Write-Info ""
Write-Info "========================================"
Write-Info "  [1/5] CONFIGURANDO GIT"
Write-Info "========================================"
Write-Info ""

$gitNome = git config --global user.name 2>$null
$gitEmail = git config --global user.email 2>$null

if ([string]::IsNullOrWhiteSpace($gitNome) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
    Write-Warning "Git não está configurado. Configurando agora..."
    if (Test-Path "configurar_git.ps1") {
        & ".\configurar_git.ps1"
    } else {
        Write-Error "Script configurar_git.ps1 não encontrado!"
        Write-Info "Configure manualmente:"
        Write-Detail "  git config --global user.name 'Seu Nome'"
        Write-Detail "  git config --global user.email 'seu@email.com'"
    }
} else {
    Write-Success "Git já está configurado:"
    Write-Detail "  Nome: $gitNome"
    Write-Detail "  Email: $gitEmail"
}

# 2. Configurar Proteções Automáticas
Write-Info ""
Write-Info "========================================"
Write-Info "  [2/5] CONFIGURANDO PROTEÇÕES"
Write-Info "========================================"
Write-Info ""

if (Test-Path "protecao_automatica.ps1") {
    Write-Info "Configurando hooks de proteção..."
    & ".\protecao_automatica.ps1"
    Write-Success "Proteções configuradas!"
} else {
    Write-Warning "Script protecao_automatica.ps1 não encontrado!"
}

# 3. Criar Ponto de Restauração Inicial
Write-Info ""
Write-Info "========================================"
Write-Info "  [3/5] CRIANDO PONTO DE RESTAURAÇÃO"
Write-Info "========================================"
Write-Info ""

if (Test-Path "criar_ponto_restauracao.ps1") {
    Write-Info "Criando ponto de restauração inicial..."
    Write-Detail "Nome: 'Configuração inicial do projeto'"
    
    # Criar ponto automaticamente sem interação
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $pontosDir = Join-Path $scriptDir ".pontos_restauracao"
    if (-not (Test-Path $pontosDir)) {
        New-Item -ItemType Directory -Path $pontosDir -Force | Out-Null
    }
    
    $pontoDir = Join-Path $pontosDir "RESTORE_$timestamp"
    New-Item -ItemType Directory -Path $pontoDir -Force | Out-Null
    
    # Salvar informações
    $commitHash = git rev-parse HEAD 2>$null
    $infoFile = Join-Path $pontoDir "info.txt"
    @"
========================================
PONTO DE RESTAURAÇÃO
========================================
Nome: Configuração inicial do projeto
Tag: RESTORE_$timestamp
Data/Hora: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Commit Hash: $commitHash

Criado automaticamente durante configuração inicial.

========================================
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    
    # Criar bundle (pode ser grande, então opcional)
    Write-Detail "  Criando backup do repositório..."
    $bundleFile = Join-Path $pontoDir "repositorio.bundle"
    git bundle create $bundleFile --all 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        $bundleSize = (Get-Item $bundleFile).Length / 1MB
        Write-Success "  Ponto criado: $([math]::Round($bundleSize, 2)) MB"
    } else {
        Write-Warning "  Bundle não criado (pode ser grande), mas ponto foi salvo"
    }
    
    # Salvar no índice
    $indiceFile = Join-Path $pontosDir "indice.json"
    $pontos = @()
    if (Test-Path $indiceFile) {
        try {
            $conteudo = Get-Content $indiceFile -Raw | ConvertFrom-Json
            $pontos = $conteudo
        } catch { }
    }
    
    $novoPonto = @{
        tag = "RESTORE_$timestamp"
        nome = "Configuração inicial do projeto"
        data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        commitHash = $commitHash
        caminho = $pontoDir
    }
    
    $pontos += $novoPonto
    $pontos | ConvertTo-Json -Depth 10 | Out-File -FilePath $indiceFile -Encoding UTF8
    
    Write-Success "Ponto de restauração criado!"
} else {
    Write-Warning "Script criar_ponto_restauracao.ps1 não encontrado!"
}

# 4. Verificar se há alterações não salvas
Write-Info ""
Write-Info "========================================"
Write-Info "  [4/5] VERIFICANDO ALTERAÇÕES"
Write-Info "========================================"
Write-Info ""

$status = git status --porcelain 2>$null
if ($status) {
    Write-Warning "Há alterações não salvas!"
    Write-Info "Deseja salvar agora? (s/n)"
    $salvar = Read-Host
    
    if ($salvar -eq "s" -or $salvar -eq "S") {
        if (Test-Path "salvar_alteracoes.ps1") {
            Write-Info "Salvando alterações..."
            & ".\salvar_alteracoes.ps1"
        } else {
            Write-Info "Fazendo commit manual..."
            git add -A
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            git commit -m "Salvamento automático - $timestamp"
        }
    }
} else {
    Write-Success "Nenhuma alteração pendente - tudo salvo!"
}

# 5. Iniciar Sistema de Proteção
Write-Info ""
Write-Info "========================================"
Write-Info "  [5/5] INICIANDO SISTEMA DE PROTEÇÃO"
Write-Info "========================================"
Write-Info ""

Write-Info "Deseja iniciar o salvamento automático em tempo real? (s/n)"
Write-Detail "  Isso vai monitorar e salvar alterações automaticamente"
$iniciar = Read-Host

if ($iniciar -eq "s" -or $iniciar -eq "S") {
    if (Test-Path "iniciar_protecao.ps1") {
        Write-Info "Iniciando sistema de proteção..."
        & ".\iniciar_protecao.ps1"
    } else {
        Write-Warning "Script iniciar_protecao.ps1 não encontrado!"
        Write-Info "Execute manualmente:"
        Write-Detail "  .\salvamento_tempo_real.ps1"
    }
} else {
    Write-Info "Sistema de proteção não iniciado."
    Write-Info "Para iniciar depois, execute:"
    Write-Detail "  .\iniciar_protecao.ps1"
}

# Resumo final
Write-Info ""
Write-Success "========================================"
Write-Success "  CONFIGURAÇÃO CONCLUÍDA!"
Write-Success "========================================"
Write-Info ""
Write-Info "Resumo do que foi configurado:"
Write-Info "  ✓ Git configurado"
Write-Info "  ✓ Proteções automáticas ativadas"
Write-Info "  ✓ Ponto de restauração criado"
Write-Info "  ✓ Alterações verificadas"
Write-Info ""
Write-Info "Scripts importantes disponíveis:"
Write-Detail "  .\iniciar_protecao.ps1          - Iniciar salvamento automático"
Write-Detail "  .\criar_ponto_restauracao.ps1   - Criar ponto de restauração"
Write-Detail "  .\restaurar_ponto.ps1           - Restaurar ponto"
Write-Detail "  .\backup_completo.ps1           - Backup completo"
Write-Info ""
Write-Success "Seu projeto está protegido!"
Write-Info ""



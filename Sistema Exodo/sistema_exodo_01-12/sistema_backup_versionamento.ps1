# Sistema de Backup e Versionamento - Sistema Exodo
# Cria backups completos e permite restaurar versões anteriores

param(
    [string]$Acao = "backup",  # backup, restaurar, listar
    [string]$VersaoId = ""      # ID da versão para restaurar
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projetoDir = $scriptDir
$backupBaseDir = Join-Path $scriptDir ".backups_versionamento"
$versoesDir = Join-Path $backupBaseDir "versoes"
$indiceFile = Join-Path $backupBaseDir "indice_versoes.json"

# Criar diretórios se não existirem
if (-not (Test-Path $backupBaseDir)) {
    New-Item -ItemType Directory -Path $backupBaseDir -Force | Out-Null
}
if (-not (Test-Path $versoesDir)) {
    New-Item -ItemType Directory -Path $versoesDir -Force | Out-Null
}

# Função para criar backup
function Criar-Backup {
    Write-Host "`n=== CRIANDO BACKUP DO SISTEMA ===" -ForegroundColor Cyan
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $versaoId = "v_$timestamp"
    $versaoDir = Join-Path $versoesDir $versaoId
    
    Write-Host "Versão: $versaoId" -ForegroundColor Yellow
    Write-Host "Diretório: $versaoDir" -ForegroundColor Gray
    
    # Criar diretório da versão
    New-Item -ItemType Directory -Path $versaoDir -Force | Out-Null
    
    # Diretórios e arquivos importantes para backup
    $itensParaBackup = @(
        "lib",
        "pubspec.yaml",
        "pubspec.lock",
        "README.md",
        "firebase.json",
        ".firebaserc",
        "firestore.rules",
        "firestore.indexes.json",
        "ESTRUTURA_FIREBASE.md",
        "README_FIREBASE.md",
        "deploy_firebase.ps1",
        "salvamento_inteligente.ps1",
        "reverter_alteracoes.ps1",
        "sistema_backup_versionamento.ps1"
    )
    
    # Criar estrutura de backup
    $backupInfo = @{
        id = $versaoId
        timestamp = $timestamp
        data = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        descricao = "Backup automático"
        arquivos = @()
        tamanhoTotal = 0
    }
    
    $arquivosCopiados = 0
    $tamanhoTotal = 0
    
    Write-Host "`nCopiando arquivos..." -ForegroundColor Yellow
    
    foreach ($item in $itensParaBackup) {
        $caminhoOrigem = Join-Path $projetoDir $item
        
        if (Test-Path $caminhoOrigem) {
            $caminhoDestino = Join-Path $versaoDir $item
            $destinoPai = Split-Path -Parent $caminhoDestino
            
            if (-not (Test-Path $destinoPai)) {
                New-Item -ItemType Directory -Path $destinoPai -Force | Out-Null
            }
            
            try {
                if (Test-Path $caminhoOrigem -PathType Container) {
                    # É um diretório
                    Copy-Item -Path $caminhoOrigem -Destination $caminhoDestino -Recurse -Force -ErrorAction SilentlyContinue
                    $tamanho = (Get-ChildItem -Path $caminhoDestino -Recurse -File -ErrorAction SilentlyContinue | 
                                Measure-Object -Property Length -Sum).Sum
                } else {
                    # É um arquivo
                    Copy-Item -Path $caminhoOrigem -Destination $caminhoDestino -Force -ErrorAction SilentlyContinue
                    $tamanho = (Get-Item -Path $caminhoDestino -ErrorAction SilentlyContinue).Length
                }
                
                if ($tamanho) {
                    $tamanhoTotal += $tamanho
                    $arquivosCopiados++
                    Write-Host "  [OK] $item" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [ERRO] Erro ao copiar $item : $_" -ForegroundColor Red
            }
        }
    }
    
    # Criar arquivo de informações do Git (se houver)
    $gitInfoFile = Join-Path $versaoDir "git_info.txt"
    try {
        Push-Location $projetoDir
        $gitCommit = git rev-parse HEAD 2>$null
        $gitBranch = git branch --show-current 2>$null
        $gitStatus = git status --short 2>$null
        
        $gitInfo = @"
=== INFORMAÇÕES DO GIT ===
Commit: $gitCommit
Branch: $gitBranch
Status: $gitStatus
"@
        $gitInfo | Out-File -FilePath $gitInfoFile -Encoding UTF8
    } catch {
        # Git não disponível ou não é um repositório
    }
    finally {
        Pop-Location
    }
    
    # Criar arquivo de informações do backup
    $infoFile = Join-Path $versaoDir "info.txt"
    $backupInfo.arquivos = $arquivosCopiados
    $backupInfo.tamanhoTotal = $tamanhoTotal
    
    $infoContent = @"
=== INFORMAÇÕES DO BACKUP ===
ID: $($backupInfo.id)
Data: $($backupInfo.data)
Descrição: $($backupInfo.descricao)
Arquivos: $($backupInfo.arquivos)
Tamanho Total: $([math]::Round($tamanhoTotal / 1MB, 2)) MB
"@
    
    $infoContent | Out-File -FilePath $infoFile -Encoding UTF8
    
    # Atualizar índice de versões
    Atualizar-Indice -BackupInfo $backupInfo
    
    Write-Host "`n[SUCESSO] Backup criado com sucesso!" -ForegroundColor Green
    Write-Host "  ID: $versaoId" -ForegroundColor Cyan
    Write-Host "  Arquivos: $arquivosCopiados" -ForegroundColor Cyan
    Write-Host "  Tamanho: $([math]::Round($tamanhoTotal / 1MB, 2)) MB" -ForegroundColor Cyan
    Write-Host "  Local: $versaoDir" -ForegroundColor Gray
    
    return $versaoId
}

# Função para atualizar índice de versões
function Atualizar-Indice {
    param([hashtable]$BackupInfo)
    
    $versoes = @()
    
    if (Test-Path $indiceFile) {
        try {
            $conteudo = Get-Content $indiceFile -Raw -Encoding UTF8
            $versoes = $conteudo | ConvertFrom-Json
            if (-not $versoes) { $versoes = @() }
        } catch {
            $versoes = @()
        }
    }
    
    # Converter para array se for objeto único
    if ($versoes -isnot [array]) {
        $versoes = @($versoes)
    }
    
    # Adicionar nova versão
    $versoes = @($BackupInfo) + $versoes
    
    # Manter apenas as últimas 50 versões
    if ($versoes.Count -gt 50) {
        $versoes = $versoes[0..49]
    }
    
    # Salvar índice
    $versoes | ConvertTo-Json -Depth 10 | Out-File -FilePath $indiceFile -Encoding UTF8
}

# Função para listar versões
function Listar-Versoes {
    Write-Host "`n=== VERSÕES DISPONÍVEIS ===" -ForegroundColor Cyan
    
    if (-not (Test-Path $indiceFile)) {
        Write-Host "Nenhuma versão encontrada." -ForegroundColor Yellow
        return
    }
    
    try {
        $conteudo = Get-Content $indiceFile -Raw -Encoding UTF8
        $versoes = $conteudo | ConvertFrom-Json
        
        if (-not $versoes -or $versoes.Count -eq 0) {
            Write-Host "Nenhuma versão encontrada." -ForegroundColor Yellow
            return
        }
        
        # Converter para array se for objeto único
        if ($versoes -isnot [array]) {
            $versoes = @($versoes)
        }
        
        Write-Host "`nTotal de versões: $($versoes.Count)`n" -ForegroundColor Yellow
        
        $index = 0
        foreach ($versao in $versoes) {
            $index++
            $versaoDir = Join-Path $versoesDir $versao.id
            $existe = Test-Path $versaoDir
            
            $status = if ($existe) { "[OK]" } else { "[X]" }
            $cor = if ($existe) { "Green" } else { "Red" }
            
            Write-Host "[$index] $status $($versao.id)" -ForegroundColor $cor
            Write-Host "     Data: $($versao.data)" -ForegroundColor Gray
            Write-Host "     Arquivos: $($versao.arquivos) | Tamanho: $([math]::Round($versao.tamanhoTotal / 1MB, 2)) MB" -ForegroundColor Gray
            Write-Host ""
        }
    } catch {
        Write-Host "Erro ao ler índice: $_" -ForegroundColor Red
    }
}

# Função para restaurar versão
function Restaurar-Versao {
    param([string]$VersaoId)
    
    if (-not $VersaoId) {
        Write-Host "Erro: ID da versão não informado!" -ForegroundColor Red
        Write-Host "Use: .\sistema_backup_versionamento.ps1 -Acao restaurar -VersaoId v_20251202_120000" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n=== RESTAURANDO VERSÃO ===" -ForegroundColor Cyan
    Write-Host "Versão: $VersaoId" -ForegroundColor Yellow
    
    $versaoDir = Join-Path $versoesDir $VersaoId
    
    if (-not (Test-Path $versaoDir)) {
        Write-Host "Erro: Versão não encontrada!" -ForegroundColor Red
        Write-Host "Diretório: $versaoDir" -ForegroundColor Gray
        return
    }
    
    # Confirmar restauração
    Write-Host "`n[ATENCAO] Esta operacao ira substituir arquivos do projeto atual!" -ForegroundColor Yellow
    $confirmacao = Read-Host "Deseja continuar? (S/N)"
    
    if ($confirmacao -ne "S" -and $confirmacao -ne "s") {
        Write-Host "Restauração cancelada." -ForegroundColor Yellow
        return
    }
    
    # Criar backup antes de restaurar
    Write-Host "`nCriando backup de segurança antes da restauração..." -ForegroundColor Yellow
    $backupAntes = Criar-Backup
    Write-Host "Backup criado: $backupAntes" -ForegroundColor Green
    
    # Restaurar arquivos
    Write-Host "`nRestaurando arquivos..." -ForegroundColor Yellow
    
    $itensRestaurados = 0
    
    Get-ChildItem -Path $versaoDir -Recurse -File | ForEach-Object {
        $arquivoBackup = $_.FullName
        $caminhoRelativo = $arquivoBackup.Substring($versaoDir.Length + 1)
        $arquivoDestino = Join-Path $projetoDir $caminhoRelativo
        $destinoPai = Split-Path -Parent $arquivoDestino
        
        if (-not (Test-Path $destinoPai)) {
            New-Item -ItemType Directory -Path $destinoPai -Force | Out-Null
        }
        
            try {
                Copy-Item -Path $arquivoBackup -Destination $arquivoDestino -Force
                $itensRestaurados++
                Write-Host "  [OK] $caminhoRelativo" -ForegroundColor Green
            } catch {
                Write-Host "  [ERRO] Erro ao restaurar $caminhoRelativo : $_" -ForegroundColor Red
            }
    }
    
    Write-Host "`n[SUCESSO] Restauracao concluida!" -ForegroundColor Green
    Write-Host "  Arquivos restaurados: $itensRestaurados" -ForegroundColor Cyan
    Write-Host "  Backup de segurança: $backupAntes" -ForegroundColor Cyan
}

# Função para limpar versões antigas
function Limpar-VersoesAntigas {
    param([int]$Manter = 20)
    
    Write-Host "`n=== LIMPANDO VERSÕES ANTIGAS ===" -ForegroundColor Cyan
    Write-Host "Mantendo as últimas $Manter versões..." -ForegroundColor Yellow
    
    if (-not (Test-Path $indiceFile)) {
        Write-Host "Nenhuma versão para limpar." -ForegroundColor Yellow
        return
    }
    
    try {
        $conteudo = Get-Content $indiceFile -Raw -Encoding UTF8
        $versoes = $conteudo | ConvertFrom-Json
        
        if (-not $versoes -or $versoes.Count -eq 0) {
            Write-Host "Nenhuma versão para limpar." -ForegroundColor Yellow
            return
        }
        
        # Converter para array se for objeto único
        if ($versoes -isnot [array]) {
            $versoes = @($versoes)
        }
        
        if ($versoes.Count -le $Manter) {
            Write-Host "Total de versões ($($versoes.Count)) está dentro do limite ($Manter)." -ForegroundColor Green
            return
        }
        
        # Separar versões para manter e remover
        $versoesManter = $versoes[0..($Manter - 1)]
        $versoesRemover = $versoes[$Manter..($versoes.Count - 1)]
        
        $removidas = 0
        foreach ($versao in $versoesRemover) {
            $versaoDir = Join-Path $versoesDir $versao.id
            if (Test-Path $versaoDir) {
                Remove-Item -Path $versaoDir -Recurse -Force -ErrorAction SilentlyContinue
                $removidas++
                Write-Host "  Removido: $($versao.id)" -ForegroundColor Gray
            }
        }
        
        # Atualizar índice
        $versoesManter | ConvertTo-Json -Depth 10 | Out-File -FilePath $indiceFile -Encoding UTF8
        
        Write-Host "`n[SUCESSO] Limpeza concluida!" -ForegroundColor Green
        Write-Host "  Versões removidas: $removidas" -ForegroundColor Cyan
        Write-Host "  Versões mantidas: $($versoesManter.Count)" -ForegroundColor Cyan
    } catch {
        Write-Host "Erro ao limpar versões: $_" -ForegroundColor Red
    }
}

# Menu principal
switch ($Acao.ToLower()) {
    "backup" {
        Criar-Backup
    }
    "listar" {
        Listar-Versoes
    }
    "restaurar" {
        Restaurar-Versao -VersaoId $VersaoId
    }
    "limpar" {
        Limpar-VersoesAntigas -Manter 20
    }
    default {
        Write-Host "`n=== SISTEMA DE BACKUP E VERSIONAMENTO ===" -ForegroundColor Cyan
        Write-Host "`nUso:" -ForegroundColor Yellow
        Write-Host "  .\sistema_backup_versionamento.ps1 -Acao backup" -ForegroundColor White
        Write-Host "  .\sistema_backup_versionamento.ps1 -Acao listar" -ForegroundColor White
        Write-Host "  .\sistema_backup_versionamento.ps1 -Acao restaurar -VersaoId v_20251202_120000" -ForegroundColor White
        Write-Host "  .\sistema_backup_versionamento.ps1 -Acao limpar" -ForegroundColor White
        Write-Host ""
    }
}


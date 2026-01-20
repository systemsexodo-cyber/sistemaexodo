# ============================================================================
# Script de Configuração Automática do Flutter - Sistema Êxodo
# ============================================================================
# Este script configura automaticamente o ambiente Flutter e resolve
# problemas comuns de instalação do Dart SDK
# ============================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Sistema Êxodo - Configuração Automática do Flutter" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Função para exibir mensagens coloridas
function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERRO] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n>>> $Message" -ForegroundColor Magenta
}

# ============================================================================
# PASSO 1: Verificar Git
# ============================================================================
Write-Step "Verificando instalação do Git..."

try {
    $gitVersion = git --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Git instalado: $gitVersion"
    }
}
catch {
    Write-Error-Custom "Git não encontrado!"
    Write-Info "Baixe e instale o Git em: https://git-scm.com/download/win"
    Write-Info "Após instalação, reinicie o PowerShell e execute este script novamente."
    pause
    exit 1
}

# ============================================================================
# PASSO 2: Verificar Flutter
# ============================================================================
Write-Step "Verificando instalação do Flutter..."

$flutterPath = $null
try {
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $flutterPath = Split-Path (Split-Path $flutterCmd.Source -Parent)
        Write-Success "Flutter encontrado em: $flutterPath"
    }
}
catch {
    Write-Error-Custom "Flutter não encontrado no PATH!"
}

if (-not $flutterPath) {
    Write-Info "Flutter não está instalado ou não está no PATH."
    Write-Info "Por favor, siga estas instruções:"
    Write-Info "1. Baixe o Flutter em: https://flutter.dev/docs/get-started/install/windows"
    Write-Info "2. Extraia para C:\src\flutter"
    Write-Info "3. Adicione C:\src\flutter\bin ao PATH do sistema"
    pause
    exit 1
}

# ============================================================================
# PASSO 3: Matar processos Flutter/Dart travados
# ============================================================================
Write-Step "Encerrando processos Flutter/Dart em execução..."

$processes = Get-Process | Where-Object { $_.Name -like '*flutter*' -or $_.Name -like '*dart*' } -ErrorAction SilentlyContinue
if ($processes) {
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Success "Processos encerrados"
}
else {
    Write-Info "Nenhum processo Flutter/Dart em execução"
}

Start-Sleep -Seconds 2

# ============================================================================
# PASSO 4: Remover lock files
# ============================================================================
Write-Step "Removendo arquivos de bloqueio..."

$lockFile = "$flutterPath\bin\cache\flutter.bat.lock"
if (Test-Path $lockFile) {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    Write-Success "Lock file removido"
}
else {
    Write-Info "Lock file não encontrado (OK)"
}

# ============================================================================
# PASSO 5: Verificar e corrigir Dart SDK
# ============================================================================
Write-Step "Verificando Dart SDK..."

$dartSdkPath = "$flutterPath\bin\cache\dart-sdk"
$dartExePath = "$dartSdkPath\bin\dart.exe"

if (Test-Path $dartExePath) {
    Write-Success "Dart SDK encontrado e válido"
}
else {
    Write-Error-Custom "Dart SDK corrompido ou faltando!"
    Write-Info "Tentando corrigir automaticamente..."
    
    # Remover dart-sdk corrompido
    if (Test-Path $dartSdkPath) {
        Write-Info "Removendo Dart SDK corrompido..."
        Remove-Item $dartSdkPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remover arquivos stamp para forçar reinstalação
    Remove-Item "$flutterPath\bin\cache\*.stamp" -Force -ErrorAction SilentlyContinue
    
    Write-Info "Baixando Dart SDK... (isso pode demorar alguns minutos)"
    
    # Executar flutter doctor para baixar o Dart SDK
    $output = flutter doctor 2>&1
    
    if (Test-Path $dartExePath) {
        Write-Success "Dart SDK instalado com sucesso!"
    }
    else {
        Write-Error-Custom "Falha ao instalar Dart SDK automaticamente"
        Write-Info "Por favor, execute manualmente: flutter doctor"
        pause
        exit 1
    }
}

# ============================================================================
# PASSO 6: Verificar versão do Flutter
# ============================================================================
Write-Step "Verificando versão do Flutter..."

try {
    $flutterVersion = flutter --version 2>&1 | Select-String "Flutter"
    Write-Success $flutterVersion
}
catch {
    Write-Error-Custom "Erro ao verificar versão do Flutter"
}

# ============================================================================
# PASSO 7: Verificar dispositivos disponíveis
# ============================================================================
Write-Step "Verificando dispositivos disponíveis..."

Write-Info "Dispositivos detectados:"
flutter devices

# ============================================================================
# PASSO 8: Instalar dependências do projeto
# ============================================================================
Write-Step "Instalando dependências do projeto..."

if (Test-Path "pubspec.yaml") {
    Write-Info "Executando flutter pub get..."
    flutter pub get
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Dependências instaladas com sucesso!"
    }
    else {
        Write-Error-Custom "Erro ao instalar dependências"
        pause
        exit 1
    }
}
else {
    Write-Error-Custom "Arquivo pubspec.yaml não encontrado!"
    Write-Info "Certifique-se de estar no diretório raiz do projeto Flutter"
    pause
    exit 1
}

# ============================================================================
# FINALIZAÇÃO
# ============================================================================
Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  Configuração concluída com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Info "Para executar o projeto, use um dos comandos:"
Write-Host "  flutter run -d edge       " -ForegroundColor Cyan -NoNewline
Write-Host "(Executar no Microsoft Edge)" -ForegroundColor Gray
Write-Host "  flutter run -d windows    " -ForegroundColor Cyan -NoNewline
Write-Host "(Executar como app desktop)" -ForegroundColor Gray
Write-Host "  flutter run -d chrome     " -ForegroundColor Cyan -NoNewline
Write-Host "(Executar no Chrome, se instalado)" -ForegroundColor Gray
Write-Host ""

# Perguntar se deseja executar agora
$runNow = Read-Host "Deseja executar o projeto agora? (edge/windows/n) [edge]"
if ([string]::IsNullOrWhiteSpace($runNow)) {
    $runNow = "edge"
}

if ($runNow -eq "n" -or $runNow -eq "N") {
    Write-Info "Script finalizado. Execute manualmente quando desejar."
    exit 0
}

Write-Step "Executando projeto no dispositivo: $runNow"
flutter run -d $runNow

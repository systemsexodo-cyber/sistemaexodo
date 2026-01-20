# Script de Instalação Completa (Flutter + Python + Dependências)
$ErrorActionPreference = "Stop"

# Força o uso de TLS 1.2 para downloads (Corrige erro de descriptografia no Invoke-WebRequest)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Title { param($msg) Write-Host "`n========================================`n$msg`n========================================" -ForegroundColor Cyan }
function Write-Step { param($msg) Write-Host "-> $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "AVISO: $msg" -ForegroundColor Yellow }

$destDir = "C:\src"
$flutterDir = "$destDir\flutter"
$tempDir = $env:TEMP

# 1. Instalar Flutter
Write-Title "1. Verificando Flutter"
if (-not (Test-Path $flutterDir)) {
    Write-Step "Baixando Flutter (Stable)..."
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    
    $flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.19.0-stable.zip"
    $zipPath = "$destDir\flutter.zip"
    
    Invoke-WebRequest -Uri $flutterUrl -OutFile $zipPath
    
    Write-Step "Extraindo Flutter (Aguarde)..."
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
    Remove-Item $zipPath -Force
    Write-Step "Flutter extraído em $flutterDir"
}
else {
    Write-Step "Flutter já instalado em $flutterDir"
}

# Configurar PATH do Flutter
$flutterBin = "$flutterDir\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$flutterBin*") {
    Write-Step "Adicionando Flutter ao PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$flutterBin", "User")
    $env:Path += ";$flutterBin" # Atualizar sessão atual
}

# 2. Instalar Python
Write-Title "2. Verificando Python"
try {
    python --version 2>$null
    Write-Step "Python já instalado!"
}
catch {
    Write-Step "Python não encontrado. Baixando instalador..."
    $pythonInstaller = "$tempDir\python_installer.exe"
    # Python 3.12.2
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe" -OutFile $pythonInstaller
    
    Write-Step "Instalando Python (Silenciosamente)..."
    Write-Warn "Pode pedir permissão de administrador..."
    Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    
    Write-Step "Python instalado. Atualizando PATH..."
    # Tentar adivinhar o path padrão do Python se não aparecer
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# 3. Instalar Dependências do Backend
Write-Title "3. Instalando Dependências Python"
Write-Step "Atualizando pip..."
try {
    python -m pip install --upgrade pip
    
    Write-Step "Instalando bibliotecas (flask, cors, cryptography...)"
    python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
    
    Write-Step "Dependências instaladas com sucesso!"
}
catch {
    Write-Warn "Falha ao executar pip. Pode ser necessário reiniciar o terminal para o Python ser reconhecido."
}

Write-Title "INSTALAÇÃO CONCLUÍDA!"
Write-Host "IMPORTANTE: Reinicie seu terminal ou computador para garantir que todos os comandos funcionem." -ForegroundColor Cyan

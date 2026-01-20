# Script para finalizar a configuração após os downloads
$ErrorActionPreference = "SilentlyContinue"

# Força o uso de TLS 1.2 para downloads (Corrige erro de descriptografia no Invoke-WebRequest)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Verificando downloads..." -ForegroundColor Cyan

# 1. Configurar Flutter
if (Test-Path "C:\src\flutter\bin") {
    Write-Host "Configurando Flutter..." -ForegroundColor Green
    $flutterBin = "C:\src\flutter\bin"
    
    # Adicionar ao PATH do Usuário de forma permanente
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$flutterBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$flutterBin", "User")
    }
    
    # Adicionar à sessão atual
    $env:Path += ";$flutterBin"
    
    Write-Host "Executando flutter doctor para inicializar..." -ForegroundColor Yellow
    flutter doctor --version
}

# 2. Instalar Python
if (Test-Path "C:\src\python_installer.exe") {
    Write-Host "Instalando Python..." -ForegroundColor Green
    Start-Process -FilePath "C:\src\python_installer.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item "C:\src\python_installer.exe" -Force
}

Write-Host "Ambiente configurado!" -ForegroundColor Cyan

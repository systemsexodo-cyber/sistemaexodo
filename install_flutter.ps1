# Script para instalar Flutter automaticamente
# Baixa e extrai o Flutter SDK para C:\src\flutter

$ErrorActionPreference = "Stop"

# Força o uso de TLS 1.2 para downloads (Corrige erro de descriptografia no Invoke-WebRequest)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Iniciando instalação do Flutter..." -ForegroundColor Cyan

# Diretório de destino
$destDir = "C:\src"
$flutterDir = "$destDir\flutter"

# Criar diretório C:\src se não existir
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host "Diretório $destDir criado."
}

# URL do Flutter Stable (Windows)
$flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.38.7-stable.zip"
$zipPath = "$destDir\flutter.zip"

if (-not (Test-Path $flutterDir)) {
    Write-Host "Baixando Flutter 3.38.7..."
    Invoke-WebRequest -Uri $flutterUrl -OutFile $zipPath
    
    Write-Host "Extraindo Flutter (isso pode demorar)..."
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
    
    Remove-Item $zipPath -Force
    Write-Host "Flutter instalado em $flutterDir" -ForegroundColor Green
}
else {
    Write-Host "Pasta Flutter já existe em $flutterDir. Pulando download." -ForegroundColor Yellow
}

# Adicionar ao PATH do Usuário
$binPath = "$flutterDir\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($currentPath -notlike "*$binPath*") {
    Write-Host "Adicionando Flutter ao PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "User")
    Write-Host "PATH atualizado." -ForegroundColor Green
}
else {
    Write-Host "Flutter já está no PATH." -ForegroundColor Green
}

# Atualizar PATH na sessão atual para verificação imediata (parcial, pode não funcionar para todos processos)
$env:Path += ";$binPath"

Write-Host "Concluído! Verificando versão..." -ForegroundColor Cyan
flutter --version

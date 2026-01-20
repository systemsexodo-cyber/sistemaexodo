# Script para finalizar a configuração e iniciar o projeto
$ErrorActionPreference = "Continue"

Write-Host "--- Finalizando Configurações ---" -ForegroundColor Cyan

# 1. Instalar Python
if (Test-Path "C:\src\python_installer.exe") {
    Write-Host "Instalando Python (Silenciosamente)..." -ForegroundColor Green
    Start-Process -FilePath "C:\src\python_installer.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item "C:\src\python_installer.exe" -Force
    Write-Host "Python instalado." -ForegroundColor Green
}

# 2. Configurar Variáveis de Ambiente na Sessão Atual
$flutterBin = "C:\src\flutter\bin"
$pythonPath = "C:\Program Files\Python312" # Caminho provável se InstallAllUsers=1
$pythonScripts = "$pythonPath\Scripts"

# Adicionar ao PATH permanente do usuário
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$modified = $false
if ($userPath -notlike "*$flutterBin*") { $userPath += ";$flutterBin"; $modified = $true }
if ($modified) { [Environment]::SetEnvironmentVariable("Path", $userPath, "User") }

# Adicionar à sessão atual
$env:Path += ";$flutterBin;$pythonPath;$pythonScripts"

# 3. Validar Flutter
Write-Host "Inicializando Flutter (pode demorar na primeira vez)..." -ForegroundColor Yellow
& flutter doctor --version

# 4. Instalar Dependências do Projeto
Write-Host "Instalando dependências do Flutter..." -ForegroundColor Green
& flutter pub get

# 5. Iniciar Backend (em segundo plano)
Write-Host "Iniciando Backend..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-Command cd backend_pynfe; python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography; python app.py" -WindowStyle Minimized

# 6. Iniciar Frontend Web
Write-Host "Iniciando Frontend Web na porta 8080..." -ForegroundColor Green
& flutter run -d chrome --web-port 8080

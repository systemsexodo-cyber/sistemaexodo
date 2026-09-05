# Super Instalador Automatizado - Sistema Êxodo
# Este script configura todo o ambiente de desenvolvimento Windows (C++, Flutter, SQLite)

$ErrorActionPreference = "Continue"
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   CONFIGURADOR AUTOMÁTICO - AMBIENTE EXODO (WIN)   " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Verificar e Instalar Componentes do Visual Studio (C++)
Write-Host "`n[1/4] Verificando componentes C++ do Visual Studio..." -ForegroundColor Yellow

$vsInstallerPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
if (-not (Test-Path $vsInstallerPath)) {
    $vsInstallerPath = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\setup.exe"
}

if (Test-Path $vsInstallerPath) {
    Write-Host ">>> Instalador do Visual Studio encontrado. Iniciando adição de C++..." -ForegroundColor Green
    Write-Host ">>> Isso pode demorar alguns minutos e abrirá uma janela de progresso." -ForegroundColor White
    
    # Comando para adicionar a carga de trabalho de Desktop C++ (Indispensável para o Flutter Windows e SQLite)
    $process = Start-Process -FilePath $vsInstallerPath -ArgumentList "modify --installPath ""C:\Program Files\Microsoft Visual Studio\2022\Community"" --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart" -Wait -PassThru
    
    # Caso seja VS 2019 ou 2026 (ajuste de path se necessário pelo log do doctor)
    if ($process.ExitCode -ne 0) {
        Write-Host ">>> Tentando outro caminho de instalação (VS 2026/Custom)..." -ForegroundColor Gray
        Start-Process -FilePath $vsInstallerPath -ArgumentList "modify --installPath ""C:\Program Files\Microsoft Visual Studio\18\Community"" --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart" -Wait
    }
} else {
    Write-Host ">>> [ERRO] Instalador do Visual Studio não encontrado! Por favor, instale o VS Community primeiro." -ForegroundColor Red
}

# 2. Configurar Flutter e Dependências
Write-Host "`n[2/4] Atualizando dependências do Flutter..." -ForegroundColor Yellow
flutter clean
flutter pub get

# 3. Verificar SQLite FFI
Write-Host "`n[3/4] Preparando Banco de Dados Local (SQLite)..." -ForegroundColor Yellow
Write-Host ">>> O SQLite será compilado automaticamente na primeira execução Windows." -ForegroundColor White

# 4. Finalização
Write-Host "`n[4/4] Verificando ambiente final..." -ForegroundColor Yellow
flutter doctor

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "   AMBIENTE CONFIGURADO COM SUCESSO!                " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "Para rodar o sistema agora, use:" -ForegroundColor White
Write-Host "flutter run -d windows" -ForegroundColor Cyan

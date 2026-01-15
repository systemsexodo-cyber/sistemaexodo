# ============================================================
# SCRIPT PARA INSTALAR OPENSSL NO WINDOWS
# ============================================================
# Este script ajuda a instalar o OpenSSL no Windows
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INSTALADOR DE OPENSSL PARA WINDOWS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se OpenSSL já está instalado
Write-Host "Verificando se OpenSSL já está instalado..." -ForegroundColor Yellow
try {
    $opensslVersion = openssl version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ OpenSSL já está instalado!" -ForegroundColor Green
        Write-Host "Versão: $opensslVersion" -ForegroundColor Gray
        Write-Host ""
        Write-Host "OpenSSL está pronto para uso!" -ForegroundColor Green
        exit 0
    }
} catch {
    Write-Host "OpenSSL não encontrado no PATH" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "OpenSSL não está instalado ou não está no PATH." -ForegroundColor Yellow
Write-Host ""

# Verificar se Chocolatey está instalado
$chocoInstalled = $false
try {
    $chocoVersion = choco --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $chocoInstalled = $true
        Write-Host "✓ Chocolatey encontrado!" -ForegroundColor Green
    }
} catch {
    Write-Host "Chocolatey não encontrado" -ForegroundColor Gray
}

# Verificar se Scoop está instalado
$scoopInstalled = $false
try {
    $scoopVersion = scoop --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $scoopInstalled = $true
        Write-Host "✓ Scoop encontrado!" -ForegroundColor Green
    }
} catch {
    Write-Host "Scoop não encontrado" -ForegroundColor Gray
}

# Verificar se Git Bash tem OpenSSL
$gitBashOpenSSL = $false
$gitBashPath = "C:\Program Files\Git\usr\bin\openssl.exe"
if (Test-Path $gitBashPath) {
    try {
        $gitBashVersion = & $gitBashPath version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $gitBashOpenSSL = $true
            Write-Host "✓ OpenSSL encontrado no Git Bash!" -ForegroundColor Green
            Write-Host "Caminho: $gitBashPath" -ForegroundColor Gray
            Write-Host ""
            Write-Host "O sistema já pode usar este OpenSSL!" -ForegroundColor Green
            Write-Host "Não é necessário instalar nada adicional." -ForegroundColor Gray
            exit 0
        }
    } catch {
        # Ignorar
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OPÇÕES DE INSTALAÇÃO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Opção 1: Chocolatey
if ($chocoInstalled) {
    Write-Host "1. Instalar via Chocolatey (RECOMENDADO)" -ForegroundColor Yellow
    Write-Host "   Comando: choco install openssl -y" -ForegroundColor Gray
    Write-Host ""
}

# Opção 2: Scoop
if ($scoopInstalled) {
    Write-Host "2. Instalar via Scoop" -ForegroundColor Yellow
    Write-Host "   Comando: scoop install openssl" -ForegroundColor Gray
    Write-Host ""
}

# Opção 3: Instalador Manual
Write-Host "3. Instalar via Instalador Oficial" -ForegroundColor Yellow
Write-Host "   URL: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Cyan
Write-Host "   Baixe: Win64 OpenSSL (versão LIGHT ou FULL)" -ForegroundColor Gray
Write-Host "   IMPORTANTE: Marque 'Add OpenSSL to PATH' durante instalação" -ForegroundColor Red
Write-Host ""

# Perguntar qual opção usar
if ($chocoInstalled) {
    $resposta = Read-Host "Deseja instalar via Chocolatey? (S/N)"
    if ($resposta -eq "S" -or $resposta -eq "s") {
        Write-Host ""
        Write-Host "Instalando OpenSSL via Chocolatey..." -ForegroundColor Yellow
        choco install openssl -y
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✓ OpenSSL instalado com sucesso!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Reinicie o terminal e execute: openssl version" -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "✗ Erro ao instalar via Chocolatey" -ForegroundColor Red
        }
        exit
    }
}

if ($scoopInstalled) {
    $resposta = Read-Host "Deseja instalar via Scoop? (S/N)"
    if ($resposta -eq "S" -or $resposta -eq "s") {
        Write-Host ""
        Write-Host "Instalando OpenSSL via Scoop..." -ForegroundColor Yellow
        scoop install openssl
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✓ OpenSSL instalado com sucesso!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Execute: openssl version" -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "✗ Erro ao instalar via Scoop" -ForegroundColor Red
        }
        exit
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INSTRUÇÕES MANUAIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Acesse: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Baixe: Win64 OpenSSL (versão LIGHT é suficiente)" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Execute o instalador e:" -ForegroundColor Yellow
Write-Host "   ✓ Marque 'Copy OpenSSL DLLs to: The OpenSSL binaries (/bin) directory'" -ForegroundColor Green
Write-Host "   ✓ Marque 'Add OpenSSL to the system PATH for all users'" -ForegroundColor Green
Write-Host ""
Write-Host "4. Após instalar, reinicie o terminal" -ForegroundColor Yellow
Write-Host ""
Write-Host "5. Verifique com: openssl version" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PRONTO! O sistema detectará automaticamente" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""





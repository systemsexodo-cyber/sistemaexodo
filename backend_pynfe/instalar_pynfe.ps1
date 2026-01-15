# Script PowerShell para instalar PyNFe
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Instalando PyNFe do GitHub" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se o ambiente virtual existe
if (-not (Test-Path "venv\Scripts\python.exe")) {
    Write-Host "❌ Ambiente virtual não encontrado!" -ForegroundColor Red
    Write-Host "Execute primeiro: instalar_tudo.bat" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host "✅ Ambiente virtual encontrado" -ForegroundColor Green
Write-Host ""

# Verificar se Git está instalado
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitPath) {
    Write-Host "❌ Git não está instalado!" -ForegroundColor Red
    Write-Host "PyNFe precisa do Git para ser instalado do GitHub." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Instale o Git de: https://git-scm.com/download/win" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host "✅ Git encontrado" -ForegroundColor Green
Write-Host ""

# Atualizar pip
Write-Host "📦 Atualizando pip..." -ForegroundColor Yellow
& "venv\Scripts\python.exe" -m pip install --upgrade pip --quiet
Write-Host "✅ Pip atualizado" -ForegroundColor Green
Write-Host ""

# Instalar PyNFe
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Instalando PyNFe do GitHub..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Isso pode levar alguns minutos..." -ForegroundColor Yellow
Write-Host ""

& "venv\Scripts\python.exe" -m pip install git+https://github.com/TadaSoftware/PyNFe.git

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Erro ao instalar PyNFe!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possíveis causas:" -ForegroundColor Yellow
    Write-Host "1. Git não está instalado" -ForegroundColor Yellow
    Write-Host "2. Sem conexão com a internet" -ForegroundColor Yellow
    Write-Host "3. Repositório GitHub inacessível" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verificando instalação..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$checkResult = & "venv\Scripts\python.exe" -c "try:
    import pynfe
    print('✅ PyNFe instalado com sucesso!')
    print('✅ Pronto para usar!')
except ImportError:
    print('❌ PyNFe não foi instalado corretamente')
    exit(1)"

Write-Host $checkResult

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ PyNFe não está funcionando corretamente" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ Instalação concluída!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Agora você pode iniciar o servidor com:" -ForegroundColor Yellow
Write-Host "  start_local.bat" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para sair"



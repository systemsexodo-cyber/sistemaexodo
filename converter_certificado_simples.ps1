# Script SIMPLES para converter certificado PFX para PEM
# Uso: Execute e cole o caminho quando pedir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONVERSOR SIMPLES PFX → PEM" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Pedir caminho do certificado
Write-Host "Cole o caminho completo do certificado PFX:" -ForegroundColor Yellow
$caminhoPFX = Read-Host

# Verificar se existe
if (-not (Test-Path $caminhoPFX)) {
    Write-Host ""
    Write-Host "ERRO: Arquivo não encontrado!" -ForegroundColor Red
    Write-Host "Caminho: $caminhoPFX" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Pedir senha
Write-Host ""
Write-Host "Digite a senha do certificado:" -ForegroundColor Yellow
$senha = Read-Host -AsSecureString
$senhaTexto = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($senha)
)

Write-Host ""
Write-Host "Procurando OpenSSL..." -ForegroundColor Yellow

# Tentar encontrar OpenSSL
$openssl = $null
$caminhos = @(
    "C:\Program Files\Git\usr\bin\openssl.exe",
    "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
    "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
    "C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe"
)

foreach ($caminho in $caminhos) {
    if (Test-Path $caminho) {
        $teste = & $caminho version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $openssl = $caminho
            Write-Host "  OpenSSL encontrado: $caminho" -ForegroundColor Green
            break
        }
    }
}

# Tentar openssl no PATH
if ($null -eq $openssl) {
    try {
        $teste = & openssl version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $openssl = "openssl"
            Write-Host "  OpenSSL encontrado no PATH" -ForegroundColor Green
        }
    } catch {
        # Ignorar
    }
}

if ($null -eq $openssl) {
    Write-Host ""
    Write-Host "ERRO: OpenSSL não encontrado!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Execute primeiro: .\instalar_openssl.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Obter diretório e nome
$dir = Split-Path -Parent $caminhoPFX
$nome = [System.IO.Path]::GetFileNameWithoutExtension($caminhoPFX)
$pemFinal = Join-Path $dir "$nome.pem"

Write-Host ""
Write-Host "Convertendo..." -ForegroundColor Yellow

# Converter diretamente para PEM (mais simples)
try {
    if ($openssl -eq "openssl") {
        & openssl pkcs12 -in $caminhoPFX -out $pemFinal -nodes -passin "pass:$senhaTexto" 2>&1 | Out-Null
    } else {
        & $openssl pkcs12 -in $caminhoPFX -out $pemFinal -nodes -passin "pass:$senhaTexto" 2>&1 | Out-Null
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Erro na conversão (código: $LASTEXITCODE)"
    }
    
    if (-not (Test-Path $pemFinal)) {
        throw "Arquivo não foi criado"
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCESSO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Arquivo PEM criado:" -ForegroundColor Cyan
    Write-Host "  $pemFinal" -ForegroundColor White
    Write-Host ""
    Write-Host "Tamanho: $((Get-Item $pemFinal).Length) bytes" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERRO: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possíveis causas:" -ForegroundColor Yellow
    Write-Host "  • Senha incorreta" -ForegroundColor Gray
    Write-Host "  • Certificado corrompido" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Pressione qualquer tecla para sair..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")





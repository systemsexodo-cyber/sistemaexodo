# Script para converter certificado PFX para PEM manualmente
# Uso: .\converter_certificado_manual.ps1 -CaminhoCertificado "C:\caminho\certificado.pfx" -Senha "sua_senha"

param(
    [Parameter(Mandatory=$false)]
    [string]$CaminhoCertificado = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Senha = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONVERSOR DE CERTIFICADO PFX → PEM" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Se não forneceu caminho, pedir interativamente
if ([string]::IsNullOrEmpty($CaminhoCertificado)) {
    Write-Host "Por favor, forneça o caminho do certificado PFX:" -ForegroundColor Yellow
    $CaminhoCertificado = Read-Host "Caminho do certificado"
}

# Verificar se o arquivo existe
if (-not (Test-Path $CaminhoCertificado)) {
    Write-Host "ERRO: Arquivo não encontrado: $CaminhoCertificado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Se não forneceu senha, pedir interativamente (ocultando a entrada)
if ([string]::IsNullOrEmpty($Senha)) {
    Write-Host "Por favor, forneça a senha do certificado:" -ForegroundColor Yellow
    $SecureSenha = Read-Host "Senha" -AsSecureString
    $Senha = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSenha)
    )
}

Write-Host ""
Write-Host "Informações do certificado:" -ForegroundColor Green
Write-Host "  Arquivo: $CaminhoCertificado" -ForegroundColor Gray
Write-Host "  Tamanho: $((Get-Item $CaminhoCertificado).Length) bytes" -ForegroundColor Gray
Write-Host ""

# Procurar OpenSSL
Write-Host "Procurando OpenSSL..." -ForegroundColor Yellow
$opensslPath = $null

# Lista de caminhos possíveis
$caminhosOpenSSL = @(
    "openssl",
    "C:\Program Files\Git\usr\bin\openssl.exe",
    "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
    "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
    "C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe",
    "C:\OpenSSL-Win64\bin\openssl.exe",
    "C:\OpenSSL-Win32\bin\openssl.exe",
    "C:\ProgramData\chocolatey\bin\openssl.exe"
)

foreach ($caminho in $caminhosOpenSSL) {
    try {
        if ($caminho -eq "openssl") {
            $resultado = & openssl version 2>&1
        } else {
            if (Test-Path $caminho) {
                $resultado = & $caminho version 2>&1
            } else {
                continue
            }
        }
        
        if ($LASTEXITCODE -eq 0) {
            $opensslPath = $caminho
            Write-Host "  ✓ OpenSSL encontrado: $caminho" -ForegroundColor Green
            Write-Host "  Versão: $($resultado -join ' ')" -ForegroundColor Gray
            break
        }
    } catch {
        continue
    }
}

if ($null -eq $opensslPath) {
    Write-Host ""
    Write-Host "ERRO: OpenSSL não encontrado!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor, instale o OpenSSL:" -ForegroundColor Yellow
    Write-Host "  1. Execute: .\instalar_openssl.ps1" -ForegroundColor Cyan
    Write-Host "  2. OU baixe de: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Obter diretório e nome do arquivo
$diretorio = Split-Path -Parent $CaminhoCertificado
$nomeArquivo = [System.IO.Path]::GetFileNameWithoutExtension($CaminhoCertificado)
$caminhoCert = Join-Path $diretorio "$nomeArquivo.crt"
$caminhoChave = Join-Path $diretorio "${nomeArquivo}_chave_privada.pem"
$caminhoPEM = Join-Path $diretorio "$nomeArquivo.pem"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INICIANDO CONVERSÃO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Passo 1: Extrair certificado público
Write-Host "Passo 1/3: Extraindo certificado público..." -ForegroundColor Yellow
try {
    if ($opensslPath -eq "openssl") {
        & openssl pkcs12 -in $CaminhoCertificado -clcerts -nokeys -out $caminhoCert -passin "pass:$Senha" 2>&1 | Out-Null
    } else {
        & $opensslPath pkcs12 -in $CaminhoCertificado -clcerts -nokeys -out $caminhoCert -passin "pass:$Senha" 2>&1 | Out-Null
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Erro ao extrair certificado (código: $LASTEXITCODE)"
    }
    
    if (-not (Test-Path $caminhoCert)) {
        throw "Arquivo de certificado não foi criado"
    }
    
    $tamanhoCert = (Get-Item $caminhoCert).Length
    Write-Host "  ✓ Certificado extraído: $caminhoCert ($tamanhoCert bytes)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ERRO ao extrair certificado: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possíveis causas:" -ForegroundColor Yellow
    Write-Host "  • Senha incorreta" -ForegroundColor Gray
    Write-Host "  • Certificado corrompido" -ForegroundColor Gray
    Write-Host "  • Certificado em formato não suportado" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Passo 2: Extrair chave privada
Write-Host "Passo 2/3: Extraindo chave privada..." -ForegroundColor Yellow
try {
    if ($opensslPath -eq "openssl") {
        & openssl pkcs12 -in $CaminhoCertificado -nocerts -nodes -out $caminhoChave -passin "pass:$Senha" 2>&1 | Out-Null
    } else {
        & $opensslPath pkcs12 -in $CaminhoCertificado -nocerts -nodes -out $caminhoChave -passin "pass:$Senha" 2>&1 | Out-Null
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Erro ao extrair chave privada (código: $LASTEXITCODE)"
    }
    
    if (-not (Test-Path $caminhoChave)) {
        throw "Arquivo de chave privada não foi criado"
    }
    
    $tamanhoChave = (Get-Item $caminhoChave).Length
    Write-Host "  ✓ Chave privada extraída: $caminhoChave ($tamanhoChave bytes)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ERRO ao extrair chave privada: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Limpando arquivos temporários..." -ForegroundColor Yellow
    if (Test-Path $caminhoCert) { Remove-Item $caminhoCert -Force }
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Passo 3: Combinar certificado e chave em um arquivo PEM
Write-Host "Passo 3/3: Combinando certificado e chave..." -ForegroundColor Yellow
try {
    $conteudoCert = Get-Content $caminhoCert -Raw
    $conteudoChave = Get-Content $caminhoChave -Raw
    $conteudoPEM = "$conteudoCert`n$conteudoChave"
    
    Set-Content -Path $caminhoPEM -Value $conteudoPEM -NoNewline
    Write-Host "  ✓ Arquivo PEM criado: $caminhoPEM" -ForegroundColor Green
} catch {
    Write-Host "  ✗ ERRO ao combinar arquivos: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Limpar arquivos intermediários
Write-Host ""
Write-Host "Limpando arquivos intermediários..." -ForegroundColor Yellow
if (Test-Path $caminhoCert) { Remove-Item $caminhoCert -Force }
if (Test-Path $caminhoChave) { Remove-Item $caminhoChave -Force }
Write-Host "  ✓ Arquivos limpos" -ForegroundColor Green

# Resultado final
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  CONVERSÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivo PEM gerado:" -ForegroundColor Cyan
Write-Host "  $caminhoPEM" -ForegroundColor White
Write-Host ""
Write-Host "Tamanho: $((Get-Item $caminhoPEM).Length) bytes" -ForegroundColor Gray
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Yellow
Write-Host "  1. No sistema, vá em 'Empresas' → Edite a empresa" -ForegroundColor Cyan
Write-Host "  2. Remova o certificado antigo (PFX)" -ForegroundColor Cyan
Write-Host "  3. Selecione o arquivo PEM gerado: $caminhoPEM" -ForegroundColor Cyan
Write-Host "  4. Salve e tente emitir NFC-e novamente" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pressione qualquer tecla para sair..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")





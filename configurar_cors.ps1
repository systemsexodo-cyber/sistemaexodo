# Script para configurar CORS no Firebase Storage
# IMPORTANTE: Isso resolve o erro de CORS ao fazer upload de imagens

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURAR CORS NO FIREBASE STORAGE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se o arquivo cors.json existe
if (-not (Test-Path "cors.json")) {
    Write-Host "Criando arquivo cors.json..." -ForegroundColor Yellow
    $corsContent = @"
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE", "OPTIONS"],
    "responseHeader": ["Content-Type", "Authorization", "Content-Length", "User-Agent", "X-Goog-Upload-Protocol", "X-Goog-Upload-Command", "X-Goog-Upload-Offset", "X-Goog-Upload-Status"],
    "maxAgeSeconds": 3600
  }
]
"@
    $corsContent | Out-File -FilePath "cors.json" -Encoding UTF8
    Write-Host "✓ Arquivo cors.json criado" -ForegroundColor Green
    Write-Host ""
}

# Verificar se gsutil está instalado
Write-Host "Verificando se gsutil está instalado..." -ForegroundColor Yellow
$gsutilDisponivel = $false
try {
    $null = Get-Command gsutil -ErrorAction Stop
    $gsutilVersion = gsutil version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $gsutilDisponivel = $true
        Write-Host "✓ gsutil encontrado" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ gsutil não está instalado" -ForegroundColor Yellow
}

if (-not $gsutilDisponivel) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  CONFIGURAÇÃO MANUAL NECESSÁRIA" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "O gsutil não está instalado. Use a configuração MANUAL:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Acesse: https://console.cloud.google.com/storage/browser" -ForegroundColor White
    Write-Host "2. Selecione o bucket: exodo-system.firebasestorage.app" -ForegroundColor White
    Write-Host "3. Clique em 'Configurações' (ícone de engrenagem)" -ForegroundColor White
    Write-Host "4. Vá na aba 'CORS'" -ForegroundColor White
    Write-Host "5. Cole o conteúdo do arquivo cors.json:" -ForegroundColor White
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Get-Content "cors.json" | Write-Host -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "6. Clique em 'Salvar'" -ForegroundColor White
    Write-Host ""
    Write-Host "OU execute o script simplificado:" -ForegroundColor Cyan
    Write-Host "   .\configurar_cors_simples.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "OU leia as instruções detalhadas:" -ForegroundColor Cyan
    Write-Host "   Abra: INSTRUCOES_CORS_MANUAL.md" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Verificar se o arquivo cors.json existe
if (-not (Test-Path "cors.json")) {
    Write-Host "✗ Arquivo cors.json não encontrado!" -ForegroundColor Red
    Write-Host "Criando arquivo cors.json..." -ForegroundColor Yellow
    # O arquivo já foi criado acima
}

Write-Host ""
Write-Host "Bucket do Firebase Storage: exodo-system.firebasestorage.app" -ForegroundColor Cyan
Write-Host ""

# Configurar CORS
Write-Host "Configurando CORS no Firebase Storage..." -ForegroundColor Yellow
Write-Host "Isso pode levar alguns segundos..." -ForegroundColor Yellow
Write-Host ""

try {
    gsutil cors set cors.json gs://exodo-system.firebasestorage.app
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  ✅ CORS CONFIGURADO COM SUCESSO!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Aguarde 1-2 minutos para a propagação..." -ForegroundColor Yellow
        Write-Host "Depois, teste o upload de imagens novamente." -ForegroundColor Yellow
        Write-Host ""
    } else {
        throw "Erro ao configurar CORS"
    }
} catch {
    Write-Host ""
    Write-Host "✗ Erro ao configurar CORS: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Tente configurar manualmente:" -ForegroundColor Yellow
    Write-Host "1. Acesse: https://console.cloud.google.com/storage/browser" -ForegroundColor Yellow
    Write-Host "2. Selecione o bucket: exodo-system.firebasestorage.app" -ForegroundColor Yellow
    Write-Host "3. Vá em 'Configurações' > 'CORS'" -ForegroundColor Yellow
    Write-Host "4. Cole o conteúdo do arquivo cors.json" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}


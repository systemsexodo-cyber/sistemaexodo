# Script SIMPLIFICADO para configurar CORS no Firebase Storage
# Se este script falhar, use a opção manual no Google Cloud Console

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURAR CORS NO FIREBASE STORAGE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se o arquivo cors.json existe
if (-not (Test-Path "cors.json")) {
    Write-Host "✗ Arquivo cors.json não encontrado!" -ForegroundColor Red
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
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  OPÇÃO 1: CONFIGURAÇÃO MANUAL (RECOMENDADO)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Siga estes passos:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Abra o Google Cloud Console:" -ForegroundColor White
Write-Host "   https://console.cloud.google.com/storage/browser" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Selecione o bucket:" -ForegroundColor White
Write-Host "   exodo-system.firebasestorage.app" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Clique em 'Configurações' (ícone de engrenagem)" -ForegroundColor White
Write-Host ""
Write-Host "4. Vá na aba 'CORS'" -ForegroundColor White
Write-Host ""
Write-Host "5. Clique em 'Editar' ou 'Adicionar configuração CORS'" -ForegroundColor White
Write-Host ""
Write-Host "6. Cole o conteúdo abaixo:" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Get-Content "cors.json" | Write-Host -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "7. Clique em 'Salvar'" -ForegroundColor White
Write-Host ""
Write-Host "8. Aguarde 1-2 minutos e teste o upload novamente" -ForegroundColor White
Write-Host ""

# Tentar usar gsutil se estiver disponível
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  OPÇÃO 2: TENTAR CONFIGURAÇÃO AUTOMÁTICA" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$gsutilDisponivel = $false
try {
    $null = Get-Command gsutil -ErrorAction Stop
    $gsutilDisponivel = $true
    Write-Host "✓ gsutil encontrado" -ForegroundColor Green
} catch {
    Write-Host "✗ gsutil não está instalado" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Para instalar o Google Cloud SDK:" -ForegroundColor Yellow
    Write-Host "1. Baixe em: https://cloud.google.com/sdk/docs/install" -ForegroundColor Cyan
    Write-Host "2. Ou use a Opção 1 (Manual) acima" -ForegroundColor Cyan
    Write-Host ""
}

if ($gsutilDisponivel) {
    Write-Host "Tentando configurar CORS automaticamente..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $result = gsutil cors set cors.json gs://exodo-system.firebasestorage.app 2>&1
        
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
            Write-Host ""
            Write-Host "✗ Erro ao configurar CORS automaticamente" -ForegroundColor Red
            Write-Host "Use a Opção 1 (Manual) acima" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Detalhes do erro:" -ForegroundColor Yellow
            Write-Host $result -ForegroundColor Red
            Write-Host ""
        }
    } catch {
        Write-Host ""
        Write-Host "✗ Erro ao executar gsutil: $_" -ForegroundColor Red
        Write-Host "Use a Opção 1 (Manual) acima" -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PRÓXIMOS PASSOS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Configure CORS (usando Opção 1 ou 2 acima)" -ForegroundColor White
Write-Host "2. Aguarde 1-2 minutos" -ForegroundColor White
Write-Host "3. Limpe o cache do navegador (Ctrl + Shift + Delete)" -ForegroundColor White
Write-Host "4. Recarregue a página (Ctrl + Shift + R)" -ForegroundColor White
Write-Host "5. Teste o upload de imagens novamente" -ForegroundColor White
Write-Host ""


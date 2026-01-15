# Script para fazer deploy das regras do Firebase Storage
# Execute: .\deploy_storage_rules.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deploy das Regras do Firebase Storage" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se Firebase CLI está instalado
try {
    $firebaseVersion = firebase --version
    Write-Host "✅ Firebase CLI encontrado: $firebaseVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Firebase CLI não encontrado!" -ForegroundColor Red
    Write-Host "Instale com: npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Fazendo deploy das regras de Storage..." -ForegroundColor Yellow
Write-Host ""

# Fazer deploy apenas das regras de Storage
firebase deploy --only storage

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Deploy concluído com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verifique no Firebase Console:" -ForegroundColor Cyan
    Write-Host "https://console.firebase.google.com" -ForegroundColor Cyan
    Write-Host "Storage > Rules" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "❌ Erro no deploy!" -ForegroundColor Red
    Write-Host "Verifique se está logado: firebase login" -ForegroundColor Yellow
}

Write-Host ""



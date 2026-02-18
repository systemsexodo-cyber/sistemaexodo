# Script de Deploy para Firebase (Hosting + Functions)
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY FIREBASE (HOSTING + FUNCTIONS)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Instalar dependências das funções
Write-Host "`n[1/3] Instalando dependências das Cloud Functions..." -ForegroundColor Yellow
Set-Location functions
npm install
Set-Location ..

# 2. Build Flutter Web
Write-Host "`n[2/3] Construindo Flutter Web..." -ForegroundColor Yellow
flutter build web --release

# 3. Deploy para Firebase
Write-Host "`n[3/3] Fazendo deploy para Firebase..." -ForegroundColor Yellow
firebase deploy --only hosting, functions

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  DEPLOY CONCLUÍDO COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Script para instalar dependencias de C++ para o Flutter Windows
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Instalando Ferramentas C++ para Flutter (Visual Studio)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Por favor, aguarde. Uma barra de progresso sera mostrada." -ForegroundColor Yellow
Write-Host "O download tem cerca de 2GB e pode demorar dependendo da sua internet." -ForegroundColor Yellow
Write-Host ""

# Executar instalacao via Winget
winget install Microsoft.VisualStudio.2022.BuildTools --force --accept-package-agreements --accept-source-agreements --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.Windows10SDK.19041"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Instalacao concluida! O Flutter ja pode compilar para Windows." -ForegroundColor Green
Write-Host "Apenas feche esta janela, abra o VS Code e rode o atalho EXODO_WINDOWS.bat" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
pause

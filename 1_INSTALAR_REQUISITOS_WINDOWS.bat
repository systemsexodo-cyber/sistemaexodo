@echo off
color 0a
echo =========================================================
echo   INSTALACAO DOS REQUISITOS (C++) PARA FLUTTER NO WINDOWS
echo =========================================================
echo.
echo Para construir o app no Windows, o Flutter precisa
echo do Visual Studio Build Tools e C++.
echo.
echo Pressione qualquer tecla para SOLICITAR PERMISSAO DE ADMINISTRADOR e iniciar o download (sao ~2GB).
pause

:: Rodar PS como admin para o winget
powershell -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoExit -Command \"Write-Host ''Baixando e Instalando Ferramentas C++...''; winget install Microsoft.VisualStudio.2022.BuildTools --force --accept-package-agreements --accept-source-agreements --override ''--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.Windows10SDK.19041''; Write-Host ''Concluido! Pode fechar esta aba.''; pause\"'"

echo.
echo Processo iniciado em uma nova tela (tela azul do Administrador). 
echo Quando ela terminar, voce ja tem os dependencias necessarias!
pause

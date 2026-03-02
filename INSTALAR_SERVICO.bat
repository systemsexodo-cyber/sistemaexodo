@echo off
title Instalar Servico de Emissao Exodo
echo ===========================================
echo   INSTALACAO DO SERVICO DE BACKGROUND
echo ===========================================
echo.

:: Verifica se o terminal esta como admin
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Permissao de Administrador confirmada.
) else (
    echo [ERRO] Por favor, execute este arquivo clicando com o BOTAO DIREITO
    echo        e selecionando 'EXECUTAR COMO ADMINISTRADOR'.
    echo.
    pause
    exit
)

cd /d "%~dp0"
cd backend_nfce

echo Instalando dependencias do servico...
pip install pywin32 pystray pillow

echo.
echo Registrando e iniciando o servico 'ExodoNfceBridge'...
echo.

:: Tenta instalar o servico usando o script Python
python windows_service.py install
python windows_service.py --startup auto install

echo.
echo Iniciando o servico agora...
python windows_service.py start

echo.
echo ===========================================
echo   INSTALACAO CONCLUIDA!
echo ===========================================
echo.
echo O emissor agora roda invisiveis em segundo plano.
echo Ele vai iniciar sozinho toda vez que ligar o PC.
echo.
pause

@echo off
title Criar Instalador Exodo Nfce Bridge
echo ===========================================
echo       GERANDO EXECUTAVEL DO EMISSOR
echo ===========================================
echo.

cd /d "%~dp0"
cd backend_nfce

echo [1/3] Instalando PyInstaller...
pip install pyinstaller

echo.
echo [2/3] Criando executavel unico (EXE)...
echo Isso pode levar alguns minutos...
echo.

:: --noconsole: Esconde a janela preta
:: --onefile: Gera apenas um arquivo .exe
:: --hidden-import: Garante que bibliotecas dinamicas sejam inclusas
:: --collect-all: Garante que o firebase e outras dependencias pesadas sejam inclusas
pyinstaller --clean "ExodoNfceBridge.spec"

echo.
echo [3/3] Finalizado!
echo O executavel foi gerado na pasta: backend_nfce\dist\ExodoNfceBridge.exe
echo.
echo Copie o ExodoNfceBridge.exe para qualquer lugar do PC e execute-o.
echo Ele ira se auto-instalar para iniciar com o Windows.
echo.
pause

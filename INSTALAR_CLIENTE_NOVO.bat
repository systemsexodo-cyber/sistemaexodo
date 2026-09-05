@echo off
title Instalar Emissor NFC-e Exodo
echo ==================================================
echo    INSTALADOR RAPIDO PARA CLIENTES NOVOS
echo ==================================================
echo.

set EXE_NAME=ExodoNfceBridge.exe
set INSTALL_DIR=%AppData%\ExodoNfce

if not exist %EXE_NAME% (
    echo [ERRO] Arquivo %EXE_NAME% nao encontrado nesta pasta!
    echo Certifique-se de copiar o .exe junto com este instalador.
    pause
    exit
)

echo 1. Criando pasta de instalacao...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo 2. Copiando executavel...
copy /Y "%EXE_NAME%" "%INSTALL_DIR%\" > nul

echo 3. Configurando inicio automatico com o Windows...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "ExodoNfceBridge" /t REG_SZ /d "\"%INSTALL_DIR%\%EXE_NAME%\"" /f > nul

echo 4. Iniciando o servidor agora...
start "" "%INSTALL_DIR%\%EXE_NAME%"

echo.
echo ==================================================
echo INSTALACAO CONCLUIDA COM SUCESSO!
echo O emissor ja esta rodando em segundo plano.
echo Local: %INSTALL_DIR%\%EXE_NAME%
echo ==================================================
echo.
pause

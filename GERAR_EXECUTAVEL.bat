@echo off
title Criar Instalador Exodo Nfce Bridge
echo ===========================================
echo       GERANDO EXECUTAVEL DO EMISSOR
echo ===========================================
echo.

cd /d "%~dp0"
cd backend_nfce

echo [1/3] Preparando ambiente...
:: Tentar usar o venv se existir
if exist "..\.venv\Scripts\python.exe" (
    set PYTHON_EXE=..\.venv\Scripts\python.exe
) else (
    set PYTHON_EXE=python
)

:: Extrair versao do main.py
for /f "tokens=3" %%V in ('findstr "BRIDGE_VERSION =" main.py') do set VERSION=%%~V
set VERSION=%VERSION:"=%
echo Versao detectada: %VERSION%

echo.
echo [2/3] Criando executavel unico (EXE)...
echo Isso pode levar alguns minutos...
echo.

%PYTHON_EXE% -m PyInstaller --clean --noconfirm "ExodoNfceBridge.spec"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERRO ao gerar executavel!
    pause
    exit /b
)

echo.
echo [3/3] Finalizado!
echo.
echo Renomeando para incluir versao...
set VER_CLEAN=%VERSION:.=%
copy /Y "dist\ExodoNfceBridge.exe" "dist\ExodoNfceBridge_v%VER_CLEAN%.exe"
copy /Y "dist\ExodoNfceBridgeWatchdog.exe" "dist\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe"

echo.
echo Copiando para a raiz...
copy /Y "dist\ExodoNfceBridge_v%VER_CLEAN%.exe" "..\ExodoNfceBridge_v%VER_CLEAN%.exe"
copy /Y "dist\ExodoNfceBridge_v%VER_CLEAN%.exe" "..\ExodoNfceBridge.exe"

echo.
echo EXECUTAVEL v%VERSION% GERADO COM SUCESSO!
echo Arquivos disponiveis em:
echo - backend_nfce\dist\ExodoNfceBridge_v%VER_CLEAN%.exe
echo - ExodoNfceBridge.exe (na raiz)
echo.
pause


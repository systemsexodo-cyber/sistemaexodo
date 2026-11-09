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
if exist "venv\Scripts\python.exe" (
    set PYTHON_EXE=venv\Scripts\python.exe
) else if exist "..\.venv\Scripts\python.exe" (
    set PYTHON_EXE=..\.venv\Scripts\python.exe
) else (
    set PYTHON_EXE=python
)

:: Extrair versao do main.py
:: ATENCAO: usar /B (inicio da linha) para casar SOMENTE a atribuicao
:: "BRIDGE_VERSION = ...". Sem /B o findstr tambem casava as linhas de
:: menu/bandeja (f"...{BRIDGE_VERSION}...") e o %%V final virava lixo
:: (ex.: "setup_tray()"), fazendo o script copiar um dist\ExodoNfceBridge.exe
:: ANTIGO para a raiz — era isso que fazia o EXE corrigido nunca ser gerado.
for /f "tokens=3" %%V in ('findstr /B /C:"BRIDGE_VERSION" main.py') do set VERSION=%%~V
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
set VER_CLEAN=%VERSION:.=%

:: O .spec ja gera o nome com a versao (ExodoNfceBridge_v358.exe).
:: Antes este script copiava "dist\ExodoNfceBridge.exe", que e um arquivo
:: ANTIGO deixado no dist por builds anteriores — ou seja, a raiz recebia
:: sempre o EXE velho (com bugs ja corrigidos no fonte).
if not exist "dist\ExodoNfceBridge_v%VER_CLEAN%.exe" (
    echo.
    echo ERRO: dist\ExodoNfceBridge_v%VER_CLEAN%.exe nao foi gerado!
    echo Verifique o nome do EXE no ExodoNfceBridge.spec.
    pause
    exit /b 1
)

echo.
echo Copiando para a raiz...
copy /Y "dist\ExodoNfceBridge_v%VER_CLEAN%.exe" "..\ExodoNfceBridge_v%VER_CLEAN%.exe"
if errorlevel 1 (
    echo ERRO ao copiar o EXE para a raiz!
    pause
    exit /b 1
)
copy /Y "dist\ExodoNfceBridge_v%VER_CLEAN%.exe" "..\ExodoNfceBridge.exe"
if errorlevel 1 (
    echo ERRO ao copiar o EXE para a raiz!
    pause
    exit /b 1
)
if exist "dist\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe" (
    copy /Y "dist\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe" "..\ExodoNfceBridgeWatchdog.exe"
    copy /Y "dist\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe" "..\ExodoNfceBridgeWatchdog_v%VER_CLEAN%.exe"
)

echo.
echo EXECUTAVEL v%VERSION% GERADO COM SUCESSO!
echo Arquivos disponiveis em:
echo - backend_nfce\dist\ExodoNfceBridge_v%VER_CLEAN%.exe
echo - ExodoNfceBridge.exe (na raiz)
echo.
pause


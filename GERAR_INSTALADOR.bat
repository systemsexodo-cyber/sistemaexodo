@echo off
chcp 65001 >nul
title Gerar Instalador Sistema Exodo v1.0.43
cls
echo.
echo ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
echo ???      GERAR INSTALADOR - SISTEMA EXODO v1.0.43              ???
echo ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
echo.

cd /d "%~dp0"

:: ============================================================
:: PASSO 1: Compilar App Flutter (Windows Release)
:: ============================================================
echo [1/5] Compilando App Flutter ^(Windows Release^)...
echo.

where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ??? Flutter nao encontrado no PATH!
    echo    Instale: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)

call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ??? ERRO ao compilar o App Flutter!
    pause
    exit /b 1
)
echo ??? App Flutter compilado com sucesso!
echo.

:: Verificar se o executavel foi gerado
if not exist "build\windows\x64\runner\Release\sistema_exodo_novo.exe" (
    echo ??? Executavel do app nao encontrado em build\windows\x64\runner\Release\
    pause
    exit /b 1
)

:: Copiar DLLs do VC Runtime para a pasta Release (necessario em maquinas sem VC)
echo [1b] Copiando DLLs do Visual C++ Runtime...
copy /Y "C:\Windows\System32\vcruntime140.dll" "build\windows\x64\runner\Release\" >nul 2>&1
copy /Y "C:\Windows\System32\vcruntime140_1.dll" "build\windows\x64\runner\Release\" >nul 2>&1
copy /Y "C:\Windows\System32\msvcp140.dll" "build\windows\x64\runner\Release\" >nul 2>&1
echo ??? DLLs do VC Runtime copiadas!
echo.

:: ============================================================
:: PASSO 2: Compilar Sincronizador Nuvem (PyInstaller onedir)
:: ============================================================
echo [2/5] Compilando Sincronizador Nuvem ^(PyInstaller onedir^)...
echo.

:: Verificar Python
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ??? Python nao encontrado!
    pause
    exit /b 1
)

:: Instalar dependencias do Sincronizador
:: ATENCAO: `requests` e OBRIGATORIO aqui. O sincronizador importa
:: `sincronizar_local_supabase`, que usa requests para falar com o Supabase. Sem
:: ele o executavel abre e morre com "No module named 'requests'" no PC do cliente.
pip install -q pyinstaller pystray psycopg2-binary python-dotenv pillow requests 2>nul

:: Limpar builds anteriores do Sincronizador
if exist "dist\SincronizadorNuvem" rmdir /s /q "dist\SincronizadorNuvem"
if exist "build\SincronizadorNuvem" rmdir /s /q "build\SincronizadorNuvem"

:: Compilar em modo ONEDIR (gera pasta com exe + _internal)
:: USA O .spec: ele declara hiddenimports=['requests'], que e o que faz o
:: PyInstaller embutir o pacote. A linha de comando pura nao tem isso.
if exist "SincronizadorNuvem.spec" (
    pyinstaller "SincronizadorNuvem.spec" --clean --noconfirm
) else (
    pyinstaller --name "SincronizadorNuvem" --noconsole --onedir sincronizador_tray.py --clean --noconfirm --hidden-import requests
)

:: Guarda contra o bug que chegou no cliente: um executavel sem `requests` sobe
:: e fecha com "No module named 'requests'" no PC da loja. Se faltar aqui, nao
:: vale nem gerar o instalador. Confere os modulos embutidos no PYZ do proprio
:: .exe - em _internal nao da para ver, o PyInstaller 6 guarda os pacotes
:: Python dentro do executavel.
python verificar_sincronizador.py
if %ERRORLEVEL% NEQ 0 (
    echo !!!  ERRO: o SincronizadorNuvem nao levou todos os modulos - veja a lista acima!
    echo     Isso reprovaria o instalador no PC da loja.
    pause
    exit /b 1
)


if not exist "dist\SincronizadorNuvem\SincronizadorNuvem.exe" (
    echo ??? ERRO ao compilar Sincronizador Nuvem!
    pause
    exit /b 1
)

:: Verificar se a pasta _internal foi criada
if not exist "dist\SincronizadorNuvem\_internal" (
    echo ??????  AVISO: pasta _internal nao encontrada no Sincronizador.
    echo    Verifique se o PyInstaller esta na versao correta ^(6.x+^).
)

echo ??? Sincronizador Nuvem compilado com sucesso!
echo.

:: ============================================================
:: PASSO 3: Compilar Bridge NFC-e (PyInstaller onefile)
:: ============================================================
echo [3/5] Compilando Bridge NFC-e...
echo.

cd /d "%~dp0backend_nfce"

:: Verificar/criar venv
if not exist "venv" (
    echo ???? Criando ambiente virtual...
    python -m venv venv
)

:: Ativar venv
call venv\Scripts\activate.bat

:: Instalar dependencias
pip install -q pyinstaller fastapi uvicorn pydantic requests pynfe signxml lxml cryptography pystray Pillow firebase-admin 2>nul

:: Limpar builds anteriores
if exist "build" rmdir /s /q "build"
if exist "dist\ExodoNfceBridge.exe" del /f /q "dist\ExodoNfceBridge.exe" 2>nul
if exist "dist\ExodoNfceBridgeWatchdog.exe" del /f /q "dist\ExodoNfceBridgeWatchdog.exe" 2>nul

:: Compilar usando o spec mais recente
if exist "ExodoNfceBridge.spec" (
    pyinstaller ExodoNfceBridge.spec --clean --noconfirm
) else (
    echo ??? Arquivo ExodoNfceBridge.spec nao encontrado!
    call venv\Scripts\deactivate.bat
    cd /d "%~dp0"
    pause
    exit /b 1
)

:: Verificar se compilado
:: O ExodoNfceBridge.spec versiona os nomes (ExodoNfceBridge_v356.exe), mas o
:: instalador e este proprio script esperam ExodoNfceBridge.exe. Sem espelhar a
:: versao nova aqui, o instalador sai SEM o bridge (o .iss pula arquivo ausente).
if not exist "dist\ExodoNfceBridge.exe" (
    for %%F in ("dist\ExodoNfceBridge_v*.exe") do if exist "%%F" copy /Y "%%F" "dist\ExodoNfceBridge.exe" >nul
)
if not exist "dist\ExodoNfceBridgeWatchdog.exe" (
    for %%F in ("dist\ExodoNfceBridgeWatchdog_v*.exe") do if exist "%%F" copy /Y "%%F" "dist\ExodoNfceBridgeWatchdog.exe" >nul
)
if not exist "dist\ExodoNfceBridge.exe" (
    echo ??? ERRO ao compilar Bridge NFC-e!
    call venv\Scripts\deactivate.bat
    cd /d "%~dp0"
    pause
    exit /b 1
)

echo ??? Bridge NFC-e compilado com sucesso!

:: Desativar venv
call venv\Scripts\deactivate.bat

:: Copiar para a pasta do projeto
copy /Y "dist\ExodoNfceBridge.exe" "..\ExodoNfceBridge.exe" >nul 2>&1

cd /d "%~dp0"
echo.

:: ============================================================
:: PASSO 4: Verificar Inno Setup
:: ============================================================
echo [4/5] Verificando Inno Setup...
echo.

set "ISCC_PATH="

:: Procurar Inno Setup em locais comuns (v7 > v6 > v5)
if exist "C:\Program Files\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 5\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 5\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 5\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
)

if "%ISCC_PATH%"=="" (
    echo ??? Inno Setup NAO encontrado!
    echo.
    echo    Para gerar o instalador, instale o Inno Setup:
    echo    https://jrsoftware.org/isdl.php
    echo.
    echo    Depois execute novamente este script.
    pause
    exit /b 1
)

echo ??? Inno Setup encontrado: %ISCC_PATH%
echo.

:: ============================================================
:: PASSO 5: Compilar o Instalador (Inno Setup)
:: ============================================================
echo [5/5] Compilando instalador Inno Setup v1.0.43...
echo.

:: Criar pasta de saida
if not exist "dist\instalador" mkdir "dist\instalador"

:: Compilar o .iss
"%ISCC_PATH%" "Instalador_Exodo_Completo.iss"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ??? ERRO ao compilar o instalador!
    echo    Verifique os erros acima.
    pause
    exit /b 1
)

:: ============================================================
:: RESULTADO
:: ============================================================
echo.
echo ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
echo ???           INSTALADOR GERADO COM SUCESSO!                    ???
echo ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
echo.
echo ???? Arquivo gerado:
echo    dist\instalador\Setup_Sistema_Exodo_v1.0.43.exe
echo.
echo ???? Versao: 1.0.43
echo ???? Componentes incluidos:
echo    - Sistema Exodo ^(PDV + Gestao^)
echo    - PostgreSQL 16 ^(banco de dados^)
echo    - Bridge NFC-e ^(nota fiscal^)
echo    - Sincronizador Nuvem
echo    - Scripts de manutencao
echo.
echo O instalador esta pronto para distribuicao!
echo.
pause

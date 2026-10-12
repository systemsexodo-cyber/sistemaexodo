@echo off
:: Compilar em modo ONEDIR (gera pasta com exe + _internal)
if exist "SincronizadorNuvem.spec" (
    pyinstaller "SincronizadorNuvem.spec" --clean --noconfirm
) else (
    pyinstaller --name "SincronizadorNuvem" --noconsole --onedir sincronizador_tray.py --clean --noconfirm --hidden-import requests
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

@echo off
title Compilando Sincronizador Nuvem
echo ========================================================
echo     COMPILANDO SERVICO TRAY ^(Sincronizador Nuvem^)
echo ========================================================
echo.

:: Verifica se pyinstaller esta instalado
pip install pyinstaller pystray psycopg2-binary python-dotenv pillow requests

echo Compilando com PyInstaller...
rem MODO ONEDIR: roda direto da propria pasta, sem extrair para a pasta temporaria _MEI
rem (elimina o aviso "Failed to remove temporary directory" no Windows)
rem USA O .spec: ele declara hiddenimports=['requests'] - sem isso o executavel
rem abre no PC do cliente e fecha com "No module named 'requests'".
if exist "SincronizadorNuvem.spec" (
    pyinstaller "SincronizadorNuvem.spec" --clean --noconfirm
) else (
    pyinstaller --name "SincronizadorNuvem" --noconsole --onedir sincronizador_tray.py --clean --noconfirm --hidden-import requests
)

rem Guarda: o executavel sem `requests` abre no PC do cliente e fecha com
rem "No module named 'requests'". Confere os modulos embutidos no PYZ do exe.
python verificar_sincronizador.py
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  ERRO: o SincronizadorNuvem nao levou todos os modulos!
    echo    Rode:  pip install requests   e compile de novo.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo Compilacao concluida! 
echo O executavel e a pasta _internal estao em "dist\SincronizadorNuvem\".
echo NAO copie apenas o .exe - leve a pasta completa ^(o exe precisa do _internal^).
echo ========================================================
pause

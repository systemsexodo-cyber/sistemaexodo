@echo off
title Compilando Sincronizador Nuvem
echo ========================================================
echo     COMPILANDO SERVICO TRAY (Sincronizador Nuvem)
echo ========================================================
echo.

:: Verifica se pyinstaller esta instalado
pip install pyinstaller pystray psycopg2-binary python-dotenv pillow

echo Compilando com PyInstaller...
rem MODO ONEDIR: roda direto da propria pasta, sem extrair para a pasta temporaria _MEI
rem (elimina o aviso "Failed to remove temporary directory" no Windows)
pyinstaller --name "SincronizadorNuvem" --noconsole --onedir sincronizador_tray.py

echo.
echo ========================================================
echo Compilacao concluida! 
echo O executavel e a pasta _internal estao em "dist\SincronizadorNuvem\".
echo NAO copie apenas o .exe - leve a pasta completa (o exe precisa do _internal).
echo ========================================================
pause

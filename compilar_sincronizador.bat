@echo off
title Compilando Sincronizador Nuvem
echo ========================================================
echo     COMPILANDO SERVICO TRAY (Sincronizador Nuvem)
echo ========================================================
echo.

:: Verifica se pyinstaller esta instalado
pip install pyinstaller pystray psycopg2-binary python-dotenv pillow

echo Compilando com PyInstaller...
pyinstaller --name "SincronizadorNuvem" --noconsole --onefile sincronizador_tray.py

echo.
echo ========================================================
echo Compilacao concluida! 
echo O executavel esta na pasta "dist\SincronizadorNuvem.exe".
echo Copie este executavel para os computadores e coloque no 
echo iniciar do Windows.
echo ========================================================
pause

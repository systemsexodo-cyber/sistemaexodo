@echo off
cd /d "%~dp0"
echo ========================================
echo Instalando PyNFe
echo ========================================
echo.
echo Isso pode levar 5-10 minutos...
echo NAO FECHE ESTA JANELA!
echo.
call venv\Scripts\python.exe -m pip install git+https://github.com/TadaSoftware/PyNFe.git
echo.
echo ========================================
echo Verificando instalacao...
echo ========================================
call venv\Scripts\python.exe verificar_pynfe.py
echo.
pause



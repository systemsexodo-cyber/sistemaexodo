@echo off
echo ========================================
echo Reiniciando Servidor NFC-e
echo ========================================
echo.
echo Pressione Ctrl+C se o servidor estiver rodando
echo.
pause
echo.
echo Iniciando servidor...
echo.
cd /d "%~dp0"
python app.py
pause


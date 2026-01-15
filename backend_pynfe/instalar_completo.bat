@echo off
echo ========================================
echo INSTALACAO SISTEMA COMPLETO NFC-e
echo ========================================
echo.
echo Sistema 100%% Local
echo Funciona em Producao e Homologacao
echo Sem dependencia de APIs de terceiros
echo.

cd /d "%~dp0"

if not exist "venv" (
    echo Criando ambiente virtual...
    python -m venv venv
)

call venv\Scripts\activate.bat

echo.
echo Instalando dependencias...
pip install Flask==3.0.0 Flask-CORS==4.0.0
pip install lxml==4.9.3 zeep==4.2.1
pip install cryptography==41.0.7

echo.
echo ========================================
echo INSTALACAO CONCLUIDA!
echo ========================================
echo.
echo Para iniciar:
echo   python app_nfce_completo.py
echo.
pause





















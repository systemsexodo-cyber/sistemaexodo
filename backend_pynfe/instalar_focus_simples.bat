@echo off
echo ========================================
echo INSTALACAO SIMPLIFICADA - Focus NFe API
echo ========================================
echo.

cd /d "%~dp0"

REM Verificar se venv existe
if not exist "venv" (
    echo Criando ambiente virtual...
    python -m venv venv
)

REM Ativar venv
call venv\Scripts\activate.bat

echo.
echo Instalando dependencias basicas...
pip install Flask==3.0.0 Flask-CORS==4.0.0 python-dotenv==1.0.0 requests==2.31.0

echo.
echo ========================================
echo INSTALACAO CONCLUIDA!
echo ========================================
echo.
echo PROXIMOS PASSOS:
echo 1. Obtenha um token em: https://focusnfe.com.br
echo 2. Configure no arquivo .env: FOCUSNFE_TOKEN=seu_token
echo 3. Execute: python app_simples_focus.py
echo.
pause





















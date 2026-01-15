@echo off
echo ========================================
echo INSTALACAO GRATUITA - PyTrustNFe
echo ========================================
echo.
echo Esta solucao e 100%% GRATUITA e funciona
echo localmente, sem APIs pagas!
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
echo Instalando dependencias...
pip install Flask==3.0.0 Flask-CORS==4.0.0 python-dotenv==1.0.0 requests==2.31.0 lxml==4.9.3 zeep==4.2.1

echo.
echo Instalando PyTrustNFe (biblioteca gratuita)...
pip install PyTrustNFe

echo.
echo ========================================
echo INSTALACAO CONCLUIDA!
echo ========================================
echo.
echo PROXIMOS PASSOS:
echo 1. Execute: python app_gratuito.py
echo 2. Use o endpoint: POST http://localhost:5000/api/nfce/emitir
echo.
echo IMPORTANTE:
echo - Voce precisa de um certificado digital A1 (.pfx)
echo - Configure no JSON: certificado_base64 e senha_certificado
echo.
pause





















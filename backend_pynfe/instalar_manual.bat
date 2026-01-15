@echo off
echo ========================================
echo INSTALACAO MANUAL - 100%% LOCAL
echo ========================================
echo.
echo Esta solucao e 100%% LOCAL e funciona
echo sem APIs de terceiros!
echo.
echo O codigo faz TUDO:
echo   - Gera o XML da NFC-e
echo   - Assina com certificado
echo   - Envia para SEFAZ
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
pip install Flask==3.0.0 Flask-CORS==4.0.0 python-dotenv==1.0.0
pip install lxml==4.9.3
pip install cryptography==41.0.7
pip install zeep==4.2.1

echo.
echo ========================================
echo INSTALACAO CONCLUIDA!
echo ========================================
echo.
echo PROXIMOS PASSOS:
echo 1. Execute: python app_manual.py
echo 2. Use o endpoint: POST http://localhost:5000/api/nfce/emitir
echo.
echo IMPORTANTE:
echo - Voce precisa de um certificado digital A1 (.pfx)
echo - Configure no JSON: certificado_base64 e senha_certificado
echo - Configure numero_nfce e serie_nfce na empresa
echo.
pause





















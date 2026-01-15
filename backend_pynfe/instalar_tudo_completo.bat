@echo off
echo ========================================
echo INSTALACAO COMPLETA - Backend PyNFe
echo ========================================
echo.

cd /d "%~dp0"

echo 1. Criando ambiente virtual...
if not exist "venv" (
    python -m venv venv
    echo    ✅ Ambiente virtual criado
) else (
    echo    ✅ Ambiente virtual já existe
)

echo.
echo 2. Ativando ambiente virtual...
call venv\Scripts\activate.bat

echo.
echo 3. Atualizando pip...
python -m pip install --upgrade pip setuptools wheel

echo.
echo 4. Instalando dependências básicas...
pip install Flask==3.0.0 Flask-CORS==4.0.0 lxml==4.9.3 requests==2.31.0 python-dotenv==1.0.0

echo.
echo 5. Instalando dependências de certificado...
pip install cryptography==41.0.7 pyOpenSSL==23.3.0

echo.
echo 6. Instalando dependências XML...
pip install zeep==4.2.1 signxml defusedxml

echo.
echo 7. Instalando PyNFe do GitHub...
pip install git+https://github.com/TadaSoftware/PyNFe.git

echo.
echo 8. Verificando instalação...
python -c "import pynfe; print('✅ PyNFe instalado:', pynfe.__file__)" 2>nul
if %errorlevel% neq 0 (
    echo    ❌ PyNFe não foi instalado corretamente
    pause
    exit /b 1
)

python -c "import signxml; print('✅ signxml instalado')" 2>nul
if %errorlevel% neq 0 (
    echo    ❌ signxml não foi instalado
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✅ INSTALAÇÃO COMPLETA!
echo ========================================
echo.
echo Para iniciar o servidor:
echo   .\iniciar_simples.bat
echo.
pause


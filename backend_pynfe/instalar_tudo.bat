@echo off
echo ========================================
echo Instalando Backend NFC-e
echo ========================================
echo.

REM Atualizar PATH
for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set "SYSTEM_PATH=%%B"
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path') do set "USER_PATH=%%B"
set "PATH=%SYSTEM_PATH%;%USER_PATH%"

echo Verificando Python...
python --version
if errorlevel 1 (
    echo ERRO: Python nao encontrado!
    echo Instale Python primeiro: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo.
echo Criando ambiente virtual...
if exist venv (
    echo Ambiente virtual ja existe. Removendo...
    rmdir /s /q venv
)
python -m venv venv

echo.
echo Ativando ambiente virtual...
call venv\Scripts\activate.bat

echo.
echo Atualizando pip...
python -m pip install --upgrade pip setuptools wheel

echo.
echo Instalando dependencias basicas...
python -m pip install Flask==3.0.0 Flask-CORS==4.0.0
python -m pip install lxml==4.9.3 requests==2.31.0
python -m pip install python-dotenv==1.0.0
python -m pip install cryptography==41.0.7 pyOpenSSL==23.3.0
python -m pip install zeep==4.2.1

echo.
echo Tentando instalar PyNFe do GitHub...
python -m pip install git+https://github.com/TadaSoftware/PyNFe.git
if errorlevel 1 (
    echo.
    echo AVISO: PyNFe nao foi instalado automaticamente.
    echo Instale manualmente: pip install git+https://github.com/TadaSoftware/PyNFe.git
)

echo.
echo Criando arquivo .env...
if not exist .env (
    copy .env.example .env
    echo Arquivo .env criado!
)

echo.
echo ========================================
echo Instalacao concluida!
echo ========================================
echo.
echo Para iniciar o servidor, execute:
echo   start_local.bat
echo.
pause



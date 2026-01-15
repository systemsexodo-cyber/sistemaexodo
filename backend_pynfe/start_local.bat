@echo off
echo ========================================
echo Iniciando Backend NFC-e (Local)
echo ========================================
echo.

REM Verificar se o ambiente virtual existe
if not exist "venv" (
    echo Criando ambiente virtual...
    python -m venv venv
)

REM Ativar ambiente virtual
echo Ativando ambiente virtual...
call venv\Scripts\activate.bat

REM Verificar se as dependências estão instaladas
echo Verificando dependencias...
pip show flask >nul 2>&1
if errorlevel 1 (
    echo Instalando dependencias...
    pip install -r requirements.txt
    echo.
    echo Instalando PyNFe do GitHub (versao oficial leotada)...
    pip install https://github.com/leotada/PyNFe/archive/master.zip
)

REM Criar arquivo .env se não existir
if not exist ".env" (
    echo Criando arquivo .env...
    copy .env.example .env
    echo.
    echo ATENCAO: Configure o arquivo .env com suas configuracoes!
)

echo.
echo ========================================
echo Iniciando servidor...
echo ========================================
echo.
echo Servidor sera iniciado em: http://localhost:5000
echo Pressione Ctrl+C para parar
echo.

python app.py

pause



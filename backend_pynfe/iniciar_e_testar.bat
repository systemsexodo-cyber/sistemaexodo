@echo off
echo ========================================
echo Iniciando Backend NFC-e e Testando
echo ========================================
echo.

REM Verificar Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python nao encontrado!
    echo Instale Python 3.8+ e tente novamente.
    pause
    exit /b 1
)

echo [OK] Python encontrado
python --version

REM Verificar se estamos no diretorio correto
if not exist "app.py" (
    echo [ERRO] Arquivo app.py nao encontrado!
    echo Execute este script da pasta backend_pynfe
    pause
    exit /b 1
)

REM Verificar dependencias
echo.
echo Verificando dependencias...
pip show flask >nul 2>&1
if errorlevel 1 (
    echo Instalando dependencias basicas...
    pip install flask flask-cors python-dotenv requests lxml
)

pip show nfelib >nul 2>&1
if errorlevel 1 (
    echo.
    echo [AVISO] nfelib nao esta instalado!
    echo Instalando nfelib e dependencias...
    pip install nfelib signxml cryptography
)

echo.
echo ========================================
echo Iniciando servidor...
echo ========================================
echo.
echo Servidor sera iniciado em: http://localhost:5000
echo.
echo Para testar, abra em outro terminal:
echo   curl http://localhost:5000/health
echo.
echo Pressione Ctrl+C para parar
echo.

python app.py

pause










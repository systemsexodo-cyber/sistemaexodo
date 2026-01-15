@echo off
echo ========================================
echo Iniciando Backend NFC-e Python
echo ========================================
echo.

REM Verificar se Python esta instalado
python --version >nul 2>&1
if %errorlevel% neq 0 (
    python3 --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo ERRO: Python nao encontrado!
        echo.
        echo Instale Python 3.10+ de: https://www.python.org/downloads/
        echo Lembre-se de marcar "Add Python to PATH" durante a instalacao!
        pause
        exit /b 1
    )
    set PYTHON_CMD=python3
) else (
    set PYTHON_CMD=python
)

echo [1/3] Verificando dependencias...
%PYTHON_CMD% -m pip show flask >nul 2>&1
if %errorlevel% neq 0 (
    echo Instalando dependencias...
    %PYTHON_CMD% -m pip install -r requirements.txt
    if %errorlevel% neq 0 (
        echo ERRO: Falha ao instalar dependencias!
        pause
        exit /b 1
    )
) else (
    echo Dependencias OK!
)

echo.
echo [2/3] Verificando arquivo app.py...
if not exist app.py (
    echo ERRO: app.py nao encontrado!
    echo Execute este script na pasta backend_pynfe
    pause
    exit /b 1
)

echo.
echo [3/3] Iniciando servidor...
echo.
echo ========================================
echo Backend NFC-e iniciando em:
echo   http://localhost:5000
echo.
echo Pressione Ctrl+C para parar
echo ========================================
echo.

%PYTHON_CMD% app.py

pause












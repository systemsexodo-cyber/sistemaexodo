@echo off
echo ========================================
echo DIAGNOSTICO DO BACKEND PYTHON
echo ========================================
echo.

cd /d "%~dp0"

echo 1. Verificando Python...
venv\Scripts\python.exe --version
if errorlevel 1 (
    echo ❌ Python nao encontrado!
    pause
    exit /b 1
)
echo ✅ Python OK
echo.

echo 2. Verificando Flask...
venv\Scripts\python.exe -c "import flask; print('✅ Flask OK')" 2>&1
if errorlevel 1 (
    echo ❌ Flask nao instalado!
    echo Instalando Flask...
    venv\Scripts\python.exe -m pip install flask flask-cors
)
echo.

echo 3. Verificando PyNFe...
venv\Scripts\python.exe -c "import pynfe; print('✅ PyNFe OK')" 2>&1
if errorlevel 1 (
    echo ⚠️ PyNFe nao instalado (servidor pode rodar sem ele)
)
echo.

echo 4. Verificando arquivo app.py...
if not exist "app.py" (
    echo ❌ app.py nao encontrado!
    pause
    exit /b 1
)
echo ✅ app.py encontrado
echo.

echo 5. Verificando sintaxe do Python...
venv\Scripts\python.exe -m py_compile app.py 2>&1
if errorlevel 1 (
    echo ❌ Erro de sintaxe no app.py!
    pause
    exit /b 1
)
echo ✅ Sintaxe OK
echo.

echo 6. Tentando importar app.py...
venv\Scripts\python.exe -c "import sys; sys.path.insert(0, '.'); import app; print('✅ app.py pode ser importado')" 2>&1
if errorlevel 1 (
    echo ❌ Erro ao importar app.py!
    echo.
    echo Verifique os erros acima.
    pause
    exit /b 1
)
echo.

echo ========================================
echo ✅ DIAGNOSTICO CONCLUIDO
echo ========================================
echo.
echo Se tudo estiver OK, tente iniciar o servidor:
echo   start_local.bat
echo.
pause



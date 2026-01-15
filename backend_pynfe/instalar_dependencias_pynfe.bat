@echo off
echo ========================================
echo Instalando Dependencias do PyNFe
echo ========================================
echo.

cd /d "%~dp0"

echo 1. Instalando signxml...
call venv\Scripts\python.exe -m pip install signxml
if errorlevel 1 (
    echo ❌ Erro ao instalar signxml!
    pause
    exit /b 1
)
echo ✅ signxml instalado
echo.

echo 2. Instalando defusedxml...
call venv\Scripts\python.exe -m pip install defusedxml
if errorlevel 1 (
    echo ⚠️ Aviso: defusedxml pode não ser necessário
)
echo.

echo 3. Instalando outras dependencias...
call venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 (
    echo ⚠️ Algumas dependencias podem falhar (normal)
)
echo.

echo 4. Verificando instalacao...
call venv\Scripts\python.exe verificar_pynfe_completo.py
echo.

echo ========================================
echo ✅ Instalacao concluida!
echo ========================================
echo.
echo Agora REINICIE o servidor para detectar as dependencias!
echo.
pause



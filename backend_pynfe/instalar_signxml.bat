@echo off
echo ========================================
echo Instalando signxml (dependencia do PyNFe)
echo ========================================
echo.

cd /d "%~dp0"

echo Instalando signxml...
call venv\Scripts\python.exe -m pip install signxml

if errorlevel 1 (
    echo.
    echo ❌ Erro ao instalar signxml!
    pause
    exit /b 1
)

echo.
echo ✅ signxml instalado com sucesso!
echo.
echo ========================================
echo IMPORTANTE: REINICIE O SERVIDOR!
echo ========================================
echo.
echo 1. Pare o servidor atual (Ctrl+C)
echo 2. Execute: .\iniciar_simples.bat
echo.
pause



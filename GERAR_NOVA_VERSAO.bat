@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    GERAR NOVA VERSAO DO BRIDGE NFC-e
echo ============================================
echo.
echo Versao atual: v352
echo Nova versao:  v353
echo.

:: Verificar Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python nao encontrado!
    pause
    exit /b 1
)

cd /d "%~dp0backend_nfce"

:: Verificar/criar venv
if not exist "venv" (
    echo 📦 Criando ambiente virtual...
    python -m venv venv
)

:: Ativar venv
call venv\Scripts\activate.bat

:: Instalar dependencias
echo 📦 Instalando dependencias...
pip install -q pyinstaller fastapi uvicorn pydantic requests pynfe signxml lxml cryptography pystray Pillow firebase-admin

:: Limpar builds anteriores
echo 🧹 Limpando builds anteriores...
if exist "build" rmdir /s /q "build"
if exist "dist" rmdir /s /q "dist"

:: Usar arquivo spec existente
echo 📝 Usando arquivo de configuracao ExodoNfceBridge_v353.spec...

:: Compilar
echo 🔨 Compilando Bridge v353...
pyinstaller ExodoNfceBridge_v353.spec --clean --noconfirm

:: Verificar se compilou
echo.
if exist "dist\ExodoNfceBridge_v353.exe" (
    echo ✅ Compilacao concluida com sucesso!
    echo.
    echo 📋 Arquivo gerado:
    echo    dist\ExodoNfceBridge_v353.exe
    echo.
    echo 📝 Para usar:
    echo    1. Copie para a pasta principal do projeto
    echo    2. Execute: ExodoNfceBridge_v353.exe
    echo.
    :: Copiar para pasta raiz automaticamente
    copy /Y "dist\ExodoNfceBridge_v353.exe" "..\ExodoNfceBridge_v353.exe"
    copy /Y "dist\ExodoNfceBridge_v353.exe" "..\ExodoNfceBridge.exe"
    echo ✅ Copiado para pasta principal!
) else (
    echo ❌ Erro na compilacao!
    echo Verifique os erros acima.
)

:: Desativar venv
call venv\Scripts\deactivate.bat

echo.
pause

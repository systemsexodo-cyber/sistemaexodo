@echo off
echo ========================================
echo Instalando PyNFe do GitHub
echo ========================================
echo.

REM Verificar se o ambiente virtual existe
if not exist "venv" (
    echo ❌ Ambiente virtual não encontrado!
    echo Execute primeiro: instalar_tudo.bat
    pause
    exit /b 1
)

REM Ativar ambiente virtual
echo Ativando ambiente virtual...
call venv\Scripts\activate.bat

REM Verificar se Git está instalado
where git >nul 2>&1
if errorlevel 1 (
    echo ❌ Git não está instalado!
    echo PyNFe precisa do Git para ser instalado do GitHub.
    echo.
    echo Instale o Git de: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo.
echo ✅ Git encontrado
echo.

REM Atualizar pip
echo Atualizando pip...
python -m pip install --upgrade pip

echo.
echo ========================================
echo Instalando PyNFe do GitHub...
echo ========================================
echo.
echo Isso pode levar alguns minutos...
echo.

python -m pip install git+https://github.com/TadaSoftware/PyNFe.git

if errorlevel 1 (
    echo.
    echo ❌ Erro ao instalar PyNFe!
    echo.
    echo Possíveis causas:
    echo 1. Git não está instalado
    echo 2. Sem conexão com a internet
    echo 3. Repositório GitHub inacessível
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo Verificando instalação...
echo ========================================
echo.

python -c "try:
    import pynfe
    print('✅ PyNFe instalado com sucesso!')
    print('✅ Pronto para usar!')
except ImportError:
    print('❌ PyNFe não foi instalado corretamente')
    exit(1)"

if errorlevel 1 (
    echo.
    echo ❌ PyNFe não está funcionando corretamente
    pause
    exit /b 1
)

echo.
echo ========================================
echo ✅ Instalação concluída!
echo ========================================
echo.
echo Agora você pode iniciar o servidor com:
echo   start_local.bat
echo.
pause



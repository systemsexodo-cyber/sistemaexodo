@echo off
echo ========================================
echo TESTE RAPIDO - Backend PyNFe
echo ========================================
echo.

echo 1. Verificando se backend esta rodando...
curl -s http://localhost:5000/health
if %errorlevel% neq 0 (
    echo.
    echo ERRO: Backend nao esta rodando!
    echo Inicie o servidor: .\iniciar_simples.bat
    pause
    exit /b 1
)

echo.
echo 2. Verificando PyNFe...
.\venv\Scripts\python.exe -c "import pynfe; print('PyNFe OK')" 2>nul
if %errorlevel% neq 0 (
    echo ERRO: PyNFe nao esta instalado!
    echo Instale: .\venv\Scripts\python.exe -m pip install git+https://github.com/TadaSoftware/PyNFe.git
    pause
    exit /b 1
)

echo.
echo ========================================
echo Backend esta pronto para testes!
echo ========================================
echo.
echo Para testar validacao de certificado:
echo   .\venv\Scripts\python.exe testar_certificado.py certificado.pfx
echo.
echo Para testar emissao de NFC-e:
echo   .\venv\Scripts\python.exe testar_emissao_nfce.py config.json
echo.
pause


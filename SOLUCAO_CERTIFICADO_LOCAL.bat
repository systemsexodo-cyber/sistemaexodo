@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    SOLUCAO DEFINITIVA - CERTIFICADO LOCAL
echo ============================================
echo.
echo Este script configura o certificado para ser
echo lido de um arquivo local (evita problemas
echo com Supabase e tamanho do base64).
echo.
pause

echo.
echo ============================================
echo PASSO 1: Criar pasta do certificado
echo ============================================
echo.

set CERT_DIR=C:\ExodoNFCe\certificado
if not exist "%CERT_DIR%" (
    mkdir "%CERT_DIR%"
    echo ✅ Pasta criada: %CERT_DIR%
) else (
    echo ✅ Pasta ja existe: %CERT_DIR%
)

echo.
echo ============================================
echo PASSO 2: Instrucoes para copiar certificado
echo ============================================
echo.
echo AGORA FACA O SEGUINTE:
echo.
echo 1. Exporte seu certificado do Windows:
echo    - Abra o certificado (e-CPF/e-CNPJ Manager)
echo    - Exportar como .pfx
    - Use senha SIMPLES (ex: 123456)
echo    - Salve em: %CERT_DIR%\certificado.pfx
echo.
echo 2. Crie um arquivo de configuracao:
echo    - Abra o Bloco de Notas
echo    - Digite a senha do certificado
echo    - Salve como: %CERT_DIR%\senha.txt
echo.
pause

echo.
echo ============================================
echo PASSO 3: Verificar arquivos
echo ============================================
echo.

if exist "%CERT_DIR%\certificado.pfx" (
    echo ✅ Certificado encontrado!
    for %%I in ("%CERT_DIR%\certificado.pfx") do echo    Tamanho: %%~zI bytes
) else (
    echo ❌ Certificado NAO encontrado!
    echo    Esperado: %CERT_DIR%\certificado.pfx
    echo.
    echo Coloque o certificado nesta pasta e execute novamente.
    pause
    exit /b 1
)

if exist "%CERT_DIR%\senha.txt" (
    echo ✅ Arquivo de senha encontrado!
    set /p SENHA=<"%CERT_DIR%\senha.txt"
    echo    Senha tem %SENHA:~0,1%*** caracteres
) else (
    echo ⚠️ Arquivo de senha nao encontrado.
    echo    Voce precisara digitar a senha manualmente.
)

echo.
echo ============================================
echo PASSO 4: Configurar Bridge para usar certificado local
echo ============================================
echo.

cd /d "%~dp0backend_nfce"

:: Criar arquivo de configuracao local
(
echo {  
echo   "certificado_path": "C:/ExodoNFCe/certificado/certificado.pfx",
echo   "certificado_senha": "!SENHA!"
echo }
) > config_certificado.json

echo ✅ Configuracao criada: config_certificado.json

echo.
echo ============================================
echo PASSO 5: Testar certificado
echo ============================================
echo.
echo Para testar, execute:
echo    INICIAR_V351.bat
echo.
echo O bridge vai tentar usar o certificado local.
echo.
pause

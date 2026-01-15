@echo off
chcp 65001 >nul
echo ========================================
echo   CONVERSOR DE CERTIFICADO PFX PARA PEM
echo ========================================
echo.

REM Verificar se OpenSSL está disponível
where openssl >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] OpenSSL não encontrado!
    echo.
    echo Por favor, instale o OpenSSL:
    echo 1. Baixe em: https://slproweb.com/products/Win32OpenSSL.html
    echo 2. Ou use Git Bash (já vem com OpenSSL)
    echo 3. Ou use WSL (Windows Subsystem for Linux)
    echo.
    pause
    exit /b 1
)

echo [OK] OpenSSL encontrado!
echo.

REM Solicitar arquivo PFX
set /p arquivo_pfx="Digite o caminho completo do arquivo PFX: "
if not exist "%arquivo_pfx%" (
    echo [ERRO] Arquivo não encontrado: %arquivo_pfx%
    pause
    exit /b 1
)

echo.
set /p senha="Digite a senha do certificado PFX: "

REM Obter diretório do arquivo
for %%F in ("%arquivo_pfx%") do set diretorio=%%~dpF
for %%F in ("%arquivo_pfx%") do set nome_base=%%~nF

echo.
echo ========================================
echo   Convertendo certificado...
echo ========================================
echo.

REM Extrair certificado público
echo [1/2] Extraindo certificado público...
openssl pkcs12 -in "%arquivo_pfx%" -clcerts -nokeys -out "%diretorio%%nome_base%.crt" -passin pass:%senha%
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao extrair certificado público!
    echo Verifique se a senha está correta.
    pause
    exit /b 1
)
echo [OK] Certificado público salvo em: %diretorio%%nome_base%.crt

echo.

REM Extrair chave privada
echo [2/2] Extraindo chave privada...
openssl pkcs12 -in "%arquivo_pfx%" -nocerts -nodes -out "%diretorio%%nome_base%_chave_privada.pem" -passin pass:%senha%
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao extrair chave privada!
    echo Verifique se a senha está correta.
    pause
    exit /b 1
)
echo [OK] Chave privada salva em: %diretorio%%nome_base%_chave_privada.pem

echo.
echo ========================================
echo   CONVERSÃO CONCLUÍDA COM SUCESSO!
echo ========================================
echo.
echo Arquivos gerados:
echo   - %nome_base%.crt (certificado público)
echo   - %nome_base%_chave_privada.pem (chave privada)
echo.
echo Localização: %diretorio%
echo.
echo NOTA: A chave privada não tem senha (flag -nodes).
echo       Mantenha esses arquivos seguros!
echo.
pause





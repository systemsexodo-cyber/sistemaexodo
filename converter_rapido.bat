@echo off
chcp 65001 >nul
echo ========================================
echo   CONVERSOR RÁPIDO PFX → PEM
echo ========================================
echo.

set /p CAMINHO_PFX="Cole o caminho completo do certificado PFX: "
set /p SENHA="Digite a senha do certificado: "

echo.
echo Convertendo...

REM Tentar OpenSSL do Git
set OPENSSL="C:\Program Files\Git\usr\bin\openssl.exe"
if not exist %OPENSSL% (
    set OPENSSL="C:\Program Files (x86)\Git\usr\bin\openssl.exe"
)

REM Obter diretório e nome
for %%F in ("%CAMINHO_PFX%") do (
    set DIR_ARQUIVO=%%~dpF
    set NOME_ARQUIVO=%%~nF
)

set PEM_FINAL=%DIR_ARQUIVO%%NOME_ARQUIVO%.pem

REM Converter
%OPENSSL% pkcs12 -in "%CAMINHO_PFX%" -out "%PEM_FINAL%" -nodes -passin pass:%SENHA%

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo   SUCESSO!
    echo ========================================
    echo.
    echo Arquivo PEM criado:
    echo   %PEM_FINAL%
    echo.
) else (
    echo.
    echo ERRO na conversão!
    echo.
    echo Possíveis causas:
    echo   - Senha incorreta
    echo   - Certificado corrompido
    echo   - OpenSSL não encontrado
    echo.
)

pause




